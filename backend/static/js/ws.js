/* اتصال WebSocket اللحظي مع إعادة اتصال تلقائي */

const WS = {
    attempts: 0,

    connect() {
        const proto = location.protocol === "https:" ? "wss:" : "ws:";
        const url = `${proto}//${location.host}/ws`;
        try {
            S.ws = new WebSocket(url);
        } catch (e) {
            setTimeout(() => this.connect(), 3000);
            return;
        }
        S.ws.onopen = () => {
            S.wsReady = true;
            this.attempts = 0;
            this.send({ type: "ping" });
            App.syncAfterReconnect();
        };
        S.ws.onmessage = (evt) => {
            let data;
            try { data = JSON.parse(evt.data); } catch (e) { return; }
            this.dispatch(data);
        };
        S.ws.onclose = () => {
            S.wsReady = false;
            this.attempts += 1;
            const delay = Math.min(1000 * 2 ** Math.min(this.attempts, 5), 30000);
            setTimeout(() => this.connect(), delay);
        };
        S.ws.onerror = () => { try { S.ws.close(); } catch (e) {} };
    },

    send(obj) {
        if (S.ws && S.wsReady) {
            try { S.ws.send(JSON.stringify(obj)); } catch (e) {}
        }
    },

    dispatch(data) {
        switch (data.type) {
            case "connection":
                S.connection = data.state;
                S.paired = data.paired;
                S.qrSvg = data.qr;
                S.pairingCode = data.pairing_code;
                S.me = data.me || {};
                Pairing.render();
                break;
            case "qr":
                S.qrSvg = data.svg;
                Pairing.renderQr();
                break;
            case "pairing_code":
                S.pairingCode = data.code;
                Pairing.renderCode();
                break;
            case "pair_error":
                Pairing.showError(data.error);
                break;
            case "message":
                if (S.chats.get(data.chat)?.is_newsletter || (data.message?.chat || "").endsWith("@newsletter")) {
                    Channels.onPost(data.chat, data.message);
                } else {
                    Chats.onIncoming(data.chat, data.message);
                }
                break;
            case "message_media":
                Chats.onMediaReady(data.chat, data.id, data.media);
                break;
            case "message_deleted":
                Chats.onDeleted(data.chat, data.id);
                break;
            case "receipt":
                Chats.onReceipt(data.chat, data.ids, data.receipt);
                break;
            case "reaction":
                Chats.applyReactions(data.chat, data.id, data.reactions);
                break;
            case "typing":
                Chats.onTyping(data.chat, data.state, data.media);
                break;
            case "presence":
                Chats.onPresence(data.jid, data.available, data.lastseen);
                break;
            case "about":
                Chats.onAbout(data.jid, data.status);
                break;
            case "status":
                Statuses.onIncoming(data.status);
                break;
            case "status_media":
                Statuses.onMediaReady(data.id, data.media);
                break;
            case "chat_updated":
            case "chats_updated":
            case "history_synced":
            case "chat_name":
                Chats.refresh();
                break;
            case "avatar_changed":
                S.contactCache.delete(data.jid);
                UI.loadAvatar(data.jid, true).then(() => Chats.rerender());
                break;
            case "channels_updated":
                Channels.load();
                break;
            case "settings":
                S.privacyRead = data.privacy_read;
                App.applyPrivacyToggle();
                break;
            case "logged_out":
                S.paired = false;
                S.connection = "logged_out";
                S.chats.clear();
                S.chatsLoaded = false;
                Pairing.render();
                break;
        }
    },
};
