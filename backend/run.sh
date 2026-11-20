#!/usr/bin/env bash
# تشغيل سريع للتطوير أو التجربة
cd "$(dirname "$0")"

if [ ! -d venv ]; then
    echo "==> إنشاء البيئة الافتراضية"
    python3.12 -m venv venv 2>/dev/null || python3 -m venv venv
fi
source venv/bin/activate
pip install --quiet -r requirements.txt

echo "==> تشغيل التطبيق على http://0.0.0.0:8000"
exec uvicorn main:app --host "${WA_HOST:-0.0.0.0}" --port "${WA_PORT:-8000}"
