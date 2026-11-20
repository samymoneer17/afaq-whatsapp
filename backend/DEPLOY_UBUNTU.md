# دليل النشر الكامل على سيرفر Ubuntu 22.04 / 24.04

هذا الدليل ينقل التطبيق إلى `/opt/whatsapp-web-app` ويشغّله كخدمة systemd دائمة.

## 1) تثبيت الاعتماديات

### Ubuntu 24.04 (يأتي بـ Python 3.12 مباشرة)
```bash
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3-pip ffmpeg git
```

### Ubuntu 22.04 (يأتي بـ Python 3.10 — نثبت 3.12 من deadsnakes)
```bash
sudo apt update
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:deadsnakes/ppa
sudo apt update
sudo apt install -y python3.12 python3.12-venv python3.12-dev ffmpeg git
```

## 2) نقل المشروع إلى السيرفر

من جهازك المحلي (بعد فك الضغط عن `whatsapp-web-app.zip`):
```bash
scp -r whatsapp-web-app root@SERVER_IP:/opt/
```

أو مباشرة بالأوامر على السيرفر، ثم فك الضغط:
```bash
mkdir -p /opt && cd /opt
# ارفع whatsapp-web-app.zip ثم:
unzip whatsapp-web-app.zip -d /opt/
cd /opt/whatsapp-web-app
```

طريقة بديلة باستخدام `deploy.sh` (يقوم بالخطوات 3 و 4 تلقائياً):
```bash
cd /opt/whatsapp-web-app
chmod +x deploy.sh
sudo ./deploy.sh
```

## 3) البيئة الافتراضية والاعتماديات

```bash
cd /opt/whatsapp-web-app
python3.12 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
```

## 4) التشغيل اليدوي (للتجربة)

```bash
cd /opt/whatsapp-web-app
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8000
```

افتح من المتصفح: `http://SERVER_IP:8000`

## 5) التشغيل الدائم عبر systemd

```bash
sudo cp whatsapp-web.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable whatsapp-web
sudo systemctl start whatsapp-web
sudo systemctl status whatsapp-web
```

السجلات:
```bash
journalctl -u whatsapp-web -f
```

## 6) فتح المنفذ في جدار الحماية

```bash
sudo ufw allow 8000/tcp
# أو غيّر المنفذ من ملف الخدمة قبل التفعيل
```

## 7) تحديث المنفذ أو الإعدادات

متغيرات البيئة المدعومة (تعدل في `/etc/systemd/system/whatsapp-web.service` ثم `daemon-reload`):
- `WA_PORT` (افتراضي 8000)
- `WA_HOST` (افتراضي 0.0.0.0)
- `WA_SESSION_NAME` (مسار ملف الجلسة)

## 8) HTTPS للإنتاج (اختياري — Caddy)

```bash
sudo apt install -y caddy
# /etc/caddy/Caddyfile:
# your-domain.com {
#     reverse_proxy localhost:8000
# }
sudo systemctl restart caddy
```

WebSocket يعمل عبر `wss` تلقائياً عندما يكون البروتوكول https.

## استكشاف الأخطاء

| المشكلة | الحل |
| --- | --- |
| `client is nil` عند الإقران | مدمج الحل تلقائياً (انتظار استقرار الاتصال + 2.5 ثانية قبل PairPhone) — إذا تكرر أعد المحاولة بعد ثوانٍ |
| خطأ ffmpeg عند الإقلاع | `sudo apt install -y ffmpeg` |
| لا يظهر رمز QR | انتظر ثوانٍ — يتجدد الرمز تلقائياً، أو أعد تشغيل الخدمة |
| الكود المولّد لا يقبل | تأكد من إدخال الكود خلال دقائق وإدخال رقم الهاتف بنفس الصيغة (مع كود الدولة) |
| الرسائل لا تظهر | افحص `journalctl -u whatsapp-web -f` وتأكد أن الحساب مقترن (المؤشر أخضر) |
| إعادة إقران من الصفر | `sudo systemctl stop whatsapp-web && rm /opt/whatsapp-web-app/whatsapp_session.sqlite3* && sudo systemctl start whatsapp-web` |
| المنفذ محجوز | غيّر `WA_PORT` أو أوقف الخدمة الأخرى |

## ملفات الجلسة والبيانات

- `whatsapp_session.sqlite3` — جلسة الاقتران (احتفظ بها بسرية، حذفها = إقران جديد).
- `app_data.db` — أرشيف الرسائل والمحادثات والحالات والإعدادات.
- `downloads/media|statuses|avatars` — الوسائط المنزّلة تلقائياً.
