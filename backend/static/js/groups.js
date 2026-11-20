/* المجموعات: القائمة، الانضمام عبر رابط، معلومات الأعضاء والمشرفين */

const Groups = {
    async load() {
        try {
            const res = await fetch("/api/groups");
            if (!res.ok) return;
            const data = await res.json();
            S.groups = data.groups || [];
            this.render();
        } catch (e) { /* السيرفر غير متصل بعد */ }
    },

    render() {
        const box = document.getElementById("groupList");
        box.innerHTML = "";
        if (!S.groups.length) {
            box.innerHTML = `<div class="list-empty">
                <svg><use href="#i-groups"></use></svg><br>
                لا توجد مجموعات — استخدم زر الرابط للانضمام لمجموعة عبر دعوة
            </div>`;
            return;
        }
        S.groups.forEach((g) => {
            const row = document.createElement("div");
            row.className = "list-item" + (S.currentChat === g.jid ? " active" : "");
            const avatar = document.createElement("div");
            avatar.className = "avatar";
            avatar.textContent = (g.name || "G").charAt(0).toUpperCase();
            UI.applyAvatar(avatar, g.jid, true);
            const main = document.createElement("div");
            main.className = "li-main";
            const chat = S.chats.get(g.jid);
            const last = chat && chat.last_message ? chat.last_message : "";
            main.innerHTML = `
                <div class="li-top"><span class="li-name">${UI.esc(g.name)}</span></div>
                <div class="li-bottom"><span class="li-preview">${last ? UI.esc(last) : (g.size ? g.size + " عضو" : "مجموعة")}</span></div>`;
            row.appendChild(avatar);
            row.appendChild(main);
            row.onclick = () => Chats.open(g.jid);
            box.appendChild(row);
        });
    },

    async joinByLink() {
        const input = document.getElementById("groupLinkInput");
        const result = document.getElementById("groupJoinResult");
        const link = input.value.trim();
        if (!link) { result.textContent = "أدخل رابط الدعوة"; result.className = "modal-result err"; return; }
        result.textContent = "جارٍ الانضمام...";
        result.className = "modal-result";
        const body = new FormData();
        body.append("link", link);
        try {
            const res = await fetch("/api/groups/join", { method: "POST", body });
            const data = await res.json();
            if (!res.ok) {
                result.textContent = data.detail || "فشل الانضمام";
                result.className = "modal-result err";
                return;
            }
            result.textContent = `تم الانضمام إلى المجموعة (${data.jid})`;
            result.className = "modal-result ok";
            await this.load();
            await Chats.refresh();
            UI.closeModal("joinGroupModal");
            UI.toast("تم الانضمام للمجموعة");
        } catch (e) {
            result.textContent = "تعذر الاتصال بالسيرفر";
            result.className = "modal-result err";
        }
    },

    async showInfo(jid) {
        const modal = document.getElementById("groupInfoModal");
        const nameEl = document.getElementById("groupInfoName");
        const topicEl = document.getElementById("groupInfoTopic");
        const membersBox = document.getElementById("groupMembers");
        nameEl.textContent = "جارٍ التحميل...";
        topicEl.textContent = "";
        membersBox.innerHTML = "";
        UI.openModal("groupInfoModal");
        try {
            const res = await fetch(`/api/groups/${encodeURIComponent(jid)}/info`);
            const info = await res.json();
            if (!res.ok) { nameEl.textContent = info.detail || "تعذر التحميل"; return; }
            nameEl.textContent = info.name;
            topicEl.textContent = info.topic || "";
            const admins = info.participants.filter((p) => p.is_admin || p.is_super_admin);
            const adminJids = new Set(admins.map((p) => p.jid));
            const head = document.createElement("p");
            head.className = "contact-jid";
            head.textContent = `${info.size} عضو — ${admins.length} مشرف`;
            membersBox.appendChild(head);
            info.participants.forEach((p) => {
                const row = document.createElement("div");
                row.className = "member-row";
                const avatar = document.createElement("div");
                avatar.className = "avatar";
                avatar.style.width = "38px";
                avatar.style.height = "38px";
                avatar.style.fontSize = "15px";
                avatar.textContent = UI.phoneOf(p.jid).charAt(0) || "?";
                UI.applyAvatar(avatar, p.jid);
                const name = document.createElement("div");
                name.className = "member-name";
                const chat = S.chats.get(p.jid);
                name.textContent = (chat && chat.name) || UI.phoneOf(p.jid);
                row.appendChild(avatar);
                row.appendChild(name);
                if (p.is_admin || p.is_super_admin) {
                    const badge = document.createElement("span");
                    badge.className = "admin-badge";
                    badge.textContent = "مشرف";
                    row.appendChild(badge);
                }
                membersBox.appendChild(row);
            });
        } catch (e) {
            nameEl.textContent = "تعذر الاتصال بالسيرفر";
        }
    },
};
