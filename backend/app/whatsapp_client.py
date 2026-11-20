# -*- coding: utf-8 -*-
"""خدمة واتساب: إدارة الجلسة والربط والأحداث والإرسال عبر مكتبة neonize.

يعمل العميل داخل خيط مستقل، وتتم معالجة كل استدعاءات neonize داخل كتل
try/except حتى لا يتوقف السيرفر عند أي خطأ شبكة أو وسائط مفقودة.
"""
import json
import logging
import os
import re
import threading
import time
import traceback
import uuid

import requests

import neonize.utils.jid  # يضبط مسارات بروتوكولات neonize
from neonize.client import NewClient
from neonize.events import (
    ConnectedEv, MessageEv, ReceiptEv, ChatPresenceEv, LoggedOutEv, StreamErrorEv,
    ConnectFailureEv, DisconnectedEv, KeepAliveTimeoutEv, KeepAliveRestoredEv,
    UserAboutEv, PushNameEv, PictureEv, NewsletterLiveUpdateEV, HistorySyncEv,
    UndecryptableMessageEv, GroupInfoEv, JoinedGroupEv, PairStatusEv, PresenceEv,
    NewsletterJoinEv, NewsletterLeaveEv,
)
from neonize.proto import Neonize_pb2 as np
from neonize.utils.enum import ChatPresence, ChatPresenceMedia, ReceiptType, VoteType
from neonize.utils.jid import Jid2String, JIDToNonAD, build_jid

from . import database as db
from .config import (
    DOWNLOAD_DIR, MEDIA_DIR, AVATARS_DIR, AVATAR_FETCH_TIMEOUT, SESSION_NAME,
    HISTORY_MSGS_PER_CHAT, HISTORY_MEDIA_MAX_AGE_DAYS,
)
from .media_worker import MediaWorker
from .state import state, ws_manager

logger = logging.getLogger("whatsapp.client")

WRAPPER_FIELDS = ("ephemeralMessage", "viewOnceMessage", "viewOnceMessageV2", "viewOnceMessageV2Extension")


def jid_str(j) -> str:
    """تحويل كائن JID إلى نص موحد user@server."""
    try:
        return Jid2String(JIDToNonAD(j))
    except Exception:
        try:
            server = getattr(j, "Server", "") or ""
            user = getattr(j, "User", "") or ""
            if user and server:
                return f"{user}@{server}"
        except Exception:
            pass
    return str(j)


def parse_jid(jid: str):
    """تحويل نص JID إلى كائن JID."""
    jid = (jid or "").strip()
    if "@" in jid:
        user, server = jid.split("@", 1)
    else:
        user, server = jid, "s.whatsapp.net"
    user = user.split(".", 1)[0]  # إزالة لاحقة الجهاز
    try:
        return build_jid(user, server)
    except Exception:
        j = np.MessageInfo().MessageSource.Chat
        j.User = user
        j.Server = server
        return j


def _media_kind(inner) -> str | None:
    """تحديد نوع المحتوى من الرسالة الداخلية."""
    checks = (
        "reactionMessage", "protocolMessage", "conversation", "extendedTextMessage",
        "imageMessage", "stickerMessage", "videoMessage", "audioMessage",
        "documentMessage", "contactMessage", "locationMessage", "liveLocationMessage",
        "pollCreationMessageV6", "pollCreationMessageV5", "pollCreationMessageV4",
        "pollCreationMessageV3", "pollCreationMessageV2", "pollCreationMessage",
    )
    for name in checks:
        try:
            if inner.HasField(name):
                return name
        except Exception:
            continue
    return None


def _preview_for(mtype: str) -> str:
    return {
        "image": "صورة", "video": "فيديو", "audio": "رسالة صوتية",
        "document": "مستند", "sticker": "ملصق", "poll": "استطلاع رأي",
        "location": "موقع", "contact": "جهة اتصال", "unknown": "رسالة",
    }.get(mtype, "رسالة")


def _safe_jid(jid: str) -> str:
    return "".join(ch for ch in (jid or "unknown") if ch.isalnum() or ch in "-_@")[:120]


def _extract_invite_code(link: str) -> str:
    link = (link or "").strip()
    if "chat.whatsapp.com/" in link:
        return link.split("chat.whatsapp.com/")[1].split("/")[0].split("?")[0]
    if re.fullmatch(r"[A-Za-z0-9_-]{15,}", link):
        return link
    return ""


def _extract_newsletter_key(invite: str) -> str:
    invite = (invite or "").strip()
    if "whatsapp.com/channel/" in invite:
        return invite.split("whatsapp.com/channel/")[1].split("/")[0].split("?")[0]
    if "@" in invite:
        return invite
    return invite


class WhatsAppService:
    """غلاف كامل حول neonize: الربط، الأحداث، الإرسال، الوسائط، القنوات والمجموعات."""

    def __init__(self) -> None:
        self.client: NewClient | None = None
        self.conn_state = "init"  # init|connecting|connected|reconnecting|unpaired|logged_out
        self.paired = False
        self.qr_svg: str | None = None
        self.qr_codes: list[str] = []
        self.pairing_code: str | None = None
        self.pair_error: str | None = None
        self.me_info: dict = {}
        self.stop_requested = False
        self.media_worker = MediaWorker(self)

    # ------------------------------------------------------------ عام
    def start(self) -> None:
        self.media_worker.start()
        threading.Thread(target=self._run_forever, daemon=True, name="wa-service").start()

    def shutdown(self) -> None:
        self.stop_requested = True
        try:
            if self.client is not None:
                self.client.stop()
        except Exception:
            pass

    def _set_state(self, new_state: str) -> None:
        if self.conn_state == new_state:
            return
        self.conn_state = new_state
        self.broadcast_status()

    def broadcast_status(self) -> None:
        ws_manager.broadcast_threadsafe({
            "type": "connection",
            "state": self.conn_state,
            "paired": self.paired,
            "qr": self.qr_svg,
            "pairing_code": self.pairing_code,
            "pair_error": self.pair_error,
            "me": self.me_info,
        })

    def _run_forever(self) -> None:
        """حلقة إعادة تشغيل العميل عند أي انهيار غير متوقع."""
        while not self.stop_requested:
            try:
                self._connect_cycle()
            except Exception:
                logger.exception("انهارت دورة الاتصال: %s", traceback.format_exc(limit=2))
            if self.stop_requested:
                break
            if self.conn_state == "connected":
                self._set_state("reconnecting")
            elif self.conn_state != "logged_out":
                self._set_state("connecting")
            for _ in range(50):
                if self.stop_requested:
                    break
                time.sleep(0.2)

    def _connect_cycle(self) -> None:
        logger.info("إنشاء عميل واتساب جديد (جلسة: %s)", os.path.basename(SESSION_NAME))
        client = NewClient(SESSION_NAME)
        self.client = client
        self._register_events(client)
        self.qr_svg = None
        self.pairing_code = None
        if not self.paired:
            self._set_state("connecting")
        client.connect()

    def _is_connected_safe(self) -> bool:
        try:
            return bool(self.client.is_connected) if self.client else False
        except Exception:
            return False

    # ------------------------------------------------------------ الأحداث
    def _register_events(self, client: NewClient) -> None:
        service = self

        @client.qr
        def on_qr(cl, data) -> None:
            try:
                code = data.decode("utf-8", "ignore") if isinstance(data, (bytes, bytearray)) else str(data)
                service._on_qr_code(code)
            except Exception:
                logger.exception("خطأ معالجة QR")

        @client.event(ConnectedEv)
        def on_connected(cl, evt) -> None:
            try:
                service.paired = True
                service.qr_svg = None
                service.qr_codes = []
                service.pairing_code = None
                service.pair_error = None
                service._set_state("connected")
                service._load_me(cl)
                service._subscribe_newsletters(cl)
                logger.info("تم الاتصال بحساب واتساب بنجاح")
            except Exception:
                logger.exception("خطأ بعد الاتصال")

        @client.event(MessageEv)
        def on_message(cl, evt) -> None:
            try:
                service._handle_message(evt)
            except Exception:
                logger.exception("خطأ معالجة رسالة واردة")

        @client.event(ReceiptEv)
        def on_receipt(cl, evt) -> None:
            try:
                service._handle_receipt(evt)
            except Exception:
                logger.exception("خطأ معالجة إيصال")

        @client.event(ChatPresenceEv)
        def on_chat_presence(cl, evt) -> None:
            try:
                chat = jid_str(evt.MessageSource.Chat)
                composing = "COMPOSING" in str(getattr(evt.State, "name", evt.State))
                audio = "AUDIO" in str(getattr(evt.Media, "name", evt.Media))
                ws_manager.broadcast_threadsafe({
                    "type": "typing", "chat": chat,
                    "state": "typing" if composing else "paused",
                    "media": "audio" if audio else "text",
                })
            except Exception:
                logger.exception("خطأ حالة الكتابة")

        @client.event(PresenceEv)
        def on_presence(cl, evt) -> None:
            try:
                ws_manager.broadcast_threadsafe({
                    "type": "presence", "jid": jid_str(getattr(evt, "From")),
                    "available": not bool(getattr(evt, "Unavailable", False)),
                    "lastseen": int(getattr(evt, "LastSeen", 0) or 0),
                })
            except Exception:
                logger.debug("خطأ حضور مستخدم")

        @client.event(UserAboutEv)
        def on_about(cl, evt) -> None:
            try:
                ws_manager.broadcast_threadsafe({
                    "type": "about", "jid": jid_str(getattr(evt, "JID")),
                    "status": getattr(evt, "Status", ""),
                })
            except Exception:
                logger.debug("خطأ نبذة مستخدم")

        @client.event(PushNameEv)
        def on_push_name(cl, evt) -> None:
            try:
                jid = jid_str(getattr(evt, "JID"))
                name = getattr(evt, "NewPushName", "") or getattr(evt, "Message", "")
                if name and db.get_chat(jid):
                    db.upsert_chat(jid, name=name)
                    ws_manager.broadcast_threadsafe({"type": "chat_name", "jid": jid, "name": name})
            except Exception:
                logger.debug("خطأ اسم مستخدم")

        @client.event(PictureEv)
        def on_picture(cl, evt) -> None:
            try:
                jid = jid_str(getattr(evt, "JID"))
                service.invalidate_avatar(jid)
                ws_manager.broadcast_threadsafe({"type": "avatar_changed", "jid": jid})
            except Exception:
                logger.debug("خطأ صورة شخصية")

        @client.event(PairStatusEv)
        def on_pair_status(cl, evt) -> None:
            try:
                status_name = str(getattr(evt.Status, "name", evt.Status))
                if "SUCCESS" not in status_name:
                    service.pair_error = "فشل الإقران، تأكد من الرقم وأدخل الكود في الهاتف"
                    ws_manager.broadcast_threadsafe({"type": "pair_error", "error": service.pair_error})
            except Exception:
                logger.debug("خطأ حالة الإقران")

        @client.event(LoggedOutEv)
        def on_logged_out(cl, evt) -> None:
            try:
                logger.warning("تم تسجيل الخروج من الجلسة: %s", getattr(evt, "Reason", ""))
                service.paired = False
                service._set_state("logged_out")
            except Exception:
                logger.exception("خطأ تسجيل خروج")

        @client.event(StreamErrorEv)
        def on_stream_error(cl, evt) -> None:
            logger.warning("خطأ تدفق: %s", getattr(evt, "Code", ""))
            if not service._is_connected_safe():
                service._set_state("reconnecting")

        @client.event(ConnectFailureEv)
        def on_connect_failure(cl, evt) -> None:
            logger.warning("فشل اتصال: %s", getattr(evt, "Reason", ""))
            service._set_state("reconnecting")

        @client.event(DisconnectedEv)
        def on_disconnected(cl, evt) -> None:
            if service.stop_requested:
                return
            logger.warning("انقطع الاتصال بخوادم واتساب")
            if not service._is_connected_safe():
                service._set_state("reconnecting")

        @client.event(KeepAliveTimeoutEv)
        def on_keepalive_timeout(cl, evt) -> None:
            logger.debug("انتهت مهلة الاتصال الدوري")
            service._set_state("reconnecting")

        @client.event(KeepAliveRestoredEv)
        def on_keepalive_restored(cl, evt) -> None:
            if service.paired:
                service._set_state("connected")

        @client.event(UndecryptableMessageEv)
        def on_undecryptable(cl, evt) -> None:
            try:
                info = getattr(evt, "Info")
                chat = jid_str(info.MessageSource.Chat)
                sender = jid_str(info.MessageSource.Sender) or chat
                ts = int(getattr(info, "Timestamp", 0) or time.time())
                db.insert_message({
                    "chat_jid": chat, "id": getattr(info, "ID", ""), "sender": sender,
                    "sender_name": getattr(info, "Pushname", ""),
                    "from_me": bool(info.MessageSource.IsFromMe), "type": "unknown",
                    "body": "رسالة غير قابلة لفك التشفير على هذا الجهاز",
                    "timestamp": ts, "receipt": "delivered",
                })
                db.upsert_chat(chat, last_message="رسالة غير قابلة لفك التشفير",
                               last_time=ts, is_group=bool(info.MessageSource.IsGroup),
                               bump_unread=(not info.MessageSource.IsFromMe))
                ws_manager.broadcast_threadsafe({"type": "chat_updated", "chat": chat})
            except Exception:
                logger.exception("خطأ رسالة غير مفكوكة")

        @client.event(GroupInfoEv)
        def on_group_info(cl, evt) -> None:
            try:
                chat = jid_str(getattr(evt, "JID"))
                if db.get_chat(chat):
                    service.refresh_group_meta(chat)
            except Exception:
                logger.debug("خطأ معلومات مجموعة")

        @client.event(JoinedGroupEv)
        def on_joined_group(cl, evt) -> None:
            try:
                info = getattr(evt, "GroupInfo")
                chat = jid_str(getattr(info, "JID"))
                db.upsert_chat(chat, name=getattr(info, "GroupName", "") or chat,
                               is_group=True, last_time=int(time.time()))
                ws_manager.broadcast_threadsafe({"type": "chat_updated", "chat": chat})
            except Exception:
                logger.exception("خطأ انضمام مجموعة")

        @client.event(NewsletterJoinEv)
        def on_newsletter_join(cl, evt) -> None:
            try:
                meta = getattr(evt, "NewsletterMetadata")
                service._store_newsletter_meta(meta)
                ws_manager.broadcast_threadsafe({"type": "channels_updated"})
            except Exception:
                logger.debug("خطأ انضمام قناة")

        @client.event(NewsletterLeaveEv)
        def on_newsletter_leave(cl, evt) -> None:
            try:
                chat = jid_str(getattr(evt, "ID"))
                db.x("DELETE FROM chats WHERE jid=?", (chat,))
                ws_manager.broadcast_threadsafe({"type": "channels_updated"})
            except Exception:
                logger.debug("خطأ مغادرة قناة")

        @client.event(NewsletterLiveUpdateEV)
        def on_newsletter_live(cl, evt) -> None:
            try:
                chat = jid_str(getattr(evt, "JID"))
                ts = int(getattr(evt, "TIME", 0) or time.time())
                for nmsg in getattr(evt, "Messages", []):
                    service._store_newsletter_message(chat, nmsg, ts)
            except Exception:
                logger.exception("خطأ منشورات القناة")

        @client.event(HistorySyncEv)
        def on_history_sync(cl, evt) -> None:
            try:
                service._handle_history_sync(evt)
            except Exception:
                logger.exception("خطأ مزامنة التاريخ")

        try:
            @client.event.paircode
            def on_pair_code(cl, code: str, connected: bool) -> None:
                try:
                    if connected:
                        service.pairing_code = None
                        logger.info("اكتمل الإقران بالكود بنجاح")
                    else:
                        service.pairing_code = code
                        ws_manager.broadcast_threadsafe({"type": "pairing_code", "code": code})
                except Exception:
                    logger.exception("خطأ استدعاء كود الإقران")
        except Exception:
            logger.exception("تعذر تسجيل استدعاء كود الإقران")

    # ------------------------------------------------------------ QR والإقران
    def _on_qr_code(self, code: str) -> None:
        self.qr_codes.append(code)
        self.paired = False
        self.qr_svg = self._make_qr_svg(code)
        self._set_state("unpaired")
        self.broadcast_status()
        logger.info("تم توليد رمز QR جديد للإقران")

    @staticmethod
    def _make_qr_svg(payload: str) -> str | None:
        try:
            import io
            import base64
            import qrcode
            import qrcode.image.svg
            img = qrcode.make(payload, image_factory=qrcode.image.svg.SvgPathImage,
                              box_size=14, border=2)
            buf = io.BytesIO()
            img.save(buf)
            svg = buf.getvalue().decode("utf-8")
            return "data:image/svg+xml;base64," + base64.b64encode(svg.encode()).decode()
        except Exception:
            logger.exception("فشل توليد صورة QR")
            return None

    def request_pair(self, phone: str) -> dict:
        """طلب ربط عبر كود الإقران: يفتح client.connect أولاً في خيط منفصل ثم PairPhone."""
        phone = re.sub(r"[^\d]", "", phone or "")
        if not 7 <= len(phone) <= 15:
            return {"ok": False, "error": "رقم غير صالح، أدخل الرقم مع كود الدولة بدون +"}
        if self.client is None:
            return {"ok": False, "error": "العميل غير جاهز بعد، انتظر ثوانٍ وأعد المحاولة"}
        if self.paired:
            return {"ok": False, "error": "الحساب مقترن مسبقاً"}
        client = self.client
        self.pair_error = None

        def worker():
            try:
                # الانتظار حتى يستقر الاتصال (معالجة خطأ client is nil)
                deadline = time.time() + 20
                while time.time() < deadline:
                    try:
                        if client.is_connected:
                            break
                    except Exception:
                        pass
                    time.sleep(0.25)
                # الانتظار 2.5 ثانية قبل استدعاء PairPhone
                time.sleep(2.5)
                code = client.PairPhone(phone, True)
                self.pairing_code = code
                logger.info("تم توليد كود إقران للرقم %s", phone)
                ws_manager.broadcast_threadsafe({"type": "pairing_code", "code": code})
                self.broadcast_status()
            except Exception as exc:
                self.pair_error = f"فشل توليد كود الإقران: {exc}"
                logger.exception("فشل PairPhone")
                ws_manager.broadcast_threadsafe({"type": "pair_error", "error": self.pair_error})

        threading.Thread(target=worker, daemon=True, name="pair-phone").start()
        return {"ok": True}

    # ------------------------------------------------------------ الرسائل الواردة
    def _handle_message(self, evt, from_history: bool = False) -> None:
        info = getattr(evt, "Info", None)
        if info is None:
            return
        src = info.MessageSource
        chat = jid_str(src.Chat)
        sender = jid_str(src.Sender) or chat
        from_me = bool(src.IsFromMe)
        is_group = bool(src.IsGroup)
        msg_id = getattr(info, "ID", "") or ""
        ts = int(getattr(info, "Timestamp", 0) or time.time())
        pushname = getattr(info, "Pushname", "") or ""

        if chat.endswith("@newsletter"):
            return
        if chat == "status@broadcast":
            self._store_status(evt, sender, pushname, msg_id, ts)
            return

        inner = evt.Message
        for _ in range(5):
            changed = False
            for wf in WRAPPER_FIELDS:
                try:
                    if inner.HasField(wf):
                        inner = getattr(getattr(inner, wf), "Message")
                        changed = True
                except Exception:
                    continue
            try:
                if inner.HasField("documentWithCaptionMessage"):
                    doc = getattr(inner.documentWithCaptionMessage, "Message", None)
                    cand = getattr(doc, "documentMessage", None) if doc is not None else None
                    if cand is not None:
                        inner = cand
                        changed = True
            except Exception:
                pass
            if not changed:
                break

        kind = _media_kind(inner)

        if kind == "protocolMessage":
            pmsg = inner.protocolMessage
            ptype = str(getattr(pmsg.Type, "name", pmsg.Type))
            target_id = getattr(pmsg.Key, "ID", "")
            if target_id and ("REVOKE" in ptype or "DELETE" in ptype):
                db.mark_deleted(chat, target_id)
                ws_manager.broadcast_threadsafe({"type": "message_deleted", "chat": chat, "id": target_id})
            return

        if kind == "reactionMessage":
            rmsg = inner.reactionMessage
            target_id = getattr(rmsg.Key, "ID", "")
            emoji = getattr(rmsg, "Text", "")
            if target_id:
                row = db.get_message(chat, target_id)
                if row:
                    reactions = json.loads(row["reactions"] or "{}")
                    reactions[emoji] = sender
                    db.set_reactions(chat, target_id, json.dumps(reactions, ensure_ascii=False))
                    ws_manager.broadcast_threadsafe({
                        "type": "reaction", "chat": chat, "id": target_id, "reactions": reactions,
                    })
            return

        content = getattr(inner, kind, None) if kind else None
        row = {
            "chat_jid": chat, "id": msg_id,
            "sender": chat if (from_me or not is_group) else sender,
            "sender_name": "أنا" if from_me else (pushname or sender.split("@")[0]),
            "from_me": from_me, "type": "unknown", "body": "",
            "timestamp": ts, "receipt": "pending" if from_me else "delivered",
            "proto": evt.SerializeToString(),
        }

        if kind == "conversation":
            row["type"] = "text"
            row["body"] = getattr(content, "conversation", "")
        elif kind == "extendedTextMessage":
            row["type"] = "text"
            row["body"] = getattr(content, "text", "")
        elif kind in ("imageMessage", "videoMessage", "audioMessage", "documentMessage", "stickerMessage"):
            type_map = {"imageMessage": "image", "videoMessage": "video", "audioMessage": "audio",
                        "documentMessage": "document", "stickerMessage": "sticker"}
            row["type"] = type_map[kind]
            row["body"] = getattr(content, "caption", "") or ""
            row["media_mime"] = getattr(content, "mimetype", "")
            row["media_size"] = int(getattr(content, "fileLength", 0) or 0)
            row["media_state"] = "pending"
            if kind == "documentMessage":
                row["media_name"] = getattr(content, "fileName", "") or "ملف"
            if kind == "audioMessage":
                row["media_duration"] = int(getattr(content, "seconds", 0) or 0)
            if kind in ("videoMessage", "imageMessage"):
                row["media_width"] = int(getattr(content, "width", 0) or 0)
                row["media_height"] = int(getattr(content, "height", 0) or 0)
        elif kind == "contactMessage":
            row["type"] = "contact"
            row["body"] = f"{getattr(content, 'displayName', '')} — {getattr(content, 'vcard', '')}"[:500]
        elif kind in ("locationMessage", "liveLocationMessage"):
            row["type"] = "location"
            row["body"] = getattr(content, "comment", "") or "موقع جغرافي"
            row["media_width"] = int(float(getattr(content, "degreesLatitude", 0) or 0) * 1e6)
            row["media_height"] = int(float(getattr(content, "degreesLongitude", 0) or 0) * 1e6)
        elif kind and kind.startswith("pollCreationMessage"):
            row["type"] = "poll"
            row["poll_name"] = getattr(content, "name", "استطلاع")
            options = [getattr(o, "optionName", "") for o in getattr(content, "options", [])]
            row["poll_options"] = json.dumps(options, ensure_ascii=False)
            row["body"] = row["poll_name"]
        else:
            row["type"] = "unknown"
            row["body"] = "رسالة غير مدعومة للعرض"

        # الاقتباس (رد باقتباس)
        try:
            ctx = getattr(content, "contextInfo", None)
            if ctx is not None and kind not in ("conversation", "protocolMessage", "reactionMessage"):
                quoted = getattr(ctx, "quotedMessage", None)
                stanza = getattr(ctx, "stanzaID", "") or ""
                if quoted is not None and stanza:
                    qkind = _media_kind(quoted) or ""
                    qbody = ""
                    if qkind == "conversation":
                        qbody = getattr(quoted, "conversation", "")
                    elif qkind == "extendedTextMessage":
                        qbody = getattr(quoted.extendedTextMessage, "text", "")
                    elif qkind and hasattr(quoted, qkind):
                        qobj = getattr(quoted, qkind)
                        qbody = getattr(qobj, "caption", "") or getattr(qobj, "fileName", "") or ""
                    row["quoted_id"] = stanza
                    part = getattr(ctx, "participant", "")
                    row["quoted_sender"] = Jid2String(part) if part else ""
                    row["quoted_type"] = qkind.replace("Message", "") or "text"
                    row["quoted_body"] = qbody[:300]
                    row["quoted_from_me"] = bool(row["quoted_sender"]) and row["quoted_sender"] == self.me_info.get("jid")
        except Exception:
            logger.debug("تعذر استخراج الاقتباس")

        first_time = not db.message_exists(chat, msg_id)
        db.insert_message(row)

        display = (row["body"] or _preview_for(row["type"]))[:120]
        db.upsert_chat(
            chat,
            name=pushname or None,
            last_message=display,
            last_time=ts,
            is_group=is_group,
            bump_unread=(not from_me and not from_history and chat != state.open_chat),
        )

        # علامة القراءة: فقط إذا كانت المحادثة مفتوحة أمام المستخدم
        if not from_history and not from_me and chat == state.open_chat:
            self._mark_read_safe(chat, [msg_id], sender)

        if not from_history:
            ws_manager.broadcast_threadsafe({
                "type": "message", "chat": chat, "message": self.row_to_json(row),
            })
            db.upsert_chat(chat, last_time=ts)

        # تنزيل الوسائط تلقائياً
        if row["type"] in ("image", "video", "audio", "document", "sticker"):
            fresh_enough = (not from_history) or (ts >= int(time.time()) - HISTORY_MEDIA_MAX_AGE_DAYS * 86400)
            if fresh_enough:
                self.media_worker.enqueue(
                    chat, msg_id, evt.SerializeToString(), "media",
                    mime=row.get("media_mime", ""),
                    filename=row.get("media_name", ""),
                    ptt=(kind == "audioMessage" and bool(getattr(content, "PTT", False))),
                )

        if first_time and is_group and not from_history:
            self.refresh_group_meta(chat, silent=True)

    def _store_status(self, evt, sender: str, pushname: str, msg_id: str, ts: int) -> None:
        """حفظ حالة واردة (نص/صورة/فيديو) مع تنزيل وسائطها تلقائياً."""
        inner = evt.Message
        kind = _media_kind(inner)
        if kind is None:
            return
        sid = f"{sender}:{msg_id or ts}"
        row = {
            "id": sid, "sender": sender,
            "sender_name": pushname or sender.split("@")[0],
            "type": "text", "body": "", "media_state": "none", "timestamp": ts,
        }
        content = getattr(inner, kind, None)
        if kind == "conversation":
            row["body"] = getattr(content, "conversation", "")
        elif kind == "extendedTextMessage":
            row["body"] = getattr(content, "text", "")
        elif kind in ("imageMessage", "videoMessage"):
            row["type"] = "image" if kind == "imageMessage" else "video"
            row["media_mime"] = getattr(content, "mimetype", "")
            row["body"] = getattr(content, "caption", "") or ""
            row["media_state"] = "pending"
        else:
            return
        db.insert_status(row)
        ws_manager.broadcast_threadsafe({"type": "status", "status": row})
        if row["type"] in ("image", "video"):
            self.media_worker.enqueue(
                "status@broadcast", sid, evt.SerializeToString(), "status",
                mime=row.get("media_mime", ""),
            )

    def _store_newsletter_meta(self, meta) -> None:
        try:
            nlid = jid_str(getattr(meta, "ID"))
            thread = getattr(meta, "ThreadMeta", None)
            name = getattr(thread, "Name", "") or nlid.split("@")[0]
            desc = getattr(thread, "Description", "")
            subs = int(getattr(thread, "SubscriberCount", 0) or 0)
            db.upsert_chat(nlid, name=name, last_message=desc, is_newsletter=True,
                           members=subs, is_group=False)
            threading.Thread(target=self._fetch_newsletter_avatar, args=(nlid,),
                             daemon=True, name=f"nl-avatar-{nlid[:8]}").start()
        except Exception:
            logger.exception("تعذر حفظ بيانات قناة")

    def _store_newsletter_message(self, chat: str, nmsg, ts: int) -> None:
        server_id = int(getattr(nmsg, "MessageServerID", 0) or 0)
        if not server_id:
            return
        msg_id = f"nwsrv-{server_id}"
        inner = getattr(nmsg, "Message", None)
        if inner is None:
            return
        kind = _media_kind(inner)
        content = getattr(inner, kind, None) if kind else None
        body, mtype = "", "unknown"
        if kind == "conversation":
            mtype, body = "text", getattr(content, "conversation", "")
        elif kind == "extendedTextMessage":
            mtype, body = "text", getattr(content, "text", "")
        elif kind in ("imageMessage", "videoMessage", "audioMessage", "documentMessage", "stickerMessage"):
            type_map = {"imageMessage": "image", "videoMessage": "video", "audioMessage": "audio",
                        "documentMessage": "document", "stickerMessage": "sticker"}
            mtype = type_map[kind]
            body = getattr(content, "caption", "") or ""
        else:
            body = "منشور قناة"
        if db.message_exists(chat, msg_id):
            return
        row = {
            "chat_jid": chat, "id": msg_id, "sender": chat, "sender_name": "",
            "from_me": False, "type": mtype, "body": body,
            "timestamp": ts or int(time.time()), "server_id": server_id,
            "media_state": "none",
            "media_mime": getattr(content, "mimetype", "") if content is not None else "",
            "media_size": int(getattr(content, "fileLength", 0) or 0) if content is not None else 0,
            "media_name": getattr(content, "fileName", "") if content is not None else "",
        }
        if mtype in ("image", "video", "audio", "document", "sticker"):
            row["media_state"] = "pending"
        db.insert_message(row)
        db.upsert_chat(chat, last_message=(body or _preview_for(mtype))[:120],
                       last_time=row["timestamp"], is_newsletter=True)
        ws_manager.broadcast_threadsafe({
            "type": "message", "chat": chat, "message": self.row_to_json(row),
        })
        if mtype in ("image", "video", "audio", "document", "sticker"):
            wrapper = np.Message()
            wrapper.Message.CopyFrom(inner)
            self.media_worker.enqueue(chat, msg_id, wrapper.SerializeToString(), "media",
                                      mime=row["media_mime"], filename=row["media_name"])

    def _handle_receipt(self, evt) -> None:
        ids = [i for i in (getattr(evt, "MessageIDs", []) or []) if i]
        if not ids:
            return
        rname = str(getattr(evt.Type, "name", evt.Type))
        if rname in ("READ", "PLAYED", "READ_SELF", "PLAYED_SELF"):
            receipt = "read"
        elif rname in ("DELIVERED", "SENDER"):
            receipt = "delivered"
        else:
            return
        chats = db.set_messages_receipt(ids, receipt)
        chat = ""
        try:
            chat = jid_str(getattr(evt, "MessageSource").Chat)
        except Exception:
            chat = chats[0] if chats else ""
        ws_manager.broadcast_threadsafe({"type": "receipt", "chat": chat, "ids": ids, "receipt": receipt})

    def _handle_history_sync(self, evt) -> None:
        """استعادة المحادثات والحالات الأخيرة من مزامنة التاريخ عند أول إقران."""
        data = getattr(evt, "Data", None)
        if data is None:
            return
        pushnames = {}
        try:
            for p in getattr(data, "pushnames", []):
                pushnames[jid_str(getattr(p, "ID"))] = getattr(p, "pushname", "")
        except Exception:
            pass

        chats_seen = []
        try:
            for conv in list(getattr(data, "conversations", []))[:80]:
                chat = getattr(conv, "ID", "") or ""
                if not chat or chat == "status@broadcast" or chat.endswith("@newsletter"):
                    continue
                is_group = "@g.us" in chat
                name = pushnames.get(chat)
                last_ts = int(getattr(conv, "lastMsgTimestamp", 0) or 0)
                unread = int(getattr(conv, "unreadCount", 0) or 0)
                db.upsert_chat(chat, name=name, last_time=max(last_ts, 1),
                               is_group=is_group, set_unread=unread)
                chats_seen.append(chat)
                for h in list(getattr(conv, "messages", []))[-HISTORY_MSGS_PER_CHAT:]:
                    try:
                        w = getattr(h, "message")
                        if w is None:
                            continue
                        key = getattr(w, "key")
                        msg_id = getattr(key, "ID", "")
                        if not msg_id or db.message_exists(chat, msg_id):
                            continue
                        e2e = getattr(w, "message")
                        if e2e is None:
                            continue
                        mts = int(getattr(w, "MessageTimestamp", 0) or 0)
                        from_me = bool(getattr(key, "FromMe", False))
                        participant = jid_str(getattr(key, "Participant", "")) if getattr(key, "Participant", "") else ""
                        sender = chat if (from_me or not participant) else participant
                        wrapper = np.Message()
                        wrapper.Info.ID = msg_id
                        wrapper.Info.Timestamp = mts
                        wrapper.Info.MessageSource.Chat.CopyFrom(parse_jid(chat))
                        wrapper.Info.MessageSource.Sender.CopyFrom(parse_jid(sender))
                        wrapper.Info.MessageSource.IsFromMe = from_me
                        wrapper.Info.MessageSource.IsGroup = is_group
                        wrapper.Message.CopyFrom(e2e)
                        self._handle_message(wrapper, from_history=True)
                    except Exception:
                        continue
        except Exception:
            logger.exception("فشل معالجة محادثات التاريخ")

        try:
            for sm in list(getattr(data, "statusV3Messages", []))[:30]:
                key = getattr(sm, "key")
                participant = jid_str(getattr(sm, "participant", "")) or "status@broadcast"
                msg_id = getattr(key, "ID", "")
                ts = int(getattr(sm, "messageTimestamp", 0) or int(time.time()))
                if not msg_id:
                    continue
                sid = f"{participant}:{msg_id}"
                if db.message_exists("status@broadcast", sid):
                    continue
                e2e = getattr(sm, "message")
                if e2e is None:
                    continue
                wrapper = np.Message()
                wrapper.Info.ID = msg_id
                wrapper.Info.Timestamp = ts
                wrapper.Info.MessageSource.Chat.CopyFrom(parse_jid("status@broadcast"))
                wrapper.Info.MessageSource.Sender.CopyFrom(parse_jid(participant))
                wrapper.Message.CopyFrom(e2e)
                self._store_status(wrapper, participant, getattr(sm, "pushName", ""), msg_id, ts)
        except Exception:
            logger.debug("تعذر استعادة حالات التاريخ")

        for chat in chats_seen:
            ws_manager.broadcast_threadsafe({"type": "history_synced", "chat": chat})
        ws_manager.broadcast_threadsafe({"type": "chats_updated"})

    def _load_me(self, client) -> None:
        try:
            device = client.get_me()
            self.me_info = {
                "jid": jid_str(getattr(device, "JID")),
                "pushname": getattr(device, "PushName", "") or "حسابي",
                "platform": str(getattr(device, "Platform", "")),
            }
        except Exception as exc:
            logger.warning("تعذر جلب بيانات حسابي: %s", exc)
        self.broadcast_status()

    def _subscribe_newsletters(self, client) -> None:
        """تفعيل التحديث اللحظي لكل القنوات المشترك بها."""
        def worker():
            time.sleep(2)
            try:
                for meta in client.get_subscribed_newletters():
                    self._store_newsletter_meta(meta)
                    try:
                        client.newsletter_subscribe_live_updates(parse_jid(jid_str(getattr(meta, "ID"))))
                    except Exception as exc:
                        logger.debug("تعذر تفعيل تحديثات القناة: %s", exc)
                ws_manager.broadcast_threadsafe({"type": "channels_updated"})
            except Exception:
                logger.debug("تعذر تحميل القنوات المشترك بها")

        threading.Thread(target=worker, daemon=True, name="newsletter-sub").start()

    # ------------------------------------------------------------ علامات القراءة والحضور
    def _mark_read_safe(self, chat: str, ids: list[str], sender: str = "") -> None:
        if state.privacy_read or not ids:
            return
        client = self.client
        if client is None:
            return
        try:
            client.mark_read(*ids, chat=parse_jid(chat), sender=parse_jid(sender or chat),
                             receipt=ReceiptType.READ)
            db.reset_unread(chat)
        except Exception as exc:
            logger.debug("تعذر تعليم القراءة %s: %s", chat, exc)

    def send_chat_presence(self, chat: str, composing: bool, audio: bool = False) -> None:
        client = self._require_client()
        st = ChatPresence.CHAT_PRESENCE_COMPOSING if composing else ChatPresence.CHAT_PRESENCE_PAUSED
        md = ChatPresenceMedia.CHAT_PRESENCE_MEDIA_AUDIO if audio else ChatPresenceMedia.CHAT_PRESENCE_MEDIA_TEXT
        client.send_chat_presence(parse_jid(chat), st, md)

    # ------------------------------------------------------------ الإرسال
    def _require_client(self) -> NewClient:
        client = self.client
        if client is None or not self._is_connected_safe():
            raise RuntimeError("العميل غير متصل بخوادم واتساب")
        return client

    def _load_quoted(self, chat: str, msg_id: str | None):
        """تحميل الرسالة المقتبسة من الأرشيف لبناء الرد."""
        if not msg_id:
            return None
        row = db.get_message(chat, msg_id)
        if row is None or not row["proto"]:
            return None
        try:
            return np.Message.FromString(row["proto"])
        except Exception:
            logger.debug("تعذر تحميل بروتوكول الاقتباس")
        return None

    def send_text(self, chat: str, body: str, reply_to: str | None = None) -> dict:
        client = self._require_client()
        to = parse_jid(chat)
        quoted = self._load_quoted(chat, reply_to) if reply_to else None
        if quoted is not None:
            resp = client.reply_message(body, quoted, to=to)
        else:
            resp = client.send_message(to, body)
        return self._sent_row(chat, "text", body, resp)

    def send_poll(self, chat: str, name: str, options: list[str], reply_to: str | None = None) -> dict:
        client = self._require_client()
        to = parse_jid(chat)
        quoted = self._load_quoted(chat, reply_to) if reply_to else None
        built = client.build_poll_vote_creation(name, options, VoteType.SINGLE, quoted=quoted)
        resp = client.send_message(to, built)
        row = self._sent_row(chat, "poll", name, resp)
        row["poll_name"] = name
        row["poll_options"] = json.dumps(options, ensure_ascii=False)
        return row

    def send_media(self, chat: str, kind: str, data: bytes, caption: str = "",
                   filename: str = "", mime: str = "", reply_to: str | None = None) -> dict:
        client = self._require_client()
        to = parse_jid(chat)
        quoted = self._load_quoted(chat, reply_to) if reply_to else None
        mime = mime or "application/octet-stream"
        if kind == "image":
            built = client.build_image_message(file=data, caption=caption or None, quoted=quoted)
        elif kind == "video":
            built = client.build_video_message(file=data, caption=caption or None, quoted=quoted)
        elif kind == "audio":
            built = client.build_audio_message(file=data, ptt=True, quoted=quoted)
        elif kind == "document":
            built = client.build_document_message(
                file=data, caption=caption or None, title=filename or None,
                filename=filename or None, mimetype=mime, quoted=quoted)
        elif kind == "sticker":
            built = client.build_sticker_message(file=data, quoted=quoted)
        else:
            raise ValueError(f"نوع وسائط غير مدعوم: {kind}")
        resp = client.send_message(to, built)
        row = self._sent_row(chat, kind, caption, resp)
        row["media_mime"] = mime
        row["media_name"] = filename
        row["media_size"] = len(data)
        return row

    def save_own_media(self, row: dict, data: bytes) -> str:
        """حفظ نسخة الوسائط المرسلة محلياً لعرضها في الفقاعة."""
        from .media_worker import _ext_for
        ext = _ext_for(row.get("media_mime", ""), row.get("media_name", ""))
        filename = f"{_safe_jid(row['chat_jid'])}_{row['id']}{ext}"
        target = os.path.join(MEDIA_DIR, filename)
        os.makedirs(MEDIA_DIR, exist_ok=True)
        with open(target, "wb") as fh:
            fh.write(data)
        return os.path.relpath(target, DOWNLOAD_DIR)

    def react(self, chat: str, msg_id: str, emoji: str) -> dict:
        client = self._require_client()
        row = db.get_message(chat, msg_id)
        if row is None:
            raise ValueError("الرسالة غير موجودة")
        me = self.me_info.get("jid", "أنا")
        if chat.endswith("@newsletter"):
            client.newsletter_send_reaction(parse_jid(chat), row["server_id"], emoji, msg_id)
        else:
            built = client.build_reaction(parse_jid(chat),
                                          parse_jid(row["sender"] or chat), msg_id, emoji)
            client.send_message(parse_jid(chat), built)
        reactions = json.loads(row["reactions"] or "{}")
        if emoji:
            reactions[emoji] = me
        else:
            for emo, by in list(reactions.items()):
                if by == me:
                    del reactions[emo]
        db.set_reactions(chat, msg_id, json.dumps(reactions, ensure_ascii=False))
        return {"chat": chat, "id": msg_id, "reactions": reactions}

    def _sent_row(self, chat: str, mtype: str, body: str, resp) -> dict:
        msg_id = getattr(resp, "ID", "") or self._gen_id()
        ts = int(getattr(resp, "Timestamp", 0) or time.time())
        return {
            "chat_jid": chat, "id": msg_id, "sender": chat, "sender_name": "أنا",
            "from_me": True, "type": mtype, "body": body, "timestamp": ts,
            "receipt": "pending", "media_state": "none",
        }

    @staticmethod
    def _gen_id() -> str:
        return ("3EB0" + uuid.uuid4().hex[:16].upper())[:22]

    # ------------------------------------------------------------ الصور الشخصية
    def invalidate_avatar(self, jid: str) -> None:
        try:
            path = os.path.join(AVATARS_DIR, f"{_safe_jid(jid)}.jpg")
            if os.path.exists(path):
                os.remove(path)
        except Exception:
            pass

    def get_avatar(self, jid: str, force: bool = False) -> dict:
        """جلب الصورة الشخصية بأعلى دقة (preview=False) وحفظها في downloads/avatars."""
        safe = _safe_jid(jid)
        target = os.path.join(AVATARS_DIR, f"{safe}.jpg")
        if not force and os.path.exists(target) and os.path.getsize(target) > 0:
            rel = os.path.relpath(target, DOWNLOAD_DIR)
            return {"url": f"/media/{rel}", "cached": True}
        client = self._require_client()
        try:
            info = client.get_profile_picture(parse_jid(jid), np.GetProfilePictureParams(Preview=False))
        except Exception:
            return {"url": None, "cached": False, "error": "لا توجد صورة شخصية أو تعذر جلبها"}
        url = getattr(info, "URL", "") or ""
        if not url:
            return {"url": None, "cached": False, "error": "لا توجد صورة شخصية لهذا الرقم"}
        resp = requests.get(url, timeout=AVATAR_FETCH_TIMEOUT)
        resp.raise_for_status()
        with open(target, "wb") as fh:
            fh.write(resp.content)
        rel = os.path.relpath(target, DOWNLOAD_DIR)
        return {"url": f"/media/{rel}", "cached": False}

    def _fetch_newsletter_avatar(self, nlid: str) -> None:
        try:
            result = self.get_avatar(nlid)
            if result.get("url"):
                db.set_chat_picture(nlid, result["url"])
                ws_manager.broadcast_threadsafe({"type": "chat_updated", "chat": nlid})
        except Exception:
            logger.debug("تعذر جلب صورة القناة %s", nlid)

    # ------------------------------------------------------------ المجموعات وجهات الاتصال
    def refresh_group_meta(self, chat: str, silent: bool = False) -> None:
        def worker():
            try:
                client = self._require_client()
                info = client.get_group_info(parse_jid(chat))
                name = getattr(info, "GroupName", "") or chat
                participants = list(getattr(info, "Participants", []))
                db.upsert_chat(chat, name=name, is_group=True, members=len(participants))
                try:
                    result = self.get_avatar(chat)
                    if result.get("url"):
                        db.set_chat_picture(chat, result["url"])
                except Exception:
                    pass
                if not silent:
                    ws_manager.broadcast_threadsafe({"type": "chat_updated", "chat": chat})
            except Exception as exc:
                logger.debug("تعذر تحديث بيانات المجموعة %s: %s", chat, exc)

        threading.Thread(target=worker, daemon=True, name=f"group-meta-{_safe_jid(chat)[:10]}").start()

    def group_info(self, chat: str) -> dict:
        client = self._require_client()
        info = client.get_group_info(parse_jid(chat))
        members = []
        for p in getattr(info, "Participants", []):
            members.append({
                "jid": jid_str(getattr(p, "JID")),
                "is_admin": bool(getattr(p, "IsAdmin", False)),
                "is_super_admin": bool(getattr(p, "IsSuperAdmin", False)),
            })
        return {
            "jid": chat,
            "name": getattr(info, "GroupName", "") or chat,
            "topic": getattr(info, "GroupTopic", "") or "",
            "participants": members,
            "size": len(members),
        }

    def joined_groups(self) -> list[dict]:
        client = self._require_client()
        out = []
        for g in client.get_joined_groups():
            j = jid_str(getattr(g, "JID"))
            name = getattr(g, "GroupName", "") or j
            size = len(list(getattr(g, "Participants", [])))
            out.append({"jid": j, "name": name, "size": size})
            db.upsert_chat(j, name=name, is_group=True, members=size)
        return out

    def join_group_link(self, link: str) -> dict:
        client = self._require_client()
        code = _extract_invite_code(link)
        if not code:
            raise ValueError("رابط دعوة غير صالح")
        jid = jid_str(client.join_group_with_link(code))
        db.upsert_chat(jid, is_group=True, last_time=int(time.time()))
        self.refresh_group_meta(jid)
        return {"jid": jid}

    # ------------------------------------------------------------ القنوات
    def newsletters(self) -> list[dict]:
        client = self._require_client()
        out = []
        for meta in client.get_subscribed_newletters():
            nlid = jid_str(getattr(meta, "ID"))
            thread = getattr(meta, "ThreadMeta", None)
            viewer = getattr(meta, "ViewerMeta", None)
            entry = {
                "jid": nlid,
                "name": getattr(thread, "Name", "") or nlid.split("@")[0],
                "description": getattr(thread, "Description", ""),
                "subscribers": int(getattr(thread, "SubscriberCount", 0) or 0),
                "role": str(getattr(getattr(viewer, "Role", ""), "name", "")),
                "picture": None,
            }
            try:
                avatar = self.get_avatar(nlid)
                entry["picture"] = avatar.get("url")
                if avatar.get("url"):
                    db.set_chat_picture(nlid, avatar["url"])
            except Exception:
                pass
            out.append(entry)
            db.upsert_chat(nlid, name=entry["name"], last_message=entry["description"],
                           is_newsletter=True, members=entry["subscribers"])
        return out

    def newsletter_info_by_invite(self, invite: str) -> dict:
        client = self._require_client()
        key = _extract_newsletter_key(invite)
        if not key:
            raise ValueError("أدخل رابط قناة صالحاً أو معرفها")
        meta = client.get_newsletter_info_with_invite(key)
        thread = getattr(meta, "ThreadMeta", None)
        return {
            "jid": jid_str(getattr(meta, "ID")),
            "name": getattr(thread, "Name", "") or "",
            "description": getattr(thread, "Description", ""),
            "subscribers": int(getattr(thread, "SubscriberCount", 0) or 0),
        }

    def follow_newsletter(self, nlid: str) -> None:
        client = self._require_client()
        client.follow_newsletter(parse_jid(nlid))
        db.upsert_chat(nlid, is_newsletter=True, last_time=int(time.time()))
        threading.Thread(target=self._fetch_newsletter_avatar, args=(nlid,),
                         daemon=True, name=f"nl-avatar-{_safe_jid(nlid)[:8]}").start()

    def unfollow_newsletter(self, nlid: str) -> None:
        client = self._require_client()
        client.unfollow_newsletter(parse_jid(nlid))
        db.x("DELETE FROM chats WHERE jid=?", (nlid,))

    def newsletter_posts(self, nlid: str, count: int = 50) -> list[dict]:
        client = self._require_client()
        try:
            client.newsletter_subscribe_live_updates(parse_jid(nlid))
        except Exception:
            logger.debug("تعذر تفعيل التحديث اللحظي للقناة %s", nlid)
        try:
            posts = client.get_newsletter_messages(parse_jid(nlid), count=count, before=0)
            for nmsg in posts:
                self._store_newsletter_message(nlid, nmsg, int(time.time()))
        except Exception as exc:
            logger.warning("تعذر جلب منشورات القناة %s: %s", nlid, exc)
        rows = db.get_messages(nlid, offset=0, limit=count)
        return [self.row_to_json(dict(r)) for r in reversed(rows)]

    def react_newsletter(self, chat: str, msg_id: str, emoji: str) -> dict:
        client = self._require_client()
        row = db.get_message(chat, msg_id)
        if row is None:
            raise ValueError("المنشور غير موجود")
        client.newsletter_send_reaction(parse_jid(chat), row["server_id"], emoji, msg_id)
        reactions = json.loads(row["reactions"] or "{}")
        if emoji:
            reactions[emoji] = self.me_info.get("jid", "أنا")
        db.set_reactions(chat, msg_id, json.dumps(reactions, ensure_ascii=False))
        return {"chat": chat, "id": msg_id, "reactions": reactions}

    # ------------------------------------------------------------ جهات الاتصال
    def contact_info(self, jid: str) -> dict:
        client = self._require_client()
        info = {"jid": jid, "about": "", "verified_name": "", "on_whatsapp": None}
        try:
            results = client.get_user_info(parse_jid(jid))
            if results:
                userinfo = getattr(results[0], "UserInfo")
                info["about"] = getattr(userinfo, "Status", "") or ""
                vname = getattr(userinfo, "VerifiedName", None)
                info["verified_name"] = getattr(vname, "Name", "") if vname is not None else ""
        except Exception as exc:
            logger.debug("تعذر جلب معلومات %s: %s", jid, exc)
        phone = jid.split("@")[0]
        try:
            resp = client.is_on_whatsapp(phone)
            if resp:
                info["on_whatsapp"] = bool(resp[0].IsIn)
        except Exception:
            pass
        return info

    def start_chat(self, phone: str) -> dict:
        client = self._require_client()
        phone = re.sub(r"[^\d]", "", phone or "")
        resp = client.is_on_whatsapp(phone)
        on_whatsapp = bool(resp and resp[0].IsIn)
        if not on_whatsapp:
            return {"on_whatsapp": False, "jid": None}
        jid = jid_str(resp[0].JID)
        db.upsert_chat(jid, name=phone, last_time=int(time.time()))
        return {"on_whatsapp": True, "jid": jid}

    # ------------------------------------------------------------ تسجيل الخروج
    def logout(self) -> None:
        logger.info("تسجيل خروج وإعادة تعيين الجلسة")
        client = self.client
        try:
            if client is not None:
                client.logout()
        except Exception:
            logger.debug("logout انتهى بخطأ غير حرج")
        try:
            if client is not None:
                client.stop()
        except Exception:
            pass
        self.paired = False
        self.me_info = {}
        self.qr_svg = None
        self.pairing_code = None
        self._set_state("logged_out")
        for path in (SESSION_NAME, SESSION_NAME + "-wal", SESSION_NAME + "-shm"):
            try:
                if os.path.exists(path):
                    os.remove(path)
            except Exception:
                logger.exception("تعذر حذف ملف الجلسة %s", path)
        ws_manager.broadcast_threadsafe({"type": "logged_out"})

    # ------------------------------------------------------------ تحويل الصفوف للـ JSON
    @staticmethod
    def row_to_json(row) -> dict:
        media = {
            "path": row.get("media_path", "") or "",
            "mime": row.get("media_mime", "") or "",
            "name": row.get("media_name", "") or "",
            "size": int(row.get("media_size", 0) or 0),
            "duration": int(row.get("media_duration", 0) or 0),
            "width": int(row.get("media_width", 0) or 0),
            "height": int(row.get("media_height", 0) or 0),
            "state": row.get("media_state", "none") or "none",
        }
        return {
            "id": row.get("id", ""),
            "chat": row.get("chat_jid", ""),
            "sender": row.get("sender", "") or "",
            "sender_name": row.get("sender_name", "") or "",
            "from_me": bool(row.get("from_me")),
            "type": row.get("type", "text"),
            "body": row.get("body", "") or "",
            "media": media,
            "timestamp": int(row.get("timestamp", 0) or 0),
            "quoted": {
                "id": row.get("quoted_id", "") or "",
                "body": row.get("quoted_body", "") or "",
                "type": row.get("quoted_type", "") or "",
                "from_me": bool(row.get("quoted_from_me")),
                "sender": row.get("quoted_sender", "") or "",
            } if row.get("quoted_id") else None,
            "reactions": json.loads(row.get("reactions") or "{}"),
            "poll": {
                "name": row.get("poll_name", "") or "",
                "options": json.loads(row.get("poll_options") or "[]"),
            } if row.get("poll_name") else None,
            "receipt": row.get("receipt", "pending") or "pending",
        }
