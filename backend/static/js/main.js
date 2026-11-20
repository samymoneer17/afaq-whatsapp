/* الإقلاع والتنقل والإعدادات */

const App = {
    async boot() {
        this.applyTheme(localStorage.getItem("wa_theme") || "dark");
        this.bindNav();
        this.bindComposer();
        this.bindSettings();
        WS.connect();

        try {
            const res = await fetch("/api/settings");
            const data = await res.json();
            S.privacyRead = data.privacy_read;
            if (data.theme) localStorage.setItem("wa_theme", data.theme);
            this.applyTheme(localStorage.getItem("wa_theme") || "dark");
            this.applyPrivacyToggle();
        } catch (e) { /* تجاهل */ }

        try {
            const res = await fetch("/api/session/status");
            const data = await res.json();
            S.connection = data.state;
            S.paired = data.paired;
            S.qrSvg = data.qr;
            S.pairingCode = data.pairing_code;
            S.me = data.me || {};
            Pairing.render();
        } catch (e) { /* تجاهل */ }
    },

    bindNav() {
        document.querySelectorAll(".rail-btn").forEach((btn) => {
            btn.addEventListener("click", () => this.switchTab(btn.dataset.tab));
        });
        document.getElementById("chatSearch").addEventListener("input", (e) => {
            Chats.renderList(e.target.value.trim());
        });
        document.getElementById("channelSearch").addEventListener("input", (e) => {
            Channels.render(e.target.value.trim());
        });
    },

    switchTab(tab) {
        S.tab = tab;
        document.querySelectorAll(".rail-btn").forEach((b) =>
            b.classList.toggle("active", b.dataset.tab === tab));
        ["chats", "statuses", "channels", "groups", "settings"].forEach((t) => {
            document.getElementById(`panel-${t}`).classList.toggle("hidden", t !== tab);
        });
        if (tab === "chats") Chats.refresh();
        if (tab === "statuses") Statuses.load();
        if (tab === "channels") Channels.load();
        if (tab === "groups") Groups.load();
        if (tab === "settings") this.fillSettings();
    },

    bindComposer() {
        const input = document.getElementById("msgInput");
        const sendBtn = document.getElementById("sendBtn");
        const recordBtn = document.getElementById("recordBtn");

        input.addEventListener("input", () => {
            input.style.height = "auto";
            input.style.height = Math.min(input.scrollHeight, 130) + "px";
            const hasText = input.value.trim().length > 0;
            if (!Chats.recording) {
                sendBtn.classList.toggle("hidden", false);
                recordBtn.classList.toggle("hidden", hasText);
            }
            // مؤشر الكتابة
            clearTimeout(this._typingTimer);
            Chats.sendTyping("composing", "text");
            this._typingTimer = setTimeout(() => Chats.sendTypingPaused(), 2500);
        });

        input.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                Chats.sendText();
            }
        });

        sendBtn.addEventListener("click", () => {
            if (Chats.recording) {
                recordBtn.click();
            } else {
                Chats.sendText();
            }
        });

        recordBtn.addEventListener("click", () => Chats.toggleRecording());
    },

    bindSettings() {
        document.getElementById("themeToggle").addEventListener("change", (e) => {
            const theme = e.target.checked ? "dark" : "light";
            this.applyTheme(theme);
            localStorage.setItem("wa_theme", theme);
            fetch("/api/settings", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ theme }),
            }).catch(() => {});
        });

        document.getElementById("privacyToggle").addEventListener("change", (e) => {
            const on = e.target.checked;
            fetch("/api/settings", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ privacy_read: on }),
            }).then(() => {
                S.privacyRead = on;
                UI.toast(on ? "تم إيقاف علامات القراءة (وضع التخفي)" : "تم تشغيل علامات القراءة");
            }).catch(() => {});
        });
    },

    applyTheme(theme) {
        document.body.classList.toggle("wa-dark", theme === "dark");
        document.body.classList.toggle("wa-light", theme === "light");
        const toggle = document.getElementById("themeToggle");
        if (toggle) toggle.checked = theme === "dark";
    },

    applyPrivacyToggle() {
        const toggle = document.getElementById("privacyToggle");
        if (toggle) toggle.checked = S.privacyRead;
    },

    fillSettings() {
        document.getElementById("meName").textContent = S.me.pushname || "حسابي";
        document.getElementById("meJid").textContent = S.me.jid || "غير مقترن";
        const meAvatar = document.getElementById("meAvatar");
        if (S.me.jid) {
            meAvatar.textContent = (S.me.pushname || "W").charAt(0);
            UI.applyAvatar(meAvatar, S.me.jid);
        }
        const map = {
            connected: "متصل بخوادم واتساب",
            connecting: "جارٍ الاتصال",
            reconnecting: "جارٍ إعادة الاتصال",
            unpaired: "غير مقترن",
            logged_out: "تم تسجيل الخروج",
            init: "جارٍ التهيئة",
        };
        document.getElementById("settingsConn").textContent = map[S.connection] || "-";
        const dot = document.getElementById("settingsDot");
        dot.className = "dot big " + (
            S.connection === "connected" ? "green" :
            ["connecting", "reconnecting", "init"].includes(S.connection) ? "amber" : "");
        this.applyPrivacyToggle();
    },

    onConnected() {
        Chats.refresh();
        Statuses.load();
        Channels.load();
        Groups.load();
        UI.loadAvatar(S.me.jid);
    },

    async syncAfterReconnect() {
        if (S.connection === "connected" && S.paired) {
            Chats.refresh();
            if (S.tab === "statuses") Statuses.load();
            if (S.tab === "channels") Channels.load();
            if (S.tab === "groups") Groups.load();
        }
    },

    updateUnreadBadge() {
        let total = 0;
        S.chats.forEach((c) => { if (!c.is_newsletter) total += c.unread || 0; });
        document.querySelectorAll('.rail-btn[data-tab="chats"]').forEach((btn) => {
            let badge = btn.querySelector(".badge");
            if (total > 0) {
                if (!badge) {
                    badge = document.createElement("span");
                    badge.className = "badge";
                    btn.appendChild(badge);
                }
                badge.textContent = total > 99 ? "+99" : total;
            } else if (badge) badge.remove();
        });
    },

    closeChatMobile() {
        document.getElementById("chatWindow").classList.remove("open-mobile");
    },

    async logout() {
        if (!confirm("تسجيل الخروج سيزيل الاقتران ويحذف ملف الجلسة. متابعة؟")) return;
        try {
            await fetch("/api/session/logout", { method: "POST" });
            UI.toast("تم تسجيل الخروج");
        } catch (e) {
            UI.toast("تعذر الاتصال بالسيرفر");
        }
    },
};

document.addEventListener("DOMContentLoaded", () => App.boot());
