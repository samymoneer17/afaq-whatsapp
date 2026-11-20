/* الحالة المشتركة للتطبيق */
const S = {
    ws: null,
    wsReady: false,
    connection: "init",        // init|connecting|connected|reconnecting|unpaired|logged_out
    paired: false,
    qrSvg: null,
    pairingCode: null,
    me: {},
    privacyRead: false,
    theme: "dark",

    tab: "chats",
    chats: new Map(),          // jid -> chat object
    chatsLoaded: false,
    currentChat: null,         // jid المفتوح
    currentChatIsNewsletter: false,
    messages: new Map(),       // chat -> Map(id -> message)
    messageOrder: new Map(),   // chat -> [ids مرتبة]
    hasMore: new Map(),
    replyTo: null,             // message object يتم الرد عليه
    typingTimers: new Map(),   // chat -> timer
    typingStates: new Map(),   // chat -> {chat, state, media}

    statuses: [],
    newsletters: [],
    currentNewsletter: null,

    groups: [],
    contactCache: new Map(),   // jid -> avatar url
    channelLastPost: null,
};
