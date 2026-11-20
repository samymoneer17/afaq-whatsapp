# -*- coding: utf-8 -*-
"""نقطة نهاية WebSocket للتحديث اللحظي."""
import asyncio
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from ..state import state, ws_manager

logger = logging.getLogger("whatsapp.ws")
router = APIRouter()


@router.websocket("/ws")
async def ws_endpoint(websocket: WebSocket):
    await ws_manager.connect(websocket)
    service = state.service
    try:
        # لقطة أولية لحالة الجلسة
        if service is not None:
            await websocket.send_json({
                "type": "connection",
                "state": service.conn_state,
                "paired": service.paired,
                "qr": service.qr_svg,
                "pairing_code": service.pairing_code,
                "pair_error": service.pair_error,
                "me": service.me_info,
            })
        while True:
            try:
                data = await websocket.receive_json()
            except Exception:
                break
            msg_type = data.get("type", "")
            if msg_type == "ping":
                await websocket.send_json({"type": "pong"})
            elif msg_type == "presence":
                chat = data.get("chat", "")
                composing = data.get("state", "paused") == "composing"
                audio = data.get("media", "text") == "audio"
                service = state.service
                if chat and service is not None:
                    try:
                        await asyncio.to_thread(service.send_chat_presence, chat, composing, audio)
                    except Exception:
                        pass
            elif msg_type == "open_chat":
                state.open_chat = data.get("chat", "")
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("انقطع اتصال WebSocket")
    finally:
        ws_manager.disconnect(websocket)
