#!/usr/bin/env bash
# نشر كامل على Ubuntu: اعتماديات + بيئة افتراضية + خدمة systemd — مسار /var/www/html/whatsapp-web-app
set -e

APP_DIR="/var/www/html/whatsapp-web-app"
SERVICE_NAME="afaq-whatsapp"

echo "==> تثبيت اعتماديات النظام"
apt update
apt install -y python3 python3-venv python3-pip ffmpeg

echo "==> إنشاء البيئة الافتراضية وتثبيت الحزم"
cd "$APP_DIR"
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install -r requirements.txt

echo "==> تثبيت خدمة systemd"
cp -f afaq-whatsapp.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo "==> فتح المنفذ 8000 في جدار الحماية"
iptables -I INPUT -p tcp --dport 8000 -j ACCEPT 2>/dev/null || true
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    ufw allow 8000/tcp || true
fi

sleep 3
systemctl status "$SERVICE_NAME" --no-pager | head -12 || true
echo ""
echo "==> تم النشر! الخادم يعمل على: http://$(hostname -I | awk '{print $1}'):8000"
echo "==> لتشغيل واجهة الويب الافتراضية: نفس العنوان من أي متصفح"
