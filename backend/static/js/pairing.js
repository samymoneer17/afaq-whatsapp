/* شاشة الربط: كود الإقران برقم الهاتف أو رمز QR */

const Pairing = {
    render() {
        const screen = document.getElementById("pairingScreen");
        const app = document.getElementById("app");
        const connected = S.connection === "connected" && S.paired;

        if (connected) {
            screen.classList.add("hidden");
            app.classList.remove("hidden");
            App.onConnected();
            return;
        }

        screen.classList.remove("hidden");
        app.classList.add("hidden");

        const statusBox = document.getElementById("pairStatusBox");
        const statusText = document.getElementById("pairStatusText");
        const form = document.getElementById("pairingForm");
        const qrBox = document.getElementById("qrBox");
        const codeBox = document.getElementById("pairCodeBox");

        const isConnecting = S.connection === "connecting" || S.connection === "reconnecting" || S.connection === "init";
        statusBox.classList.toggle("hidden", !isConnecting);
        statusText.textContent =
            S.connection === "reconnecting" ? "جارٍ إعادة الاتصال بخوادم واتساب..." :
            isConnecting ? "جارٍ الاتصال بخوادم واتساب..." : "";

        const showForm = !isConnecting;
        form.classList.toggle("hidden", !showForm);

        if (S.pairingCode) {
            codeBox.classList.remove("hidden");
            this.renderCode();
        } else {
            codeBox.classList.add("hidden");
        }

        if (S.qrSvg && !isConnecting) {
            qrBox.classList.remove("hidden");
            this.renderQr();
        } else {
            qrBox.classList.add("hidden");
        }

        this.updateIndicator();
        if (this.errorVisible && !isConnecting) this.showError(this.lastError || "انقطع الاتصال، أعد المحاولة");
    },

    renderQr() {
        const box = document.getElementById("qrImage");
        if (!S.qrSvg) {
            document.getElementById("qrBox").classList.add("hidden");
            return;
        }
        document.getElementById("qrBox").classList.remove("hidden");
        box.innerHTML = "";
        const img = document.createElement("img");
        img.src = S.qrSvg;
        img.alt = "رمز QR";
        img.style.width = "260px";
        img.style.height = "260px";
        box.appendChild(img);
    },

    renderCode() {
        if (!S.pairingCode) return;
        document.getElementById("pairCodeBox").classList.remove("hidden");
        const code = S.pairingCode;
        document.getElementById("pairCodeText").textContent =
            code.length > 4 ? `${code.slice(0, 4)} - ${code.slice(4)}` : code;
    },

    updateIndicator() {
        const dot = document.getElementById("connDot");
        const text = document.getElementById("connText");
        const map = {
            connected: ["green", "متصل"],
            connecting: ["amber", "جارٍ الاتصال"],
            reconnecting: ["amber", "جارٍ إعادة الاتصال"],
            unpaired: ["", "غير مقترن"],
            logged_out: ["", "تم تسجيل الخروج — أعد الربط"],
            init: ["amber", "جارٍ التهيئة"],
        };
        const [cls, label] = map[S.connection] || ["", "غير مقترن"];
        dot.className = `dot ${cls}`;
        text.textContent = label;
    },

    async pairByPhone() {
        const input = document.getElementById("phoneInput");
        const phone = input.value.trim();
        if (!phone) { this.showError("أدخل رقم الهاتف مع كود الدولة"); return; }
        const btn = document.getElementById("pairBtn");
        btn.disabled = true;
        btn.textContent = "جارٍ الربط...";
        try {
            const body = new FormData();
            body.append("phone", phone);
            const res = await fetch("/api/session/pair", { method: "POST", body });
            if (!res.ok) {
                const err = await res.json().catch(() => ({}));
                this.showError(err.detail || "فشل الطلب");
            } else {
                this.hideError();
                UI.toast("تم إرسال الطلب — الكود سيظهر خلال لحظات");
            }
        } catch (e) {
            this.showError("تعذر الاتصال بالسيرفر");
        }
        btn.disabled = false;
        btn.textContent = "ربط";
    },

    async showQr() {
        try {
            const res = await fetch("/api/session/qr", { method: "POST" });
            const data = await res.json().catch(() => ({}));
            if (res.ok && data.qr) {
                S.qrSvg = data.qr;
                this.renderQr();
            } else if (res.ok) {
                UI.toast(data.note || "الرمز سيظهر تلقائياً خلال لحظات");
            } else {
                this.showError(data.detail || "تعذر إظهار رمز QR");
            }
        } catch (e) {
            this.showError("تعذر الاتصال بالسيرفر");
        }
    },

    copyCode() {
        if (!S.pairingCode) return;
        navigator.clipboard.writeText(S.pairingCode).then(() => UI.toast("تم نسخ الكود"));
    },

    lastError: null,
    errorVisible: false,

    showError(msg) {
        this.lastError = msg;
        this.errorVisible = true;
        const box = document.getElementById("pairErrorBox");
        document.getElementById("pairErrorText").textContent = msg;
        box.classList.remove("hidden");
    },

    hideError() {
        this.errorVisible = false;
        document.getElementById("pairErrorBox").classList.add("hidden");
    },
};
