/* الحالات الواردة: عرض وتنزيل تلقائي */

const Statuses = {
    async load() {
        try {
            const res = await fetch("/api/statuses");
            const data = await res.json();
            S.statuses = data.statuses || [];
            this.render();
        } catch (e) { /* تجاهل */ }
    },

    onIncoming(status) {
        if (S.statuses.some((s) => s.id === status.id)) return;
        S.statuses.unshift(status);
        if (S.tab === "statuses") this.render();
    },

    onMediaReady(id, media) {
        const st = S.statuses.find((s) => s.id === id);
        if (st) {
            st.media_path = media.path;
            st.media_mime = media.mime;
            st.media_state = "ready";
            if (S.tab === "statuses") this.render();
        }
    },

    render() {
        const box = document.getElementById("statusList");
        box.innerHTML = "";
        if (!S.statuses.length) {
            box.innerHTML = `<div class="list-empty">
                <svg><use href="#i-status"></use></svg><br>
                لا توجد حالات بعد — ستظهر حالات جهات الاتصال هنا تلقائياً عند نشرها
            </div>`;
            return;
        }
        // تجميع حسب المرسل
        const groups = new Map();
        S.statuses.forEach((s) => {
            if (!groups.has(s.sender)) groups.set(s.sender, []);
            groups.get(s.sender).push(s);
        });
        groups.forEach((items, sender) => {
            const group = document.createElement("div");
            group.className = "status-group";
            const title = document.createElement("div");
            title.className = "status-group-title";
            const chat = S.chats.get(sender);
            title.textContent = (chat && chat.name) || items[0].sender_name || UI.phoneOf(sender);
            group.appendChild(title);

            const thumbs = document.createElement("div");
            thumbs.className = "status-thumbs";
            items.forEach((s) => {
                const thumb = document.createElement("div");
                thumb.className = "status-thumb";
                thumb.onclick = () => this.view(s);
                if (s.type === "image" && s.media_path && s.media_state === "ready") {
                    thumb.appendChild(Object.assign(document.createElement("img"), { src: s.media_path, alt: "" }));
                } else if (s.type === "video" && s.media_path && s.media_state === "ready") {
                    const v = document.createElement("video");
                    v.src = s.media_path;
                    v.muted = true;
                    v.playsInline = true;
                    thumb.appendChild(v);
                } else {
                    const t = document.createElement("div");
                    t.className = "thumb-text";
                    t.textContent = s.body || (s.type === "video" ? "فيديو (جارٍ التنزيل...)" : "صورة (جارٍ التنزيل...)");
                    thumb.appendChild(t);
                }
                const dl = document.createElement("button");
                dl.className = "thumb-dl";
                dl.title = "تنزيل الحالة";
                dl.innerHTML = `<svg><use href="#i-download"></use></svg>`;
                dl.onclick = (e) => { e.stopPropagation(); this.download(s); };
                thumb.appendChild(dl);
                thumbs.appendChild(thumb);
            });
            group.appendChild(thumbs);
            box.appendChild(group);
        });
    },

    view(s) {
        const body = document.getElementById("statusViewerBody");
        const sender = (S.chats.get(s.sender) && S.chats.get(s.sender).name) || s.sender_name || UI.phoneOf(s.sender);
        body.innerHTML = `<div class="status-meta">
                <span>${UI.esc(sender)}</span>
                <span>${UI.fmtChatTime(s.timestamp)}</span>
            </div>`;
        const content = document.createElement("div");
        content.className = "status-media-view";
        if (s.type === "image" && s.media_path) {
            content.appendChild(Object.assign(document.createElement("img"), { src: s.media_path, alt: "" }));
        } else if (s.type === "video" && s.media_path) {
            content.appendChild(Object.assign(document.createElement("video"), { src: s.media_path, controls: true, autoplay: true }));
        } else if (s.body) {
            content.className = "status-text-view";
            content.textContent = s.body;
        } else {
            content.innerHTML = `<div class="media-placeholder">الوسائط قيد التنزيل...</div>`;
        }
        body.appendChild(content);
        UI.openModal("statusViewerModal");
    },

    download(s) {
        if (s.media_path && s.media_state === "ready") {
            UI.downloadUrl(s.media_path, `status_${UI.phoneOf(s.sender)}_${s.timestamp}.${(s.media_mime || "media").split("/")[1] || "bin"}`);
            UI.toast("تم تنزيل الحالة");
        } else {
            UI.toast(s.type === "text" ? "الحالة نصية — انسخها من العرض" : "الوسائط قيد التنزيل، حاول بعد لحظات");
        }
    },
};
