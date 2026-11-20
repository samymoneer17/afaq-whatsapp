# -*- coding: utf-8 -*-
"""نقاط النهاية REST للتطبيق."""
import asyncio
import json
import os
import re
import subprocess
import tempfile

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.templating import Jinja2Templates

from .. import database as db
from ..config import MEDIA_DIR, STATUSES_DIR, TEMPLATES_DIR
from ..state import state, ws_manager

templates = Jinja2Templates(directory=TEMPLATES_DIR)
router = APIRouter(prefix="/api")

ALLOWED_SEND_TYPES = ("text", "image", "video", "audio", "document", "sticker", "poll")


def _service():
    return state.service


def _running_service():
    service = state.service
    if service is None or service.client is None:
        raise HTTPException(status_code=503, detail="عميل واتساب غير متاح الآن")
    return service


# ------------------------------------------------------------ الجلسة
@router.get("/session/status")
async def session_status():
    service = _service()
    return {
        "state": service.conn_state,
        "paired": service.paired,
        "qr": service.qr_svg,
        "pairing_code": service.pairing_code,
        "pair_error": service.pair_error,
        "me": service.me_info,
        "privacy_read": state.privacy_read,
    }


@router.post("/session/pair")
async def session_pair(phone: str = Form(...)):
    service = _service()
    result = await asyncio.to_thread(service.request_pair, phone)
    if not result.get("ok"):
        raise HTTPException(status_code=400, detail=result.get("error", "فشل الطلب"))
    return {"ok": True, "note": "سيظهر كود الإقران في الواجهة بعد لحظات"}


@router.post("/session/qr")
async def session_qr():
    service = _service()
    if service.paired:
        raise HTTPException(status_code=400, detail="الحساب مقترن مسبقاً")
    return {
        "ok": True,
        "qr": service.qr_svg,
        "note": "إذا لم يظهر الرمز بعد سيصل تلقائياً خلال لحظات",
    }


@router.post("/session/logout")
async def session_logout():
    service = _service()
    await asyncio.to_thread(service.logout)
    return {"ok": True}


# ------------------------------------------------------------ المحادثات
@router.get("/chats")
async def list_chats():
    rows = db.get_chats()
    return {
        "chats": [
            {
                "jid": r["jid"], "name": r["name"], "last_message": r["last_message"],
                "last_time": r["last_time"], "unread": r["unread"],
                "is_group": bool(r["is_group"]), "is_newsletter": bool(r["is_newsletter"]),
                "picture": r["picture"], "members": r["members"],
            }
            for r in rows if not r["is_newsletter"]
        ]
    }


@router.get("/chats/search")
async def search_chats(term: str = ""):
    if not term.strip():
        return {"chats": []}
    rows = db.search_chats(term.strip())
    return {"chats": [
        {"jid": r["jid"], "name": r["name"], "last_message": r["last_message"],
         "last_time": r["last_time"], "unread": r["unread"],
         "is_group": bool(r["is_group"]), "picture": r["picture"]}
        for r in rows
    ]}


@router.get("/chats/{jid}/messages")
async def chat_messages(jid: str, offset: int = 0, limit: int = 50):
    limit = max(1, min(limit, 200))
    rows = db.get_messages(jid, offset=offset, limit=limit)
    service = _service()
    return {
        "messages": [service.row_to_json(dict(r)) for r in reversed(rows)],
        "has_more": len(rows) == limit,
    }


@router.post("/chats/start")
async def start_chat(phone: str = Form(...)):
    service = _running_service()
    result = await asyncio.to_thread(service.start_chat, phone)
    if not result.get("on_whatsapp"):
        return {"on_whatsapp": False,
                "error": "الرقم غير مسجل في واتساب (is_on_whatsapp = False)"}
    return result


@router.post("/chats/{jid}/read")
async def mark_read(jid: str, request: Request):
    """تعليم الرسائل مقروءة: يعمل فوراً ويعالج mark_read في الخلفية."""
    service = _service()
    state.open_chat = jid
    db.reset_unread(jid)
    ids: list[str] = []
    try:
        payload = await request.json()
        if isinstance(payload, list):
            ids = [str(i) for i in payload]
        elif isinstance(payload, dict):
            ids = [str(i) for i in (payload.get("ids") or [])]
    except Exception:
        ids = []
    if ids and not state.privacy_read and service is not None:
        import threading
        threading.Thread(
            target=service._mark_read_safe, args=(jid, ids),
            daemon=True, name=f"mark-read-{jid[:8]}",
        ).start()
    return {"ok": True, "privacy_read": state.privacy_read}


@router.post("/chats/{jid}/presence")
async def send_presence(jid: str, state_name: str = Form(...), media: str = Form("text")):
    service = _running_service()
    try:
        await asyncio.to_thread(
            service.send_chat_presence, jid, state_name == "composing", media == "audio")
    except Exception:
        pass
    return {"ok": True}


@router.post("/chats/{jid}/send")
async def send_message(
    jid: str,
    type: str = Form("text"),
    body: str = Form(""),
    reply_to: str = Form(""),
    options: str = Form("[]"),
    file: UploadFile | None = File(None),
):
    if type not in ALLOWED_SEND_TYPES:
        raise HTTPException(status_code=400, detail="نوع رسالة غير مدعوم")
    service = _running_service()

    def do_send():
        if type == "text":
            return service.send_text(jid, body, reply_to or None)
        if type == "poll":
            opts = [o.strip() for o in json.loads(options) if o.strip()]
            if len(opts) < 2:
                raise ValueError("الاستطلاع يحتاج خيارين على الأقل")
            return service.send_poll(jid, body, opts, reply_to or None)
        # رسائل الوسائط
        if file is None:
            raise ValueError("لم يتم إرفاق ملف")
        data = file.file.read()
        if not data:
            raise ValueError("الملف فارغ")
        filename = os.path.basename(file.filename or "ملف")
        mime = file.content_type or "application/octet-stream"
        # تحويل تسجيل الصوت من متصفح webm إلى ogg/opus ليظهر كرسالة صوتية في واتساب
        if type == "audio" and mime.startswith("audio/webm"):
            data, mime = _convert_to_ogg(data)
            if not filename.endswith(".ogg"):
                filename = os.path.splitext(filename)[0] + ".ogg"
        # تحويل الملصقات إلى webp بحجم 512
        if type == "sticker" and "webp" not in mime:
            data, mime = _convert_to_webp(data)
            filename = os.path.splitext(filename)[0] + ".webp"
        row = service.send_media(jid, type, data,
                                 caption=body, filename=filename, mime=mime,
                                 reply_to=reply_to or None)
        local = service.save_own_media(row, data)
        row["media_path"] = local
        row["media_state"] = "ready"
        return row

    try:
        row = await asyncio.to_thread(do_send)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"فشل الإرسال: {exc}")

    db.insert_message(row)
    db.upsert_chat(jid, last_message=(row["body"] or "وسائط")[:120],
                   last_time=row["timestamp"])
    payload = {"type": "message", "chat": jid, "message": service.row_to_json(row)}
    await ws_manager.broadcast_json(payload)
    return {"ok": True, "message": service.row_to_json(row)}


@router.post("/messages/react")
async def react_message(chat: str = Form(...), id: str = Form(...), emoji: str = Form(...)):
    service = _running_service()
    try:
        result = await asyncio.to_thread(service.react, chat, id, emoji)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"فشل التفاعل: {exc}")
    await ws_manager.broadcast_json({"type": "reaction", **result})
    return {"ok": True, "reactions": result["reactions"]}


# ------------------------------------------------------------ الصور الشخصية والمعلومات
@router.get("/avatar/{jid}")
async def get_avatar(jid: str, force: bool = False):
    service = _running_service()
    try:
        return await asyncio.to_thread(service.get_avatar, jid, force)
    except Exception as exc:
        return {"url": None, "cached": False, "error": f"تعذر جلب الصورة: {exc}"}


@router.get("/contact/{jid}/info")
async def contact_info(jid: str):
    service = _running_service()
    try:
        return await asyncio.to_thread(service.contact_info, jid)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"تعذر جلب المعلومات: {exc}")


# ------------------------------------------------------------ الحالات
@router.get("/statuses")
async def list_statuses():
    rows = db.get_statuses()
    return {"statuses": [
        {
            "id": r["id"], "sender": r["sender"], "sender_name": r["sender_name"],
            "type": r["type"], "body": r["body"], "media_path": r["media_path"],
            "media_mime": r["media_mime"], "media_state": r["media_state"],
            "timestamp": r["timestamp"],
        }
        for r in rows
    ]}


# ------------------------------------------------------------ القنوات
@router.get("/newsletters")
async def list_newsletters():
    service = _running_service()
    try:
        newsletters = await asyncio.to_thread(service.newsletters)
        return {"newsletters": newsletters}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"تعذر جلب القنوات: {exc}")


@router.post("/newsletters/preview")
async def preview_newsletter(invite: str = Form(...)):
    service = _running_service()
    try:
        info = await asyncio.to_thread(service.newsletter_info_by_invite, invite)
        return info
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"تعذر جلب معلومات القناة: {exc}")


@router.post("/newsletters/join")
async def join_newsletter(invite: str = Form(...)):
    service = _running_service()
    try:
        info = await asyncio.to_thread(service.newsletter_info_by_invite, invite)
        await asyncio.to_thread(service.follow_newsletter, info["jid"])
        await ws_manager.broadcast_json({"type": "channels_updated"})
        return {"ok": True, **info}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"فشل الانضمام للقناة: {exc}")


@router.post("/newsletters/{jid}/leave")
async def leave_newsletter(jid: str):
    service = _running_service()
    try:
        await asyncio.to_thread(service.unfollow_newsletter, jid)
        await ws_manager.broadcast_json({"type": "channels_updated"})
        return {"ok": True}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"فشل مغادرة القناة: {exc}")


@router.get("/newsletters/{jid}/posts")
async def newsletter_posts(jid: str, count: int = 50):
    service = _running_service()
    try:
        posts = await asyncio.to_thread(service.newsletter_posts, jid, count)
        return {"posts": posts}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"تعذر جلب المنشورات: {exc}")


# ------------------------------------------------------------ المجموعات
@router.get("/groups")
async def list_groups():
    service = _running_service()
    try:
        groups = await asyncio.to_thread(service.joined_groups)
        return {"groups": groups}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"تعذر جلب المجموعات: {exc}")


@router.get("/groups/{jid}/info")
async def group_info(jid: str):
    service = _running_service()
    try:
        return await asyncio.to_thread(service.group_info, jid)
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"تعذر جلب معلومات المجموعة: {exc}")


@router.post("/groups/join")
async def join_group(link: str = Form(...)):
    service = _running_service()
    try:
        result = await asyncio.to_thread(service.join_group_link, link)
        await ws_manager.broadcast_json({"type": "chat_updated", "chat": result["jid"]})
        return {"ok": True, **result}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"فشل الانضمام للمجموعة: {exc}")


# ------------------------------------------------------------ الإعدادات
@router.get("/settings")
async def get_settings():
    saved = db.kv_get("privacy_read", "0") == "1"
    state.privacy_read = saved
    theme = db.kv_get("theme", "dark")
    return {"privacy_read": saved, "theme": theme}


@router.post("/settings")
async def set_settings(privacy_read: bool | None = Form(None), theme: str | None = Form(None)):
    if privacy_read is not None:
        state.privacy_read = privacy_read
        db.kv_set("privacy_read", "1" if privacy_read else "0")
        await ws_manager.broadcast_json({"type": "settings", "privacy_read": privacy_read})
    if theme in ("dark", "light"):
        db.kv_set("theme", theme)
    return {"ok": True}


# ------------------------------------------------------------ أدوات التحويل
def _convert_to_ogg(data: bytes) -> tuple[bytes, str]:
    """تحويل تسجيل متصفح (webm/opus) إلى ogg/opus."""
    try:
        with tempfile.TemporaryDirectory() as tmp:
            src = os.path.join(tmp, "in.webm")
            dst = os.path.join(tmp, "out.ogg")
            with open(src, "wb") as fh:
                fh.write(data)
            proc = subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error", "-i", src,
                 "-c:a", "libopus", "-b:a", "24k", "-application", "voip", dst],
                capture_output=True, timeout=30,
            )
            if proc.returncode == 0 and os.path.exists(dst):
                with open(dst, "rb") as fh:
                    return fh.read(), "audio/ogg"
    except Exception:
        pass
    return data, "audio/webm"


def _convert_to_webp(data: bytes) -> tuple[bytes, str]:
    """تحويل الصور إلى ملصق webp بحجم 512x512."""
    try:
        from PIL import Image
        import io
        img = Image.open(io.BytesIO(data)).convert("RGBA")
        img.thumbnail((512, 512), Image.LANCZOS)
        out = io.BytesIO()
        img.save(out, "WEBP", quality=90)
        return out.getvalue(), "image/webp"
    except Exception:
        return data, "image/webp"
