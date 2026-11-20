# دليل بناء APK خطوة بخطوة

يوجد طريقتان للحصول على ملف APK جاهز للتثبيت على هاتفك.

---

## الطريقة الأولى: GitHub Actions (الأسهل — بدون تثبيت أي شيء على جهازك)

1. أنشئ حساباً على [github.com](https://github.com) إن لم يكن لديك.

2. أنشئ مستودعاً جديداً (New repository) وسمّه مثلاً `afaq-whatsapp`.

3. ارفع ملفات هذا المشروع للمستودع:
   ```bash
   # على جهازك بعد فك ضغط الملف
   cd afaq_whatsapp
   git init
   git add .
   git commit -m "آفاق واتساب 2.0"
   git branch -M main
   git remote add origin https://github.com/اسمك/afaq-whatsapp.git
   git push -u origin main
   ```
   أو ببساطة: من صفحة المستودع على المتصفح اضغط **Add file ← Upload files** واسحب محتويات المجلد كلها.

4. انتظر دقيقة — سيبدأ بناء APK تلقائياً بمجرد الرفع (راجع تبويب **Actions** في المستودع).

5. عند انتهاء البناء (نقطة خضراء ✓):
   - افتح البناء ← أسفل الصفحة قسم **Artifacts**
   - نزّل `afaq-whatsapp-apk` — سيحوي عدة ملفات APK:
     - `app-arm64-v8a-release.apk` ← **هذا المخصص لأغلب الهواتف الحديثة**
     - `app-armeabi-v7a-release.apk` ← للهواتف القديمة
     - `app-x86_64-release.apk` ← للمحاكيات

6. انقل الملف إلى هاتفك وثبّته (اسمح بـ "تثبيت من مصادر غير معروفة").

7. (اختياري) لإنشاء إصدار رسمي بصفحة تحميل دائمة: أضف وسم
   ```bash
   git tag v2.0.0
   git push origin v2.0.0
   ```
   سيبني APK وينشره تلقائياً في صفحة Releases.

---

## الطريقة الثانية: البناء على جهازك (يتطلب تثبيت Flutter)

### المتطلبات
- Windows / macOS / Linux
- 10 جيجا مساحة فارغة
- [Flutter SDK 3.35+](https://docs.flutter.dev/get-started/install) و [Android Studio](https://developer.android.com/studio) (منه SDK فقط)

### الخطوات

```bash
# 1) تحقق من التثبيت
flutter doctor

# 2) ادخل مجلد المشروع وولّد هيكل Android المطابق لإصدار Flutter لديك
cd afaq_whatsapp
flutter create --org com.afaq --project-name afaq_whatsapp --platforms android .

# 3) طبّق تعديلاتنا (الصلاحيات + MainActivity)
#    على Windows استخدم xcopy بدل cp
cp -r android_overlay/. android/

# 4) ثبت الاعتماديات وابنِ
flutter pub get
flutter build apk --release

# الملف الناتج:
# build/app/outputs/flutter-apk/app-release.apk
```

### ملاحظات
- أول بناء يستغرق 5–15 دقيقة (تنزيل Gradle والاعتماديات).
- إن ظهر خطأ SDK: افتح Android Studio ← SDK Manager ← ثبّت Android SDK 35 + Platform Tools.
- لبناء APK واحد لكل المعالجات (أكبر حجماً لكن يعمل على الكل):
  ```bash
  flutter build apk --release
  ```
- لتشغيله مباشرة على هاتف موصول بالكمبيوتر:
  ```bash
  flutter run --release
  ```

---

## بعد التثبيت

1. افتح التطبيق — ستظهر شاشة الربط.
2. اكتب عنوان الخادم (مثال: `http://SERVER_IP:8000`) واضغط ✓ للفحص.
3. أدخل رقمك مع كود الدولة واضغط **ربط برقم الهاتف**.
4. على هاتفك الاصلي: واتساب ← الإعدادات ← الأجهزة المرتبطة ← ربط جهاز ← **ربط برقم الهاتف بدلاً** ← أدخل الكود.
5. انتظر مزامنة المحادثات — سيصبح جهازك رابع جهاز مرتبط بحسابك.
