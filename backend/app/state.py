# -*- coding: utf-8 -*-
"""الحالة المشتركة للتطبيق ومدير اتصالات WebSocket."""
import asyncio
import logging

logger = logging.getLogger("whatsapp.app")


class AppState:
    """حالة التطبيق المشتركة بين الأحداث والواجهة."""

    def __init__(self) -> None:
        self.loop: asyncio.AbstractEventLoop | None = None
        self.service = None          # مرجع WhatsAppService
        self.open_chat: str = ""     # المحادثة المفتوحة حالياً في الواجهة
        self.privacy_read: bool = False  # وضع التخفي (إيقاف علامات القراءة)


class WSManager:
    """إدارة عملاء WebSocket والبث اللحظي لجميع الواجهات المفتوحة."""

    def __init__(self) -> None:
        self.clients: set = set()
        self.loop: asyncio.AbstractEventLoop | None = None

    def set_loop(self, loop: asyncio.AbstractEventLoop | None) -> None:
        self.loop = loop

    async def connect(self, websocket) -> None:
        await websocket.accept()
        self.clients.add(websocket)

    def disconnect(self, websocket) -> None:
        self.clients.discard(websocket)

    async def broadcast_json(self, data: dict) -> None:
        dead = []
        for ws in list(self.clients):
            try:
                await ws.send_json(data)
            except Exception:
                dead.append(ws)
        for ws in dead:
            self.disconnect(ws)

    def broadcast_threadsafe(self, data: dict) -> None:
        """بث من خيوط neonize غير المتزامنة إلى حلقة أحداث uvicorn."""
        loop = self.loop or state.loop
        if loop is None or loop.is_closed():
            return
        try:
            asyncio.run_coroutine_threadsafe(self.broadcast_json(data), loop)
        except RuntimeError as exc:
            logger.debug("تعذر البث عبر WebSocket: %s", exc)


state = AppState()
ws_manager = WSManager()
ws_manager.set_loop(None)
