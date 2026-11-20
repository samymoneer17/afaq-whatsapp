#!/usr/bin/env bash
# نشر كامل على Ubuntu 22.04/24.04: اعتماديات + بيئة افتراضية + خدمة systemd
set -e

APP_DIR="/opt/whatsapp-web-app"
SERVICE_NAME="whatsapp-web"

echo "==> تثبيت اعتماديات النظام"
if grep -q "22.04" /etc/os-release 2>/dev/null; then
    apt update
    apt install -y software-properties-common
    add-apt-repository -y ppa:deadsnakes/ppa
    apt update
    apt install -y python3.12 python3.12-venv python3.12-dev ffmpeg
else
    apt update
    apt install -y python3 python3-venv python3-pip ffmpeg
fi

echo "==> إنشاء البيئة الافتراضية وتثبيت الحزم"
cd "$APP_DIR"
python3.12 -m venv venv || python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

echo "==> تثبيت خدمة systemd"
cp -f whatsapp-web.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo "==> فتح المنفذ 8000 في جدار الحماية (إن كان ufw مفعلاً)"
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow 8000/tcp || true
fi

sleep 2
systemctl status "$SERVICE_NAME" --no-pager || true
echo "==> تم! افتح http://$(hostname -I | awk '{print $1}'):8000"
