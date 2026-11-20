/* أدوات الواجهة المشتركة: النوافذ، التنبيهات، الصور الشخصية، العناصر */

const UI = {
    /* --------- عناصر نصية --------- */
    esc(text) {
        const div = document.createElement("div");
        div.textContent = text == null ? "" : String(text);
        return div.innerHTML;
    },

    linkify(text) {
        const escaped = this.esc(text);
        return escaped.replace(/(https?:\/\/[^\s<]+)/g, (url) =>
            `<a href="${url}" target="_blank" rel="noopener" style="text-decoration:underline">${url}</a>`);
    },

    fmtTime(ts) {
        if (!ts) return "";
        return new Intl.DateTimeFormat("ar-SA-u-nu-latn-ca-islamic-umalqura", {
            hour: "2-digit", minute: "2-digit",
        }).format(new Date(ts * 1000));
    },

    fmtDate(ts) {
        const d = new Date(ts * 1000);
        const today = new Date();
        const yesterday = new Date(today);
        yesterday.setDate(today.getDate() - 1);
        const sameDay = (a, b) => a.toDateString() === b.toDateString();
        if (sameDay(d, today)) return "اليوم";
        if (sameDay(d, yesterday)) return "أمس";
        return new Intl.DateTimeFormat("ar-SA-u-nu-latn-ca-islamic-umalqura", {
            day: "numeric", month: "long", year: "numeric",
        }).format(d);
    },

    fmtChatTime(ts) {
        if (!ts) return "";
        const d = new Date(ts * 1000);
        const today = new Date();
        if (d.toDateString() === today.toDateString()) return this.fmtTime(ts);
        const yesterday = new Date(today);
        yesterday.setDate(today.getDate() - 1);
        if (d.toDateString() === yesterday.toDateString()) return "أمس";
        return new Intl.DateTimeFormat("ar-SA-u-nu-latn-ca-islamic-umalqura", {
            day: "numeric", month: "numeric", year: "numeric",
        }).format(d);
    },

    fmtSize(bytes) {
        if (!bytes) return "";
        if (bytes < 1024) return bytes + " بايت";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " ك.ب";
        return (bytes / (1024 * 1024)).toFixed(1) + " م.ب";
    },

    phoneOf(jid) {
        return (jid || "").split("@")[0].replace(/^966/, "0").replace(/(\d{3})(\d{3})(\d{4})/, "$1 $2 $3");
    },

    displayName(chat) {
        if (!chat) return "-";
        if (chat.name) return chat.name;
        const jid = chat.jid || chat;
        return this.phoneOf(jid);
    },

    /* --------- النوافذ المنبثقة --------- */
    openModal(id) { document.getElementById(id).classList.remove("hidden"); },
    closeModal(id) { document.getElementById(id).classList.add("hidden"); },

    toast(msg, ms = 3000) {
        const box = document.getElementById("toasts");
        const el = document.createElement("div");
        el.className = "toast";
        el.textContent = msg;
        box.appendChild(el);
        setTimeout(() => el.remove(), ms);
    },

    toggleAttachMenu() {
        document.getElementById("attachMenu").classList.toggle("hidden");
    },

    /* --------- الصور الشخصية --------- */
    _avatarChain: Promise.resolve(),
    _avatarPending: new Map(),

    loadAvatar(jid, force = false) {
        if (!force && S.contactCache.has(jid)) return Promise.resolve(S.contactCache.get(jid));
        if (!force && this._avatarPending.has(jid)) return this._avatarPending.get(jid);
        const promise = new Promise((resolve) => {
            this._avatarChain = this._avatarChain.then(async () => {
                try {
                    const res = await fetch(`/api/avatar/${encodeURIComponent(jid)}?force=${force}`);
                    const data = await res.json();
                    if (data.url) {
                        S.contactCache.set(jid, data.url);
                        resolve(data.url);
                    } else {
                        resolve(null);
                    }
                } catch (e) {
                    resolve(null);
                } finally {
                    this._avatarPending.delete(jid);
                }
            });
        });
        if (!force) this._avatarPending.set(jid, promise);
        return promise;
    },

    applyAvatar(el, jid, isGroup = false, isNewsletter = false) {
        el.textContent = "";
        const cached = S.contactCache.get(jid);
        if (cached) {
            const img = document.createElement("img");
            img.src = cached;
            img.alt = "";
            el.appendChild(img);
            el.onclick = () => UI.showAvatarModal(jid);
            return;
        }
        const name = S.chats.get(jid)?.name || "";
        el.textContent = (name || jid || "?").charAt(0).toUpperCase();
        el.classList.add("clickable");
        this.loadAvatar(jid).then((url) => {
            if (url && el.isConnected) {
                el.textContent = "";
                const img = document.createElement("img");
                img.src = url;
                img.alt = "";
                el.appendChild(img);
                el.onclick = () => UI.showAvatarModal(jid);
            } else if (el.isConnected) {
                el.onclick = () => UI.showAvatarModal(jid);
            }
        });
    },

    avatarModalJid: null,

    showAvatarModal(jid) {
        const url = S.contactCache.get(jid);
        if (!url) return;
        this.avatarModalJid = jid;
        document.getElementById("avatarBigImg").src = url;
        this.openModal("avatarModal");
    },

    downloadUrl(url, name) {
        const a = document.createElement("a");
        a.href = url;
        a.download = name || "download";
        a.click();
    },

    downloadContactAvatar() {
        const url = S.contactCache.get(this.avatarModalJid || "");
        if (url) this.downloadUrl(url, `avatar_${UI.phoneOf(this.avatarModalJid)}.jpg`);
    },

    /* --------- معلومات جهة الاتصال --------- */
    contactInfoJid: null,

    async showContactInfo() {
        if (S.currentChatIsNewsletter || !S.currentChat) return;
        const chat = S.chats.get(S.currentChat);
        if (!chat) return;
        this.contactInfoJid = S.currentChat;
        document.getElementById("contactName").textContent = this.displayName(chat);
        document.getElementById("contactJid").textContent = chat.jid;
        document.getElementById("contactAbout").textContent = "جارٍ التحميل...";
        document.getElementById("contactCheck").textContent = "";
        const avatarEl = document.getElementById("contactAvatarBig");
        avatarEl.textContent = chat.name ? chat.name.charAt(0).toUpperCase() : "?";
        const url = S.contactCache.get(chat.jid);
        if (url) {
            avatarEl.textContent = "";
            avatarEl.appendChild(Object.assign(document.createElement("img"), { src: url, alt: "" }));
        }
        this.openModal("contactModal");
        if (chat.is_group) {
            document.getElementById("contactAbout").textContent = "مجموعة — اضغط على زر المعلومات في رأس الدردشة لعرض الأعضاء";
            document.getElementById("contactCheck").textContent = "";
            return;
        }
        try {
            const res = await fetch(`/api/contact/${encodeURIComponent(chat.jid)}/info`);
            const info = await res.json();
            if (this.contactInfoJid !== chat.jid) return;
            document.getElementById("contactAbout").textContent = info.about || "لا توجد نبذة تعريفية";
            let check = "";
            if (info.on_whatsapp === true) check = "الرقم مسجل على واتساب";
            else if (info.on_whatsapp === false) check = "الرقم غير مسجل على واتساب";
            if (info.verified_name) check += ` — ${info.verified_name}`;
            document.getElementById("contactCheck").textContent = check;
        } catch (e) {
            document.getElementById("contactAbout").textContent = "تعذر تحميل النبذة";
        }
    },

    /* --------- منتقي الإيموجي --------- */
    emojiTarget: null,

    openEmojiPicker(anchor, targetInput) {
        const picker = document.getElementById("emojiPicker");
        this.emojiTarget = targetInput;
        picker.innerHTML = "";
        const tabs = document.createElement("div");
        tabs.className = "emoji-tabs";
        const grid = document.createElement("div");
        grid.className = "emoji-grid";
        const keys = Object.keys(EMOJI_CATEGORIES);
        keys.forEach((cat, idx) => {
            const btn = document.createElement("button");
            btn.textContent = EMOJI_CATEGORIES[cat][0];
            if (idx === 0) btn.classList.add("active");
            btn.onclick = () => {
                tabs.querySelectorAll("button").forEach((b) => b.classList.remove("active"));
                btn.classList.add("active");
                grid.innerHTML = "";
                EMOJI_CATEGORIES[cat].forEach((em) => {
                    const eb = document.createElement("button");
                    eb.textContent = em;
                    eb.onclick = () => this.insertEmoji(em);
                    grid.appendChild(eb);
                });
            };
            tabs.appendChild(btn);
        });
        keys[0] && EMOJI_CATEGORIES[keys[0]].forEach((em) => {
            const eb = document.createElement("button");
            eb.textContent = em;
            eb.onclick = () => this.insertEmoji(em);
            grid.appendChild(eb);
        });
        picker.appendChild(tabs);
        picker.appendChild(grid);
        picker.classList.remove("hidden");
        const rect = anchor.getBoundingClientRect();
        const pw = 340, ph = 320;
        let left = rect.left - pw / 2;
        let top = rect.top - ph - 10;
        if (top < 8) top = 8;
        left = Math.max(8, Math.min(left, window.innerWidth - pw - 8));
        picker.style.left = left + "px";
        picker.style.top = top + "px";
    },

    insertEmoji(emoji) {
        const input = this.emojiTarget;
        if (!input) return;
        const start = input.selectionStart ?? input.value.length;
        const end = input.selectionEnd ?? input.value.length;
        input.value = input.value.slice(0, start) + emoji + input.value.slice(end);
        input.focus();
        input.selectionStart = input.selectionEnd = start + emoji.length;
        input.dispatchEvent(new Event("input"));
    },

    toggle() {
        const picker = document.getElementById("emojiPicker");
        if (picker.classList.contains("hidden")) {
            this.openEmojiPicker(document.querySelector('[title="إيموجي"]'), document.getElementById("msgInput"));
        } else {
            picker.classList.add("hidden");
        }
    },

    openReactionPicker(anchorEl, chat, msgId) {
        const picker = document.getElementById("reactionPicker");
        picker.innerHTML = "";
        REACTION_EMOJIS.forEach((em) => {
            const btn = document.createElement("button");
            btn.textContent = em;
            btn.onclick = async () => {
                picker.classList.add("hidden");
                try {
                    const body = new FormData();
                    body.append("chat", chat);
                    body.append("id", msgId);
                    body.append("emoji", em);
                    const res = await fetch("/api/messages/react", { method: "POST", body });
                    if (!res.ok) {
                        const err = await res.json().catch(() => ({}));
                        this.toast(err.detail || "فشل التفاعل");
                        return;
                    }
                    const data = await res.json();
                    Chats.applyReactions(chat, msgId, data.reactions);
                } catch (e) {
                    this.toast("فشل الاتصال بالسيرفر");
                }
            };
            picker.appendChild(btn);
        });
        picker.classList.remove("hidden");
        const rect = anchorEl.getBoundingClientRect();
        const pw = picker.offsetWidth || 220;
        let left = Math.min(rect.left, window.innerWidth - pw - 10);
        let top = rect.top - 50;
        if (top < 8) top = rect.bottom + 8;
        picker.style.left = Math.max(8, left) + "px";
        picker.style.top = top + "px";
    },

    /* --------- عارض الوسائط --------- */
    openLightbox(path, mime, name) {
        const body = document.getElementById("lightboxBody");
        const dl = document.getElementById("lightboxDl");
        body.innerHTML = "";
        if ((mime || "").startsWith("image/")) {
            body.appendChild(Object.assign(document.createElement("img"), { src: path, alt: "" }));
        } else if ((mime || "").startsWith("video/")) {
            body.appendChild(Object.assign(document.createElement("video"), { src: path, controls: true, autoplay: true }));
        } else {
            body.appendChild(Object.assign(document.createElement("video"), { src: path, controls: true }));
        }
        dl.href = path;
        dl.download = name || "media";
        this.openModal("lightboxModal");
    },
};

document.addEventListener("click", (e) => {
    const picker = document.getElementById("emojiPicker");
    if (!picker.classList.contains("hidden") && !picker.contains(e.target)
        && !e.target.closest('[title="إيموجي"]')) {
        picker.classList.add("hidden");
    }
    const rpicker = document.getElementById("reactionPicker");
    if (!rpicker.classList.contains("hidden") && !rpicker.contains(e.target)) {
        rpicker.classList.add("hidden");
    }
    const attach = document.getElementById("attachMenu");
    if (!attach.classList.contains("hidden") && !e.target.closest(".attach-wrap")) {
        attach.classList.add("hidden");
    }
});

document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
        document.querySelectorAll(".modal:not(.hidden)").forEach((m) => m.classList.add("hidden"));
        document.getElementById("emojiPicker").classList.add("hidden");
        document.getElementById("reactionPicker").classList.add("hidden");
        document.getElementById("attachMenu").classList.add("hidden");
    }
});
