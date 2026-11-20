# -*- coding: utf-8 -*-
"""عامل تنزيل الوسائط الخلفي: يفك تشفير وينزّل كل الوسائط الواردة عبر download_any."""
import logging
import mimetypes
import os
import queue
import threading
import time

from . import database as db
from .config import MEDIA_DIR, STATUSES_DIR, DOWNLOAD_DIR, MEDIA_DOWNLOAD_TIMEOUT
from .state import ws_manager

logger = logging.getLogger("whatsapp.media")

DOWNLOAD_DIR_REL = DOWNLOAD_DIR

MIME_EXT = {
    "image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/webp": ".webp",
    "image/gif": ".gif", "image/heic": ".heic", "video/mp4": ".mp4", "video/3gpp": ".3gp",
    "video/webm": ".webm", "audio/ogg": ".ogg", "audio/ogg; codecs=opus": ".ogg",
    "audio/mpeg": ".mp3", "audio/mp4": ".m4a", "audio/amr": ".amr", "audio/aac": ".aac",
    "audio/webm": ".weba", "application/pdf": ".pdf", "application/zip": ".zip",
    "text/plain": ".txt", "application/vnd.ms-excel": ".xls",
}


def _ext_for(mime: str, filename: str) -> str:
    if filename and "." in filename:
        ext = os.path.splitext(filename)[1].lower()
        if 1 <= len(ext) <= 6:
            return ext
    mime = (mime or "").split(";")[0].strip().lower()
    if mime in MIME_EXT:
        return MIME_EXT[mime]
    guessed = mimetypes.guess_extension(mime) if mime else None
    return guessed or ".bin"


def _safe_name(jid: str, msg_id: str) -> str:
    keep = "".join(ch for ch in f"{jid}_{msg_id}" if ch.isalnum() or ch in "-_@")
    return keep[:150] or f"media_{int(time.time())}"


class MediaWorker(threading.Thread):
    """خيط واحد يعالج طابور تنزيل الوسائط بالترتيب دون تعطيل أحداث neonize."""

    def __init__(self, service) -> None:
        super().__init__(daemon=True, name="media-worker")
        self.service = service
        self.queue: queue.Queue = queue.Queue()
        self.pending: set[str] = set()

    def enqueue(self, chat: str, msg_id: str, blob: bytes, category: str,
                mime: str = "", filename: str = "", ptt: bool = False) -> None:
        key = f"{chat}|{msg_id}"
        if key in self.pending:
            return
        self.pending.add(key)
        self.queue.put({
            "chat": chat, "id": msg_id, "blob": blob, "category": category,
            "mime": mime, "filename": filename, "ptt": ptt,
        })

    def run(self) -> None:
        while True:
            job = self.queue.get()
            try:
                self._process(job)
            except Exception:
                logger.exception("فشل تنزيل الوسائط للرسالة %s", job.get("id"))
            finally:
                self.pending.discard(f"{job['chat']}|{job['id']}")

    def _process(self, job: dict) -> None:
        chat, msg_id = job["chat"], job["id"]
        client = self.service.client
        if client is None:
            self._mark_failed(chat, msg_id)
            return

        ext = _ext_for(job["mime"], job["filename"])
        subdir = STATUSES_DIR if job["category"] == "status" else MEDIA_DIR
        filename = f"{_safe_name(chat, msg_id)}{ext}"
        target = os.path.join(subdir, filename)

        # 1) حفظ مباشر عبر neonize إلى الملف الهدف
        ok = False
        try:
            client.download_any(job["blob"], target)
            if os.path.exists(target) and os.path.getsize(target) > 0:
                ok = True
        except Exception as exc:
            logger.warning("download_any حفظ مباشر فشل (%s): %s", msg_id, exc)

        # 2) محاولة احتياطية: تنزيل بالبايتات ثم كتابة الملف يدوياً
        if not ok:
            try:
                data = client.download_any(job["blob"])
                if data:
                    with open(target, "wb") as fh:
                        fh.write(data)
                    ok = True
            except Exception as exc:
                logger.warning("download_any بايتات فشل (%s): %s", msg_id, exc)

        if not ok:
            self._mark_failed(chat, msg_id)
            return

        rel = os.path.relpath(target, DOWNLOAD_DIR_REL)
        if job["category"] == "status":
            db.x(
                "UPDATE statuses SET media_path=?, media_mime=?, media_state='ready' WHERE id=?",
                (rel, job["mime"], msg_id),
            )
            ws_manager.broadcast_threadsafe({
                "type": "status_media", "id": msg_id,
                "media": {"path": rel, "mime": job["mime"]},
            })
        else:
            db.update_message(chat, msg_id, media_path=rel, media_mime=job["mime"],
                              media_state="ready")
            ws_manager.broadcast_threadsafe({
                "type": "message_media", "chat": chat, "id": msg_id,
                "media": {"path": rel, "mime": job["mime"]},
            })
        logger.info("تم تنزيل وسائط %s إلى %s", msg_id, rel)

    @staticmethod
    def _mark_failed(chat: str, msg_id: str) -> None:
        try:
            db.update_message(chat, msg_id, media_state="failed")
        except Exception:
            pass
