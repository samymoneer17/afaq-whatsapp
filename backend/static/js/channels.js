/* القنوات (Newsletters): القائمة، الانضمام، المنشورات، التفاعل بالإيموجي */

const Channels = {
    currentId: null,

    async load() {
        try {
            const res = await fetch("/api/newsletters");
            if (!res.ok) return;
            const data = await res.json();
            S.newsletters = data.newsletters || [];
            this.render();
        } catch (e) { /* السيرفر غير متصل بعد */ }
    },

    onPost(chat, message) {
        const nl = S.newsletters.find((n) => n.jid === chat);
        if (nl) {
            nl.last_post = message.body || "";
            if (S.currentId === chat) this.appendPost(message);
        }
        if (S.tab === "channels") this.render();
    },

    render(term = "") {
        const box = document.getElementById("channelList");
        box.innerHTML = "";
        if (!S.newsletters.length) {
            box.innerHTML = `<div class="list-empty">
                <svg><use href="#i-channel"></use></svg><br>
                لا توجد قنوات مشترك بها — استخدم زر + للانضمام عبر رابط القناة
            </div>`;
            return;
        }
        const filtered = term ? S.newsletters.filter((n) => (n.name || "").includes(term)) : S.newsletters;
        filtered.forEach((nl) => {
            const row = document.createElement("div");
            row.className = "list-item" + (S.currentId === nl.jid ? " active" : "");
            const avatar = document.createElement("div");
            avatar.className = "avatar";
            avatar.textContent = (nl.name || "C").charAt(0).toUpperCase();
            UI.applyAvatar(avatar, nl.jid);
            const main = document.createElement("div");
            main.className = "li-main";
            main.innerHTML = `
                <div class="li-top"><span class="li-name">${UI.esc(nl.name)}</span></div>
                <div class="li-bottom"><span class="li-preview">${nl.subscribers ? nl.subscribers.toLocaleString("ar") + " متابع" : "قناة"}</span></div>`;
            row.appendChild(avatar);
            row.appendChild(main);
            row.onclick = () => this.open(nl);
            box.appendChild(row);
        });
    },

    async open(nl) {
        const item = typeof nl === "string" ? S.newsletters.find((n) => n.jid === nl) : nl;
        if (!item) return;
        this.currentId = item.jid;
        S.currentChat = item.jid;
        S.currentChatIsNewsletter = true;

        document.getElementById("chatEmpty").classList.add("hidden");
        document.getElementById("chatActive").classList.add("hidden");
        document.getElementById("channelView").classList.remove("hidden");
        document.getElementById("chatWindow").classList.add("open-mobile");

        document.getElementById("channelName").textContent = item.name;
        document.getElementById("channelSub").textContent =
            `قناة — ${item.subscribers ? item.subscribers.toLocaleString("ar") + " متابع" : ""}`;
        const avatar = document.getElementById("channelAvatar");
        avatar.textContent = (item.name || "C").charAt(0).toUpperCase();
        UI.applyAvatar(avatar, item.jid);

        const box = document.getElementById("channelMessages");
        box.innerHTML = `<div class="list-empty"><svg class="spin"><use href="#i-refresh"></use></svg><br>جارٍ تحميل المنشورات...</div>`;
        S.channelLastPost = null;

        try {
            const res = await fetch(`/api/newsletters/${encodeURIComponent(item.jid)}/posts?count=50`);
            const data = await res.json();
            box.innerHTML = "";
            box.classList.add("newsletter-view");
            const posts = data.posts || [];
            if (!posts.length) {
                box.innerHTML = `<div class="list-empty">لا توجد منشورات بعد</div>`;
            }
            posts.forEach((p) => this.appendPost(p));
            if (posts.length) S.channelLastPost = posts[posts.length - 1];
            box.scrollTop = box.scrollHeight;
        } catch (e) {
            box.innerHTML = `<div class="list-empty">تعذر تحميل المنشورات</div>`;
        }
        this.renderReacts();
        this.renderList();
    },

    appendPost(m) {
        const box = document.getElementById("channelMessages");
        const empty = box.querySelector(".list-empty");
        if (empty) empty.remove();
        const row = document.createElement("div");
        row.className = "msg-row in";
        row.dataset.id = m.id;
        const bubble = document.createElement("div");
        bubble.className = "bubble tail-in";

        this.appendPostContent(bubble, m);

        if (Object.keys(m.reactions || {}).length) {
            const chips = document.createElement("div");
            chips.className = "reactions-chips";
            chips.innerHTML = Object.keys(m.reactions).map((e) => `<span class="reaction-chip">${e}</span>`).join("");
            bubble.appendChild(chips);
        }

        const meta = document.createElement("div");
        meta.className = "bubble-meta";
        meta.innerHTML = `<span>${UI.fmtTime(m.timestamp)}</span>`;
        bubble.appendChild(meta);

        const actions = document.createElement("div");
        actions.className = "msg-actions";
        const reactBtn = document.createElement("button");
        reactBtn.title = "تفاعل بالإيموجي";
        reactBtn.innerHTML = `<svg><use href="#i-emoji"></use></svg>`;
        reactBtn.onclick = (e) => {
            e.stopPropagation();
            UI.openReactionPicker(actions, this.currentId, m.id);
        };
        actions.appendChild(reactBtn);
        bubble.appendChild(actions);
        row.appendChild(bubble);
        box.appendChild(row);
    },

    appendPostContent(bubble, m) {
        const media = m.media || {};
        if (["image", "video", "sticker"].includes(m.type) && media.path && media.state === "ready") {
            if (m.type === "image") {
                const img = document.createElement("img");
                img.className = "msg-img";
                img.src = media.path;
                img.onclick = () => UI.openLightbox(media.path, media.mime, media.name);
                bubble.appendChild(img);
            } else if (m.type === "video") {
                const v = document.createElement("video");
                v.className = "msg-video";
                v.src = media.path;
                v.controls = true;
                bubble.appendChild(v);
            } else {
                const img = document.createElement("img");
                img.className = "sticker-img";
                img.src = media.path;
                bubble.appendChild(img);
            }
        } else if (["image", "video"].includes(m.type)) {
            const ph = document.createElement("div");
            ph.className = "media-placeholder";
            ph.innerHTML = `<svg class="spin"><use href="#i-refresh"></use></svg> جارٍ تنزيل الوسائط...`;
            bubble.appendChild(ph);
        }
        if (m.body) {
            const text = document.createElement("div");
            text.innerHTML = UI.linkify(m.body);
            bubble.appendChild(text);
        }
    },

    updatePostReactions(id, reactions) {
        const box = document.getElementById("channelMessages");
        const row = box.querySelector(`.msg-row[data-id="${CSS.escape(id)}"] .reactions-chips`);
        if (!row) return;
        row.innerHTML = Object.keys(reactions || {}).map((e) => `<span class="reaction-chip">${e}</span>`).join("");
    },

    renderReacts() {
        const box = document.getElementById("channelReacts");
        box.innerHTML = "";
        REACTION_EMOJIS.forEach((em) => {
            const btn = document.createElement("button");
            btn.textContent = em;
            btn.title = "تفاعل مع آخر منشور";
            btn.onclick = () => this.reactLast(em);
            box.appendChild(btn);
        });
    },

    async reactLast(emoji) {
        if (!this.currentId || !S.channelLastPost) {
            UI.toast("لا يوجد منشور للتفاعل معه");
            return;
        }
        const id = S.channelLastPost.id;
        try {
            const body = new FormData();
            body.append("chat", this.currentId);
            body.append("id", id);
            body.append("emoji", emoji);
            const res = await fetch("/api/messages/react", { method: "POST", body });
            const data = await res.json();
            if (!res.ok) { UI.toast(data.detail || "فشل التفاعل"); return; }
            this.updatePostReactions(id, data.reactions);
            UI.toast("تم إرسال التفاعل");
        } catch (e) {
            UI.toast("تعذر الاتصال بالسيرفر");
        }
    },

    async previewInvite() {
        const input = document.getElementById("channelLinkInput");
        const result = document.getElementById("channelPreview");
        const invite = input.value.trim();
        if (!invite) { result.textContent = "أدخل رابط القناة أو معرفها"; result.className = "modal-result err"; return; }
        result.textContent = "جارٍ جلب معلومات القناة...";
        result.className = "modal-result";
        const body = new FormData();
        body.append("invite", invite);
        try {
            const res = await fetch("/api/newsletters/preview", { method: "POST", body });
            const data = await res.json();
            if (!res.ok) {
                result.textContent = data.detail || "تعذر جلب المعلومات";
                result.className = "modal-result err";
                return;
            }
            result.innerHTML = `<b>${UI.esc(data.name)}</b><br>${UI.esc(data.description || "")}<br>${data.subscribers.toLocaleString("ar")} متابع`;
            result.className = "modal-result ok";
        } catch (e) {
            result.textContent = "تعذر الاتصال بالسيرفر";
            result.className = "modal-result err";
        }
    },

    async joinByInvite() {
        const input = document.getElementById("channelLinkInput");
        const result = document.getElementById("channelPreview");
        const invite = input.value.trim();
        if (!invite) { result.textContent = "أدخل رابط القناة أو معرفها"; result.className = "modal-result err"; return; }
        result.textContent = "جارٍ الانضمام...";
        result.className = "modal-result";
        const body = new FormData();
        body.append("invite", invite);
        try {
            const res = await fetch("/api/newsletters/join", { method: "POST", body });
            const data = await res.json();
            if (!res.ok) {
                result.textContent = data.detail || "فشل الانضمام";
                result.className = "modal-result err";
                return;
            }
            result.textContent = `تم الانضمام إلى ${data.name}`;
            result.className = "modal-result ok";
            await this.load();
            UI.closeModal("joinChannelModal");
            UI.toast(`تمت المتابعة: ${data.name}`);
        } catch (e) {
            result.textContent = "تعذر الاتصال بالسيرفر";
            result.className = "modal-result err";
        }
    },

    async leaveCurrent() {
        if (!this.currentId) return;
        const nl = S.newsletters.find((n) => n.jid === this.currentId);
        if (!confirm(`مغادرة قناة "${nl ? nl.name : ""}"؟`)) return;
        try {
            const res = await fetch(`/api/newsletters/${encodeURIComponent(this.currentId)}/leave`, { method: "POST" });
            if (!res.ok) { UI.toast("فشل مغادرة القناة"); return; }
            UI.toast("تمت مغادرة القناة");
            document.getElementById("channelView").classList.add("hidden");
            document.getElementById("chatEmpty").classList.remove("hidden");
            this.currentId = null;
            await this.load();
        } catch (e) {
            UI.toast("تعذر الاتصال بالسيرفر");
        }
    },

    renderList(term = "") {
        if (S.tab !== "channels") return;
        this.render(term);
    },
};
