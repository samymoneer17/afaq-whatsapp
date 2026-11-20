# -*- coding: utf-8 -*-
"""نقطة تشغيل تطبيق واتساب ويب — FastAPI + neonize."""
import asyncio
import logging
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, Request
from fastapi.staticfiles import StaticFiles

from app.config import DOWNLOAD_DIR, HOST, PORT, STATIC_DIR, ensure_dirs
from app.database import init_db
from app.routes.api import router as api_router, templates
from app.routes.ws import router as ws_router
from app.state import state, ws_manager
from app.whatsapp_client import WhatsAppService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
)
logging.getLogger("uvicorn.access").setLevel(logging.WARNING)


@asynccontextmanager
async def lifespan(app: FastAPI):
    loop = asyncio.get_running_loop()
    state.loop = loop
    ws_manager.set_loop(loop)
    ensure_dirs()
    init_db()
    await state_loop_setup()
    service = WhatsAppService()
    state.service = service
    service.start()
    try:
        yield
    finally:
        service.shutdown()


async def state_loop_setup():
    """تحميل الإعدادات المحفوظة."""
    from app import database as db
    state.privacy_read = db.kv_get("privacy_read", "0") == "1"


app = FastAPI(title="WhatsApp Web App", lifespan=lifespan)
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
app.mount("/media", StaticFiles(directory=str(DOWNLOAD_DIR)), name="media")
app.include_router(api_router)
app.include_router(ws_router)


@app.get("/")
async def index(request: Request):
    return templates.TemplateResponse(request, "index.html")


if __name__ == "__main__":
    # ملاحظة مهمة: يجب تشغيل worker واحد فقط لأن عميل واتساب حالة مشتركة
    uvicorn.run("main:app", host=HOST, port=PORT, workers=1, log_level="info")
