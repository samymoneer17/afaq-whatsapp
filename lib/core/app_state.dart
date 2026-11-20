// الحالة المركزية للتطبيق — إدارة الجلسة والمحادثات والإعدادات واللغة والثيم
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

enum ThemeModePref { system, light, dark }

enum AppLang { system, arabic, english }

class AppState extends ChangeNotifier {
  late ApiClient api;
  WsService? _ws;

  // ---------------- الجلسة
  SessionInfo session = SessionInfo.empty;
  bool serverOk = false;
  DateTime? lastSync;

  // ---------------- البيانات
  List<Chat> chats = [];
  final Map<String, List<Message>> _messages =
      {}; // jid -> messages (أقدم أولاً)
  final Map<String, bool> _messagesLoaded = {};
  final Map<String, String> typing = {}; // jid -> "typing" | "recording"
  final Map<String, String> avatarCache = {}; // jid -> url
  final Map<String, ContactInfo> contactCache = {};
  List<StatusItem> statuses = [];
  List<Channel> channels = [];
  List<Map<String, dynamic>> groups = [];

  // ---------------- الإعدادات
  ThemeModePref themePref = ThemeModePref.system;
  AppLang lang = AppLang.system;
  String serverUrl = '';
  bool privacyRead = false;

  // ---------------- الغرفة المفتوحة حالياً
  String openChatJid = '';

  bool get paired => session.paired;
  bool get connecting =>
      session.state == 'connecting' || session.state == 'reconnecting';

  // ==================================================================
  // التهيئة
  // ==================================================================
  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    serverUrl = sp.getString('server_url') ?? '';
    themePref = ThemeModePref.values[sp.getInt('theme') ?? 0];
    lang = AppLang.values[sp.getInt('lang') ?? 0];
    privacyRead = sp.getBool('privacy_read') ?? false;
    api = ApiClient(serverUrl);
    if (serverUrl.isNotEmpty && paired) {
      await _startWs();
      unawaited(refreshAll());
    } else if (serverUrl.isNotEmpty) {
      await _startWs();
    }
  }

  Future<void> setServerUrl(String url) async {
    final clean = url.trim().endsWith('/')
        ? url.trim().substring(0, url.trim().length - 1)
        : url.trim();
    serverUrl = clean;
    api = ApiClient(clean);
    final sp = await SharedPreferences.getInstance();
    await sp.setString('server_url', clean);
    await _startWs();
    notifyListeners();
  }

  Future<void> _startWs() async {
    if (!api.hasBase) return;
    _ws?.dispose();
    final ws = WsService(api.base);
    _ws = ws;
    ws.connect();
    ws.events.listen(_onWsEvent);
  }

  Future<void> closeSession() async {
    chats = [];
    _messages.clear();
    _messagesLoaded.clear();
    statuses = [];
    channels = [];
    groups = [];
    session = SessionInfo.empty;
    notifyListeners();
  }

  // ==================================================================
  // أحداث WebSocket
  // ==================================================================
  void _onWsEvent(WsEvent e) {
    switch (e.kind) {
      case WsEventKind.connection:
        session = SessionInfo.fromJson(e.data);
        if (session.paired) unawaited(refreshAll());
        notifyListeners();
      case WsEventKind.pairingCode:
        session = SessionInfo(
          state: session.state,
          paired: false,
          qrSvg: session.qrSvg,
          pairingCode: e.data['code']?.toString() ?? '',
          me: session.me,
        );
        notifyListeners();
      case WsEventKind.pairError:
        session = SessionInfo(
            state: session.state,
            paired: false,
            pairError: e.data['error']?.toString() ?? '');
        notifyListeners();
      case WsEventKind.message:
        final chat = e.data['chat']?.toString() ?? '';
        final raw = e.data['message'];
        if (raw is Map) {
          final msg = Message.fromJson(raw.cast<String, dynamic>());
          addMessage(chat, msg);
          _bumpChat(chat, msg);
        }
        notifyListeners();
      case WsEventKind.reaction:
        final chat = e.data['chat']?.toString() ?? '';
        final id = e.data['id']?.toString() ?? '';
        final list = _messages[chat];
        if (list != null) {
          final i = list.indexWhere((m) => m.id == id);
          if (i >= 0) {
            final reactions = <String, String>{};
            final raw = e.data['reactions'];
            if (raw is Map)
              raw.forEach((k, v) => reactions[k.toString()] = v.toString());
            list[i] = Message(
              id: list[i].id,
              chat: list[i].chat,
              sender: list[i].sender,
              senderName: list[i].senderName,
              type: list[i].type,
              body: list[i].body,
              receipt: list[i].receipt,
              fromMe: list[i].fromMe,
              media: list[i].media,
              timestamp: list[i].timestamp,
              quoted: list[i].quoted,
              reactions: reactions,
              poll: list[i].poll,
            );
            notifyListeners();
          }
        }
      case WsEventKind.typing:
        final chat = e.data['chat']?.toString() ?? '';
        final isRecording = e.data['media']?.toString() == 'audio';
        final stateName = e.data['state']?.toString() ?? 'paused';
        if (stateName == 'paused') {
          typing.remove(chat);
        } else {
          typing[chat] = isRecording ? 'recording' : 'typing';
          // مؤشر الكتابة يزول تلقائياً بعد 6 ثوانٍ احتياطاً
          Future.delayed(const Duration(seconds: 6), () {
            if (typing[chat] != null) {
              typing.remove(chat);
              notifyListeners();
            }
          });
        }
        notifyListeners();
      case WsEventKind.mediaReady:
      case WsEventKind.mediaError:
        final chat = e.data['chat']?.toString() ?? '';
        if (chat.isNotEmpty && _messagesLoaded[chat] == true) {
          unawaited(loadMessages(chat, force: true));
        }
        notifyListeners();
      case WsEventKind.messageDeleted:
        final chat = e.data['chat']?.toString() ?? '';
        final id = e.data['id']?.toString() ?? '';
        _messages[chat]?.removeWhere((m) => m.id == id);
        notifyListeners();
      case WsEventKind.chatUpdated:
      case WsEventKind.chatName:
        unawaited(refreshChats());
      case WsEventKind.channelsUpdated:
        unawaited(refreshChannels());
      case WsEventKind.status:
        unawaited(refreshStatuses());
      case WsEventKind.settings:
        privacyRead = e.data['privacy_read'] == true;
        unawaited(_persistPrivacy());
        notifyListeners();
      case WsEventKind.avatarChanged:
        avatarCache.remove(e.data['jid']?.toString());
        notifyListeners();
      case WsEventKind.pong:
      case WsEventKind.about:
      case WsEventKind.presence:
      case WsEventKind.unknown:
        break;
    }
  }

  void addMessage(String chat, Message msg) {
    final list = _messages.putIfAbsent(chat, () => <Message>[]);
    final i = list.indexWhere((m) => m.id == msg.id);
    if (i >= 0) {
      list[i] = msg;
    } else {
      list.add(msg);
    }
  }

  void _bumpChat(String jid, Message msg) {
    final i = chats.indexWhere((c) => c.jid == jid);
    final snippet =
        msg.body.isNotEmpty ? msg.body : (msg.isMedia ? 'وسائط' : '');
    if (i >= 0) {
      final c = chats[i];
      final fromMeInc = msg.fromMe ? 0 : 1;
      chats[i] = Chat(
        jid: c.jid,
        name: c.name,
        lastMessage: snippet,
        lastTimeStr: '${msg.timestamp}',
        unread: msg.fromMe ? c.unread : c.unread + fromMeInc,
        isGroup: c.isGroup,
        isNewsletter: c.isNewsletter,
        picture: c.picture,
        members: c.members,
      );
      if (openChatJid == jid && !msg.fromMe) _markReadQuiet(jid);
    } else {
      chats.insert(
          0,
          Chat(
              jid: jid, lastMessage: snippet, lastTimeStr: '${msg.timestamp}'));
      unawaited(refreshChats());
    }
  }

  // ==================================================================
  // التحديث من REST
  // ==================================================================
  Future<void> refreshAll() async {
    await refreshSession();
    await refreshChats();
    await refreshStatuses();
    await refreshChannels();
    await refreshGroups();
  }

  Future<void> refreshSession() async {
    if (!api.hasBase) return;
    try {
      session = await api.sessionStatus();
      serverOk = true;
      lastSync = DateTime.now();
    } catch (_) {
      serverOk = false;
    }
    notifyListeners();
  }

  Future<void> refreshChats() async {
    if (!api.hasBase) return;
    try {
      chats = await api.chats();
      serverOk = true;
    } catch (_) {
      serverOk = false;
    }
    notifyListeners();
  }

  Future<void> refreshStatuses() async {
    if (!api.hasBase) return;
    try {
      statuses = await api.statuses();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshChannels() async {
    if (!api.hasBase) return;
    try {
      channels = await api.newsletters();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> refreshGroups() async {
    if (!api.hasBase) return;
    try {
      groups = await api.groups();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> loadMessages(String jid, {bool force = false}) async {
    if (!api.hasBase) return;
    if (!force && _messagesLoaded[jid] == true) return;
    try {
      final list = await api.messages(jid, limit: 100);
      _messages[jid] = list;
      _messagesLoaded[jid] = true;
      notifyListeners();
    } catch (_) {}
  }

  List<Message> messagesOf(String jid) => _messages[jid] ?? const [];

  Future<void> markRead(String jid) async {
    openChatJid = jid;
    final i = chats.indexWhere((c) => c.jid == jid);
    if (i < 0 || chats[i].unread == 0) return;
    chats[i] = Chat(
      jid: chats[i].jid,
      name: chats[i].name,
      lastMessage: chats[i].lastMessage,
      lastTimeStr: chats[i].lastTimeStr,
      unread: 0,
      isGroup: chats[i].isGroup,
      isNewsletter: chats[i].isNewsletter,
      picture: chats[i].picture,
      members: chats[i].members,
    );
    notifyListeners();
    try {
      final ids =
          (messagesOf(jid).where((m) => !m.fromMe).map((m) => m.id).toList());
      await api.markRead(jid, ids);
    } catch (_) {}
  }

  void _markReadQuiet(String jid) {
    final i = chats.indexWhere((c) => c.jid == jid);
    if (i >= 0 && chats[i].unread > 0) {
      chats[i] = Chat(
        jid: chats[i].jid,
        name: chats[i].name,
        lastMessage: chats[i].lastMessage,
        lastTimeStr: chats[i].lastTimeStr,
        unread: 0,
        isGroup: chats[i].isGroup,
        isNewsletter: chats[i].isNewsletter,
        picture: chats[i].picture,
        members: chats[i].members,
      );
    }
  }

  Future<Message> sendMessage(
    String jid, {
    required String type,
    String body = '',
    String replyTo = '',
    String options = '[]',
    Uint8List? bytes,
    String? fileName,
    String? mime,
  }) async {
    final msg = await api.send(jid,
        type: type,
        body: body,
        replyTo: replyTo,
        options: options,
        bytes: bytes,
        fileName: fileName,
        mime: mime);
    addMessage(jid, msg);
    _bumpChat(jid, msg);
    notifyListeners();
    return msg;
  }

  Future<void> sendPresence(String jid, bool composing,
      {bool audio = false}) async {
    _ws?.send({
      'type': 'presence',
      'chat': jid,
      'state': composing ? 'composing' : 'paused',
      'media': audio ? 'audio' : 'text',
    });
  }

  void sendOpenChat(String jid) {
    openChatJid = jid;
    _ws?.send({'type': 'open_chat', 'chat': jid});
  }

  Future<String> avatarOf(String jid, {bool force = false}) async {
    if (!force && avatarCache.containsKey(jid)) return avatarCache[jid] ?? '';
    final url = await api.avatar(jid, force: force);
    if (url.isNotEmpty) avatarCache[jid] = url;
    return url;
  }

  // ==================================================================
  // الإعدادات المحلية
  // ==================================================================
  Future<void> setTheme(ThemeModePref p) async {
    themePref = p;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('theme', p.index);
    notifyListeners();
  }

  Future<void> setLang(AppLang l) async {
    lang = l;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('lang', l.index);
    notifyListeners();
  }

  Future<void> setPrivacyRead(bool v) async {
    privacyRead = v;
    await _persistPrivacy();
    notifyListeners();
    try {
      await api.saveSettings(privacyRead: v);
    } catch (_) {}
  }

  Future<void> _persistPrivacy() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('privacy_read', privacyRead);
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } catch (_) {}
    await closeSession();
  }
}
