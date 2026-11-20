# -*- coding: utf-8 -*-
"""إعدادات تطبيق واتساب ويب."""
import os

# مسارات المشروع
APP_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(APP_DIR)

TEMPLATES_DIR = os.path.join(PROJECT_ROOT, "templates")
STATIC_DIR = os.path.join(PROJECT_ROOT, "static")

# مجلدات التخزين
DOWNLOAD_DIR = os.path.join(PROJECT_ROOT, "downloads")
MEDIA_DIR = os.path.join(DOWNLOAD_DIR, "media")
STATUSES_DIR = os.path.join(DOWNLOAD_DIR, "statuses")
AVATARS_DIR = os.path.join(DOWNLOAD_DIR, "avatars")

# قواعد البيانات
DATA_DB = os.path.join(PROJECT_ROOT, "app_data.db")
SESSION_NAME = os.environ.get("WA_SESSION_NAME", os.path.join(PROJECT_ROOT, "whatsapp_session.sqlite3"))

# إعدادات السيرفر
HOST = os.environ.get("WA_HOST", "0.0.0.0")
PORT = int(os.environ.get("WA_PORT", "8000"))

# حدود التحميل والمعالجة
HISTORY_MSGS_PER_CHAT = 25          # عدد الرسائل المستعادة من مزامنة التاريخ لكل محادثة
HISTORY_MEDIA_MAX_AGE_DAYS = 14     # تنزيل وسائط التاريخ الأحدث من هذا العدد من الأيام فقط
NEWSLETTER_POSTS_LIMIT = 50         # عدد منشورات القناة المستعاد عند الطلب
MEDIA_DOWNLOAD_TIMEOUT = 90         # مهلة تنزيل كل وسائط (ثانية)
AVATAR_FETCH_TIMEOUT = 20           # مهلة جلب الصورة الشخصية (ثانية)


def ensure_dirs() -> None:
    """إنشاء مجلدات التخزين تلقائياً عند الإقلاع."""
    for path in (DOWNLOAD_DIR, MEDIA_DIR, STATUSES_DIR, AVATARS_DIR, PROJECT_ROOT):
        os.makedirs(path, exist_ok=True)
