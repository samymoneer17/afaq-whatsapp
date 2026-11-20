/* المحادثات: القائمة، الدردشة، الإرسال، الردود، التفاعلات، التسجيل الصوتي */

const Chats = {
    offset: 0,
    recording: null,
    recorder: null,

    /* ================= القائمة ================= */
    async refresh() {
        try {
            const res = await fetch("/api/chats");
            const data = await res.json();
            data.chats.forEach((c) => {
                const old = S.chats.get(c.jid) || {};
                S.chats.set(c.jid, { ...old, ...c });
            });
            S.chatsLoaded = true;
            this.rerender();
            App.updateUnreadBadge();
        } catch (e) { /* تجاهل */ }
    },

    rerender() {
        const term = (document.getElementById("chatSearch").value || "").trim();
        this.renderList(term);
    },

    renderList(term = "") {
        const box = document.getElementById("chatList");
        box.innerHTML = "";
        const chats = [...S.chats.values()]
            .filter((c) => !c.is_newsletter)
            .sort((a, b) => (b.last_time || 0) - (a.last_time || 0));

        const filtered = term
            ? chats.filter((c) =>
                (c.name || "").includes(term) ||
                (c.jid || "").includes(term) ||
                (c.last_message || "").includes(term))
            : chats;

        if (!filtered.length) {
            box.innerHTML = `<div class="list-empty">
                <svg><use href="#i-chat"></use></svg><br>
                ${term ? "لا توجد نتائج مطابقة للبحث" : "لا توجد محادثات بعد — ستظهر هنا تلقائياً عند وصول الرسائل"}
            </div>`;
            return;
        }

        filtered.forEach((chat) => {
            const row = document.createElement("div");
            row.className = "list-item" + (S.currentChat === chat.jid ? " active" : "");
            row.dataset.jid = chat.jid;

            const avatar = document.createElement("div");
            avatar.className = "avatar";
            avatar.textContent = (chat.name || chat.jid).charAt(0).toUpperCase();
            avatar.onclick = (e) => { e.stopPropagation(); UI.showAvatarModal(chat.jid); };
            UI.applyAvatar(avatar, chat.jid, chat.is_group);

            const main = document.createElement("div");
            main.className = "li-main";
            const typing = S.typingStates.get(chat.jid);
            const typingHtml = typing && typing.state === "typing"
                ? `<span class="typing" style="color:var(--accent)">${typing.media === "audio" ? "يسجل صوتاً..." : "يكتب الآن..."}</span>`
                : UI.esc(chat.last_message || "");
            main.innerHTML = `
                <div class="li-top">
                    <span class="li-name">${UI.esc(UI.displayName(chat))}</span>
                    <span class="li-time">${UI.fmtChatTime(chat.last_time)}</span>
                </div>
                <div class="li-bottom">
                    <span class="li-preview">${typing ? "" : (chat.is_group ? "" : "")}${typingHtml}</span>
                    ${chat.unread > 0 ? `<span class="unread-badge">${chat.unread > 99 ? "+99" : chat.unread}</span>` : ""}
                </div>`;

            row.appendChild(avatar);
            row.appendChild(main);
            row.onclick = () => this.open(chat.jid);
            box.appendChild(row);
        });
    },

    /* ================= فتح الدردشة ================= */
    async open(jid) {
        const chat = S.chats.get(jid);
        if (chat && chat.is_newsletter) { Channels.open(jid); return; }
        S.currentChat = jid;
        S.currentChatIsNewsletter = false;
        S.replyTo = null;
        this.cancelReply();

        document.getElementById("chatEmpty").classList.add("hidden");
        document.getElementById("channelView").classList.add("hidden");
        document.getElementById("chatActive").classList.remove("hidden");
        document.getElementById("chatWindow").classList.add("open-mobile");

        const nameEl = document.getElementById("chatName");
        nameEl.textContent = chat ? UI.displayName(chat) : UI.phoneOf(jid);
        this.updateChatSub(jid);

        const avatar = document.getElementById("chatAvatar");
        avatar.textContent = (chat && chat.name || jid).charAt(0).toUpperCase();
        UI.applyAvatar(avatar, jid, chat && chat.is_group);

        this.offset = 0;
        S.messages.set(jid, new Map());
        S.messageOrder.set(jid, []);
        await this.loadMessages(jid);

        WS.send({ type: "open_chat", chat: jid });
        const ids = [...(S.messages.get(jid) || new Map()).values()]
            .filter((m) => !m.from_me && m.id)
            .map((m) => m.id);
        fetch(`/api/chats/${encodeURIComponent(jid)}/read`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(ids),
        }).then(() => {
            const c = S.chats.get(jid);
            if (c) { c.unread = 0; this.rerender(); App.updateUnreadBadge(); }
        }).catch(() => {});

        document.getElementById("msgInput").focus();
        this.renderList(document.getElementById("chatSearch").value.trim());
    },

    updateChatSub(jid) {
        const sub = document.getElementById("chatSub");
        const chat = S.chats.get(jid);
        const typing = S.typingStates.get(jid);
        if (typing && typing.state === "typing") {
            sub.innerHTML = `<span class="typing">${typing.media === "audio" ? "يسجل صوتاً..." : "يكتب الآن..."}</span>`;
            return;
        }
        if (chat && chat.is_group) {
            sub.textContent = chat.members ? `${chat.members} عضو` : "مجموعة";
        } else {
            sub.textContent = "متصل بالإنترنت";
        }
    },

    async loadMessages(jid) {
        try {
            const res = await fetch(`/api/chats/${encodeURIComponent(jid)}/messages?offset=${this.offset}&limit=50`);
            const data = await res.json();
            const map = S.messages.get(jid) || new Map();
            const order = S.messageOrder.get(jid) || [];
            const older = [];
            data.messages.forEach((m) => {
                if (!map.has(m.id)) older.push(m.id);
                map.set(m.id, m);
            });
            S.messages.set(jid, map);
            S.messageOrder.set(jid, [...older, ...order]);
            S.hasMore.set(jid, data.has_more);
            if (this.offset === 0) {
                this.renderMessages(jid, true);
            } else {
                this.prependMessages(jid, older);
            }
        } catch (e) {
            UI.toast("تعذر تحميل الرسائل");
        }
    },

    loadMore() {
        if (!S.currentChat || !S.hasMore.get(S.currentChat)) return;
        this.offset += 50;
        document.getElementById("loadMore").classList.add("hidden");
        this.loadMessages(S.currentChat);
    },

    /* ================= الرسم ================= */
    renderMessages(jid, scrollBottom) {
        const area = document.getElementById("messagesArea");
        const list = document.getElementById("messageList");
        list.innerHTML = "";
        const order = S.messageOrder.get(jid) || [];
        const map = S.messages.get(jid);

        document.getElementById("loadMore").classList.toggle("hidden", !S.hasMore.get(jid));

        let lastDay = "";
        order.forEach((id) => {
            const m = map.get(id);
            if (!m) return;
            const day = UI.fmtDate(m.timestamp);
            if (day !== lastDay) {
                const chip = document.createElement("div");
                chip.className = "date-chip";
                chip.innerHTML = `<span>${day}</span>`;
                list.appendChild(chip);
                lastDay = day;
            }
            list.appendChild(this.buildBubble(m, jid));
        });

        if (scrollBottom) area.scrollTop = area.scrollHeight;
    },

    prependMessages(jid, olderIds) {
        const area = document.getElementById("messagesArea");
        const oldScroll = area.scrollHeight;
        const list = document.getElementById("messageList");
        const map = S.messages.get(jid);
        olderIds.forEach((id) => {
            const m = map.get(id);
            if (!m) return;
            const frag = document.createDocumentFragment();
            const bubble = this.buildBubble(m, jid);
            frag.appendChild(bubble);
            list.insertBefore(frag, list.firstChild);
        });
        area.scrollTop = area.scrollHeight - oldScroll;
    },

    appendBubble(m) {
        const jid = S.currentChat;
        if (!jid || m.chat !== jid) return;
        const map = S.messages.get(jid);
        if (!map) return;
        if (map.has(m.id)) { map.set(m.id, { ...map.get(m.id), ...m }); this.updateBubble(m.id, m); return; }
        map.set(m.id, m);
        const order = S.messageOrder.get(jid) || [];
        order.push(m.id);
        S.messageOrder.set(jid, order);
        const list = document.getElementById("messageList");
        const area = document.getElementById("messagesArea");
        const nearBottom = area.scrollHeight - area.scrollTop - area.clientHeight < 220;
        const day = UI.fmtDate(m.timestamp);
        const lastBubble = list.lastElementChild;
        const lastIsSameDay = lastBubble && lastBubble.classList.contains("date-chip")
            ? lastBubble.textContent.trim() === day
            : list.querySelector(".date-chip:last-of-type")?.textContent.trim() === day;
        if (!list.querySelector(`.date-chip[data-day="${day}"]`) && !lastIsSameDay) {
            const chip = document.createElement("div");
            chip.className = "date-chip";
            chip.dataset.day = day;
            chip.innerHTML = `<span>${day}</span>`;
            list.appendChild(chip);
        }
        list.appendChild(this.buildBubble(m, jid));
        if (nearBottom || m.from_me) area.scrollTop = area.scrollHeight;
    },

    updateBubble(id, m) {
        const jid = m.chat || S.currentChat;
        if (jid !== S.currentChat) return;
        const el = document.querySelector(`.bubble[data-id="${CSS.escape(id)}"]`);
        if (el) {
            const newRow = this.buildBubble(m, jid);
            el.replaceWith(newRow);
        }
    },

    buildBubble(m, jid) {
        const chat = S.chats.get(jid);
        const row = document.createElement("div");
        row.className = `msg-row ${m.from_me ? "out" : "in"}`;
        const bubble = document.createElement("div");
        bubble.className = `bubble ${m.from_me ? "tail-out" : "tail-in"}`;
        bubble.dataset.id = m.id;

        // اسم المرسل في المجموعات
        if (chat && chat.is_group && !m.from_me && m.sender_name) {
            const name = document.createElement("div");
            name.className = "sender-name";
            name.textContent = m.sender_name;
            bubble.appendChild(name);
        }

        // الاقتباس
        if (m.quoted && m.quoted.id) {
            const quote = document.createElement("div");
            quote.className = "quote-block";
            quote.innerHTML = `<span class="quote-sender">${UI.esc(m.quoted.from_me ? "أنا" : (m.quoted.sender || "رسالة"))}</span>
                <span class="quote-body">${UI.esc(m.quoted.body || "[وسائط]")}</span>`;
            bubble.appendChild(quote);
        }

        // المحتوى
        this.appendContent(bubble, m);

        // الاستطلاع
        if (m.type === "poll" && m.poll && m.poll.options && m.poll.options.length) {
            const poll = document.createElement("div");
            poll.className = "poll-body";
            poll.innerHTML = `<div class="poll-question">${UI.esc(m.poll.name)}</div>` +
                m.poll.options.map((o) =>
                    `<div class="poll-option"><span class="circle"></span>${UI.esc(o)}</div>`).join("");
            bubble.appendChild(poll);
        }

        // شريط الميتا (الوقت + علامات القراءة)
        const meta = document.createElement("div");
        meta.className = "bubble-meta";
        let ticks = "";
        if (m.from_me) {
            if (m.receipt === "read") ticks = `<svg class="tick-read"><use href="#i-done-all"></use></svg>`;
            else if (m.receipt === "delivered") ticks = `<svg><use href="#i-done-all"></use></svg>`;
            else ticks = `<svg><use href="#i-check"></use></svg>`;
        }
        meta.innerHTML = `${ticks}<span>${UI.fmtTime(m.timestamp)}</span>`;
        bubble.appendChild(meta);

        // التفاعلات
        const reactions = m.reactions || {};
        if (Object.keys(reactions).length) {
            const chips = document.createElement("div");
            chips.className = "reactions-chips";
            chips.innerHTML = Object.entries(reactions)
                .map(([emo]) => `<span class="reaction-chip">${emo}</span>`).join("");
            bubble.appendChild(chips);
        }

        // أزرار الإجراءات
        const actions = document.createElement("div");
        actions.className = "msg-actions";
        const reactBtn = document.createElement("button");
        reactBtn.title = "تفاعل";
        reactBtn.innerHTML = `<svg><use href="#i-emoji"></use></svg>`;
        reactBtn.onclick = (e) => { e.stopPropagation(); UI.openReactionPicker(actions, jid, m.id); };
        actions.appendChild(reactBtn);

        const replyBtn = document.createElement("button");
        replyBtn.title = "رد";
        replyBtn.innerHTML = `<svg><use href="#i-reply"></use></svg>`;
        replyBtn.onclick = (e) => { e.stopPropagation(); this.setReply(m); };
        actions.appendChild(replyBtn);

        if (m.media && m.media.path && m.media.state === "ready") {
            const dlBtn = document.createElement("button");
            dlBtn.title = "تنزيل";
            dlBtn.innerHTML = `<svg><use href="#i-download"></use></svg>`;
            dlBtn.onclick = (e) => {
                e.stopPropagation();
                UI.downloadUrl(m.media.path, m.media.name || `media_${m.id}`);
            };
            actions.appendChild(dlBtn);
        }
        bubble.appendChild(actions);
        row.appendChild(bubble);
        return row;
    },

    appendContent(bubble, m) {
        const media = m.media || {};
        if (m.type === "text") {
            const body = document.createElement("div");
            body.innerHTML = UI.linkify(m.body);
            bubble.appendChild(body);
            return;
        }
        if (["image", "video", "sticker"].includes(m.type)) {
            if (media.state === "ready" && media.path) {
                const wrap = document.createElement("div");
                wrap.className = "bubble-media-wrap";
                if (m.type === "sticker") {
                    const img = document.createElement("img");
                    img.className = "sticker-img";
                    img.src = media.path;
                    img.onclick = () => UI.openLightbox(media.path, media.mime, media.name);
                    wrap.appendChild(img);
                } else if (m.type === "image") {
                    const img = document.createElement("img");
                    img.className = "msg-img";
                    img.src = media.path;
                    img.loading = "lazy";
                    img.onclick = () => UI.openLightbox(media.path, media.mime, media.name);
                    wrap.appendChild(img);
                } else {
                    const video = document.createElement("video");
                    video.className = "msg-video";
                    video.src = media.path;
                    video.controls = true;
                    video.preload = "metadata";
                    wrap.appendChild(video);
                }
                const dl = document.createElement("button");
                dl.className = "media-dl-btn";
                dl.title = "تنزيل";
                dl.innerHTML = `<svg><use href="#i-download"></use></svg>`;
                dl.onclick = () => UI.downloadUrl(media.path, media.name || `media_${m.id}`);
                wrap.appendChild(dl);
                bubble.appendChild(wrap);
            } else if (media.state === "failed") {
                const ph = document.createElement("div");
                ph.className = "media-placeholder";
                ph.innerHTML = `<svg><use href="#i-image"></use></svg> تعذر تنزيل الوسائط`;
                bubble.appendChild(ph);
            } else {
                const ph = document.createElement("div");
                ph.className = "media-placeholder";
                ph.innerHTML = `<svg class="spin"><use href="#i-refresh"></use></svg> جارٍ تنزيل ${m.type === "image" ? "الصورة" : m.type === "video" ? "الفيديو" : "الملصق"}...`;
                bubble.appendChild(ph);
            }
        } else if (m.type === "audio") {
            const note = document.createElement("div");
            note.className = "audio-note";
            if (media.state === "ready" && media.path) {
                note.innerHTML = `<svg style="color:var(--accent)"><use href="#i-mic"></use></svg>`;
                const audio = document.createElement("audio");
                audio.controls = true;
                audio.src = media.path;
                note.appendChild(audio);
                const dl = document.createElement("button");
                dl.className = "icon-btn";
                dl.title = "تنزيل";
                dl.innerHTML = `<svg><use href="#i-download"></use></svg>`;
                dl.onclick = () => UI.downloadUrl(media.path, `voice_${m.id}.ogg`);
                note.appendChild(dl);
            } else {
                note.innerHTML = `<svg><use href="#i-mic"></use></svg> جارٍ تنزيل الرسالة الصوتية...`;
            }
            bubble.appendChild(note);
        } else if (m.type === "document") {
            const chip = document.createElement("div");
            chip.className = "doc-chip";
            chip.innerHTML = `<svg><use href="#i-document"></use></svg>
                <div class="li-main">
                    <div class="doc-name">${UI.esc(media.name || "مستند")}</div>
                    <div class="doc-size">${UI.fmtSize(media.size)}</div>
                </div>`;
            if (media.state === "ready" && media.path) {
                chip.style.cursor = "pointer";
                chip.onclick = () => UI.downloadUrl(media.path, media.name || `doc_${m.id}`);
                const dl = document.createElement("button");
                dl.className = "icon-btn";
                dl.innerHTML = `<svg><use href="#i-download"></use></svg>`;
                dl.onclick = (e) => { e.stopPropagation(); UI.downloadUrl(media.path, media.name || `doc_${m.id}`); };
                chip.appendChild(dl);
            } else {
                chip.insertAdjacentHTML("beforeend", `<span class="doc-size">${media.state === "failed" ? "تعذر التنزيل" : "جارٍ التنزيل..."}</span>`);
            }
            bubble.appendChild(chip);
        } else if (m.type === "location") {
            const lat = (media.width || 0) / 1e6;
            const lng = (media.height || 0) / 1e6;
            const ph = document.createElement("div");
            ph.className = "media-placeholder";
            ph.innerHTML = `<svg><use href="#i-phone"></use></svg> موقع: ${lat.toFixed(4)}, ${lng.toFixed(4)} — ${UI.esc(m.body || "")}`;
            bubble.appendChild(ph);
        } else if (m.type === "contact") {
            const ph = document.createElement("div");
            ph.className = "media-placeholder";
            ph.innerHTML = `<svg><use href="#i-phone"></use></svg> بطاقة اتصال`;
            bubble.appendChild(ph);
        } else if (m.type === "unknown") {
            const ph = document.createElement("div");
            ph.className = "media-placeholder";
            ph.textContent = m.body || "رسالة غير مدعومة";
            bubble.appendChild(ph);
        }
    },

    /* ================= تحديثات لحظية ================= */
    onIncoming(chat, m) {
        const map = S.messages.get(chat);
        if (map && S.currentChat === chat) {
            if (map.has(m.id)) { map.set(m.id, m); this.updateBubble(m.id, m); }
            else this.appendBubble(m);
        }
        const existing = S.chats.get(chat);
        if (existing) {
            existing.last_message = m.body || existing.last_message;
            existing.last_time = m.timestamp;
            existing.name = existing.name || (m.sender_name !== "أنا" ? m.sender_name : null);
            if (m.from_me === false && S.currentChat !== chat && !S.privacyRead) {
                existing.unread = (existing.unread || 0) + 1;
            }
        } else {
            S.chats.set(chat, {
                jid: chat, name: m.sender_name && m.sender_name !== "أنا" ? m.sender_name : "",
                last_message: m.body, last_time: m.timestamp, unread: m.from_me ? 0 : 1,
                is_group: chat.endsWith("@g.us"), picture: null,
            });
            UI.loadAvatar(chat);
        }
        this.renderList(document.getElementById("chatSearch").value.trim());
        App.updateUnreadBadge();
        if (S.currentChat === chat) {
            this.updateChatSub(chat);
            if (!m.from_me && !S.privacyRead) {
                fetch(`/api/chats/${encodeURIComponent(chat)}/read`, {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify([m.id]),
                }).catch(() => {});
            }
        }
    },

    onMediaReady(chat, id, media) {
        const map = S.messages.get(chat);
        if (map && map.has(id)) {
            const m = map.get(id);
            m.media = { ...m.media, ...media, state: "ready" };
            if (S.currentChat === chat) this.updateBubble(id, m);
        }
        const st = S.statuses.find((s) => s.id === id);
    },

    onDeleted(chat, id) {
        const map = S.messages.get(chat);
        if (map && map.has(id)) {
            map.delete(id);
            const order = (S.messageOrder.get(chat) || []).filter((x) => x !== id);
            S.messageOrder.set(chat, order);
            if (S.currentChat === chat) this.renderMessages(chat, false);
        }
    },

    onReceipt(chat, ids, receipt) {
        const map = S.messages.get(chat);
        let changed = false;
        ids.forEach((id) => {
            if (map && map.has(id)) {
                const m = map.get(id);
                if (m.receipt !== receipt) {
                    m.receipt = receipt;
                    changed = true;
                    if (S.currentChat === chat) this.updateBubble(id, m);
                }
            }
        });
        if (!map && receipt) {
            // رسائل غير محملة في الذاكرة — لا حاجة لإعادة التحميل
        }
    },

    applyReactions(chat, id, reactions) {
        const map = S.messages.get(chat);
        if (map && map.has(id)) {
            const m = map.get(id);
            m.reactions = reactions;
            if (S.currentChat === chat) this.updateBubble(id, m);
        }
        if (Channels.currentId === chat) Channels.updatePostReactions(id, reactions);
    },

    onTyping(chat, state, media) {
        if (state === "typing") {
            S.typingStates.set(chat, { state, media });
        } else {
            S.typingStates.delete(chat);
        }
        this.renderList(document.getElementById("chatSearch").value.trim());
        if (S.currentChat === chat) this.updateChatSub(chat);
        clearTimeout(this.typingTimers.get(chat));
        if (state === "typing") {
            this.typingTimers.set(chat, setTimeout(() => {
                S.typingStates.delete(chat);
                this.renderList(document.getElementById("chatSearch").value.trim());
                if (S.currentChat === chat) this.updateChatSub(chat);
            }, 8000));
        }
    },

    onPresence(jid, available, lastseen) {
        if (S.currentChat === jid) {
            const sub = document.getElementById("chatSub");
            sub.textContent = available ? "متصل الآن" : (lastseen ? `آخر ظهور ${UI.fmtChatTime(lastseen)}` : "غير متصل");
        }
    },

    onAbout(jid, status) {
        if (UI.contactInfoJid === jid) {
            const el = document.getElementById("contactAbout");
            if (el && el.textContent.includes("جارٍ") === false) el.textContent = status || "لا توجد نبذة";
        }
    },

    /* ================= الإرسال ================= */
    async sendText() {
        const input = document.getElementById("msgInput");
        const body = input.value.trim();
        const chat = S.currentChat;
        if (!body || !chat) return;
        input.value = "";
        input.style.height = "auto";
        this.sendTypingPaused();
        const replyId = S.replyTo ? S.replyTo.id : "";
        const form = new FormData();
        form.append("type", "text");
        form.append("body", body);
        form.append("reply_to", replyId);
        try {
            const res = await fetch(`/api/chats/${encodeURIComponent(chat)}/send`, { method: "POST", body: form });
            const data = await res.json();
            if (!res.ok) {
                UI.toast(data.detail || "فشل الإرسال");
                input.value = body;
                return;
            }
            this.cancelReply();
            this.onIncoming(chat, data.message);
        } catch (e) {
            UI.toast("تعذر الاتصال بالسيرفر");
            input.value = body;
        }
    },

    sendTyping(state, media = "text") {
        const chat = S.currentChat;
        if (!chat) return;
        WS.send({ type: "presence", chat, state, media });
    },

    sendTypingPaused() {
        this.sendTyping("paused", "text");
    },

    /* ---------------- الرد ---------------- */
    setReply(m) {
        S.replyTo = m;
        const strip = document.getElementById("replyStrip");
        strip.classList.remove("hidden");
        const chat = S.chats.get(m.chat || S.currentChat);
        document.getElementById("replyName").textContent =
            m.from_me ? "أنا" : (m.sender_name || UI.displayName(chat));
        document.getElementById("replyBody").textContent = m.body || "[وسائط]";
        document.getElementById("msgInput").focus();
    },

    cancelReply() {
        S.replyTo = null;
        document.getElementById("replyStrip").classList.add("hidden");
    },

    /* ---------------- الملفات ---------------- */
    pickFile(kind) {
        document.getElementById("attachMenu").classList.add("hidden");
        const input = document.getElementById("fileInput");
        input.value = "";
        input.accept = {
            image: "image/*,video/*",
            document: "*/*",
            audio: "audio/*",
            sticker: "image/*",
        }[kind] || "*/*";
        input.onchange = () => {
            const file = input.files[0];
            if (!file) return;
            if (kind === "image") {
                if (file.type.startsWith("video/")) this.uploadFile("video", file);
                else this.uploadFile("image", file);
            } else {
                this.uploadFile(kind, file);
            }
        };
        input.click();
    },

    async uploadFile(kind, file) {
        const chat = S.currentChat;
        if (!chat) return;
        const replyId = S.replyTo ? S.replyTo.id : "";
        UI.toast(`جارٍ إرسال ${file.name}...`);
        const form = new FormData();
        form.append("type", kind);
        form.append("body", "");
        form.append("reply_to", replyId);
        form.append("file", file);
        try {
            const res = await fetch(`/api/chats/${encodeURIComponent(chat)}/send`, { method: "POST", body: form });
            const data = await res.json();
            if (!res.ok) { UI.toast(data.detail || "فشل الإرسال"); return; }
            this.cancelReply();
            this.onIncoming(chat, data.message);
        } catch (e) {
            UI.toast("تعذر الاتصال بالسيرفر");
        }
    },

    /* ---------------- الاستطلاعات ---------------- */
    openPollModal() {
        document.getElementById("attachMenu").classList.add("hidden");
        document.getElementById("pollQuestion").value = "";
        document.getElementById("pollOptions").innerHTML = `
            <input type="text" class="text-input poll-opt" placeholder="الخيار 1">
            <input type="text" class="text-input poll-opt" placeholder="الخيار 2">`;
        UI.openModal("pollModal");
    },

    addPollOption() {
        const box = document.getElementById("pollOptions");
        if (box.children.length >= 12) { UI.toast("الحد الأقصى 12 خياراً"); return; }
        const inp = document.createElement("input");
        inp.type = "text";
        inp.className = "text-input poll-opt";
        inp.placeholder = `الخيار ${box.children.length + 1}`;
        box.appendChild(inp);
    },

    async sendPoll() {
        const chat = S.currentChat;
        const question = document.getElementById("pollQuestion").value.trim();
        const options = [...document.querySelectorAll(".poll-opt")]
            .map((i) => i.value.trim()).filter(Boolean);
        if (!question || options.length < 2) {
            UI.toast("أدخل السؤال وخيارين على الأقل");
            return;
        }
        const replyId = S.replyTo ? S.replyTo.id : "";
        const form = new FormData();
        form.append("type", "poll");
        form.append("body", question);
        form.append("options", JSON.stringify(options));
        form.append("reply_to", replyId);
        UI.closeModal("pollModal");
        try {
            const res = await fetch(`/api/chats/${encodeURIComponent(chat)}/send`, { method: "POST", body: form });
            const data = await res.json();
            if (!res.ok) { UI.toast(data.detail || "فشل إرسال الاستطلاع"); return; }
            this.cancelReply();
            this.onIncoming(chat, data.message);
        } catch (e) {
            UI.toast("تعذر الاتصال بالسيرفر");
        }
    },

    /* ---------------- بدء محادثة جديدة ---------------- */
    async startNewChat() {
        const phone = document.getElementById("newChatPhone").value.trim();
        const result = document.getElementById("newChatResult");
        if (!phone) { result.textContent = "أدخل رقم الهاتف"; result.className = "modal-result err"; return; }
        result.textContent = "جارٍ فحص الرقم على واتساب...";
        result.className = "modal-result";
        try {
            const body = new FormData();
            body.append("phone", phone);
            const res = await fetch("/api/chats/start", { method: "POST", body });
            const data = await res.json();
            if (res.status === 503) {
                result.textContent = "عميل واتساب غير متصل — تأكد من الاقتران أولاً";
                result.className = "modal-result err";
                return;
            }
            if (!res.ok || !data.on_whatsapp) {
                result.textContent = data.error || data.detail || "الرقم غير مسجل على واتساب";
                result.className = "modal-result err";
                return;
            }
            result.textContent = `الرقم مسجل — بدء المحادثة مع ${data.jid}`;
            result.className = "modal-result ok";
            S.chats.set(data.jid, S.chats.get(data.jid) || {
                jid: data.jid, name: UI.phoneOf(data.jid), last_message: "", last_time: 0,
                unread: 0, is_group: false, picture: null,
            });
            UI.loadAvatar(data.jid);
            setTimeout(() => {
                UI.closeModal("newChatModal");
                App.switchTab("chats");
                this.open(data.jid);
            }, 600);
        } catch (e) {
            result.textContent = "تعذر الاتصال بالسيرفر";
            result.className = "modal-result err";
        }
    },

    /* ---------------- التسجيل الصوتي ---------------- */
    async toggleRecording() {
        if (this.recorder && this.recording) {
            this.recorder.stop();
            return;
        }
        try {
            const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            this.recorder = new MediaRecorder(stream);
            const chunks = [];
            this.recorder.ondataavailable = (e) => chunks.push(e.data);
            this.recorder.onstop = () => {
                stream.getTracks().forEach((t) => t.stop());
                const blob = new Blob(chunks, { type: this.recorder.mimeType || "audio/webm" });
                this.recording = null;
                const btn = document.getElementById("recordBtn");
                btn.classList.add("hidden");
                const sendBtn = document.getElementById("sendBtn");
                sendBtn.classList.remove("hidden");
                sendBtn.innerHTML = `<svg><use href="#i-send"></use></svg>`;
                document.getElementById("msgInput").classList.remove("recording-dot");
                if (blob.size > 1000 && S.currentChat) {
                    const file = new File([blob], `voice_${Date.now()}.webm`, { type: blob.type });
                    this.uploadFile("audio", file);
                }
                this.sendTypingPaused();
            };
            this.recorder.start();
            this.recording = true;
            const btn = document.getElementById("recordBtn");
            btn.classList.remove("hidden");
            document.getElementById("sendBtn").classList.add("hidden");
            document.getElementById("msgInput").classList.add("recording-dot");
            this.sendTyping("composing", "audio");
            UI.toast("جارٍ التسجيل — اضغط زر الميكروفون للإيقاف والإرسال");
        } catch (e) {
            UI.toast("تعذر الوصول إلى الميكروفون");
        }
    },
};
