// عميل REST + WebSocket — يغطي كل نقاط النهاية الـ27 في الباكند
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  String base; // مثال: http://169.58.232.88:8000
  final http.Client _http = http.Client();

  ApiClient(this.base);

  void setBase(String url) {
    base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  bool get hasBase => base.startsWith('http');

  /// يحوّل مسار الوسائط النسبي إلى رابط كامل (مثال: /media/media/x.jpg)
  String mediaUrl(String pathOrUrl) {
    if (pathOrUrl.isEmpty) return '';
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    return '$base${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final q = <String, String>{...?query};
    return Uri.parse('$base/api$path')
        .replace(queryParameters: q.isEmpty ? null : q);
  }

  dynamic _decode(http.Response r) {
    final body = utf8.decode(r.bodyBytes, allowMalformed: true);
    if (r.statusCode >= 400) {
      String detail = 'خطأ ${r.statusCode}';
      try {
        final j = jsonDecode(body);
        if (j is Map && j['detail'] != null) detail = j['detail'].toString();
      } catch (_) {
        if (body.isNotEmpty && body.length < 200) detail = body;
      }
      throw ApiException(r.statusCode, detail);
    }
    if (body.isEmpty) return <String, dynamic>{};
    return jsonDecode(body);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final r =
        await _http.get(_uri(path, query)).timeout(const Duration(seconds: 25));
    return _decode(r);
  }

  Future<dynamic> _post(String path,
      {Map<String, String> fields = const {},
      Uint8List? bytes,
      String? fileField,
      String? fileName,
      String? fileMime,
      Map<String, String>? query}) async {
    http.Response r;
    final uri = _uri(path, query);
    if (bytes != null) {
      final req = http.MultipartRequest('POST', uri)..fields.addAll(fields);
      req.files.add(http.MultipartFile.fromBytes(fileField ?? 'file', bytes,
          filename: fileName ?? 'upload.bin'));
      final streamed =
          await _http.send(req).timeout(const Duration(minutes: 3));
      r = await http.Response.fromStream(streamed);
    } else {
      r = await _http
          .post(uri, body: fields)
          .timeout(const Duration(seconds: 30));
    }
    return _decode(r);
  }

  // ---------------------------------------------------------- الجلسة
  Future<SessionInfo> sessionStatus() async {
    final j = await _get('/session/status');
    return SessionInfo.fromJson((j as Map).cast<String, dynamic>());
  }

  Future<void> pair(String phone) async {
    await _post('/session/pair', fields: {'phone': phone});
  }

  Future<String> requestQr() async {
    final j = await _post('/session/qr');
    return (j as Map)['qr']?.toString() ?? '';
  }

  Future<void> logout() async {
    await _post('/session/logout');
  }

  // ---------------------------------------------------------- المحادثات
  Future<List<Chat>> chats() async {
    final j = await _get('/chats') as Map;
    final list = (j['chats'] as List? ?? const []);
    return list
        .whereType<Map>()
        .map((e) => Chat.fromJson(e.cast<String, dynamic>()))
        .toList()
      ..sort((a, b) => b.lastTimeStr.compareTo(a.lastTimeStr));
  }

  Future<List<Chat>> searchChats(String term) async {
    if (term.trim().isEmpty) return [];
    final j = await _get('/chats/search', {'term': term.trim()}) as Map;
    return ((j['chats'] as List? ?? const []) as List)
        .whereType<Map>()
        .map((e) => Chat.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<List<Message>> messages(String jid,
      {int offset = 0, int limit = 50}) async {
    final j = await _get('/chats/${Uri.encodeComponent(jid)}/messages',
        {'offset': '$offset', 'limit': '$limit'}) as Map;
    return ((j['messages'] as List? ?? const []) as List)
        .whereType<Map>()
        .map((e) => Message.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// بدء محادثة برقم هاتف — يعيد معلومات الرقم إن كان مسجلاً في واتساب
  Future<Map<String, dynamic>> startChat(String phone) async {
    final j = await _post('/chats/start', fields: {'phone': phone});
    return (j as Map).cast<String, dynamic>();
  }

  Future<void> markRead(String jid, List<String> ids) async {
    await _http.post(_uri('/chats/${Uri.encodeComponent(jid)}/read'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ids': ids}));
  }

  Future<void> react(String chat, String id, String emoji) async {
    await _post('/messages/react',
        fields: {'chat': chat, 'id': id, 'emoji': emoji});
  }

  /// إرسال رسالة نصية/وسائط — type: text|image|video|audio|document|sticker|poll
  Future<Message> send(String jid,
      {required String type,
      String body = '',
      String replyTo = '',
      String options = '[]',
      Uint8List? bytes,
      String? fileName,
      String? mime}) async {
    final fields = <String, String>{
      'type': type,
      'body': body,
      'reply_to': replyTo,
      'options': options,
    };
    final j = await _post('/chats/${Uri.encodeComponent(jid)}/send',
        fields: fields,
        bytes: bytes,
        fileField: 'file',
        fileName: fileName,
        fileMime: mime);
    return Message.fromJson(
        ((j as Map)['message'] as Map).cast<String, dynamic>());
  }

  // ---------------------------------------------------------- الوسائط والمعلومات
  Future<String> avatar(String jid, {bool force = false}) async {
    try {
      final j =
          await _get('/avatar/${Uri.encodeComponent(jid)}', {'force': '$force'})
              as Map;
      final u = j['url'];
      return u == null ? '' : u.toString();
    } catch (_) {
      return '';
    }
  }

  Future<ContactInfo> contactInfo(String jid) async {
    final j = await _get('/contact/${Uri.encodeComponent(jid)}/info') as Map;
    return ContactInfo.fromJson(j.cast<String, dynamic>());
  }

  // ---------------------------------------------------------- الحالات
  Future<List<StatusItem>> statuses() async {
    final j = await _get('/statuses') as Map;
    return ((j['statuses'] as List? ?? const []) as List)
        .whereType<Map>()
        .map((e) => StatusItem.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  // ---------------------------------------------------------- القنوات
  Future<List<Channel>> newsletters() async {
    final j = await _get('/newsletters') as Map;
    return ((j['newsletters'] as List? ?? const []) as List)
        .whereType<Map>()
        .map((e) => Channel.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  Future<Channel> newsletterPreview(String invite) async {
    final j = await _post('/newsletters/preview', fields: {'invite': invite});
    return Channel.fromJson((j as Map).cast<String, dynamic>());
  }

  Future<void> newsletterJoin(String invite) async {
    await _post('/newsletters/join', fields: {'invite': invite});
  }

  Future<void> newsletterLeave(String jid) async {
    await _post('/newsletters/${Uri.encodeComponent(jid)}/leave');
  }

  Future<List<Message>> newsletterPosts(String jid, {int count = 50}) async {
    final j = await _get('/newsletters/${Uri.encodeComponent(jid)}/posts',
        {'count': '$count'}) as Map;
    return ((j['posts'] as List? ?? const []) as List)
        .whereType<Map>()
        .map((e) => Message.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  // ---------------------------------------------------------- المجموعات
  Future<List<Map<String, dynamic>>> groups() async {
    final j = await _get('/groups') as Map;
    return ((j['groups'] as List? ?? const []) as List)
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<GroupInfo> groupInfo(String jid) async {
    final j = await _get('/groups/${Uri.encodeComponent(jid)}/info') as Map;
    return GroupInfo.fromJson(j.cast<String, dynamic>());
  }

  Future<void> joinGroup(String link) async {
    await _post('/groups/join', fields: {'link': link});
  }

  // ---------------------------------------------------------- الإعدادات
  Future<void> saveSettings({bool? privacyRead, String? theme}) async {
    await _post('/settings', fields: {
      if (privacyRead != null) 'privacy_read': privacyRead ? 'true' : 'false',
      if (theme != null) 'theme': theme,
    });
  }

  /// اختبار اتصال الخادم — يرمي استثناء إن فشل
  Future<Duration> ping() async {
    final w = Stopwatch()..start();
    await _get('/session/status');
    return w.elapsed;
  }
}

/// أحداث WebSocket القادمة من الخادم
enum WsEventKind {
  connection,
  message,
  reaction,
  typing,
  presence,
  about,
  chatName,
  avatarChanged,
  pairError,
  pairingCode,
  chatUpdated,
  channelsUpdated,
  messageDeleted,
  status,
  settings,
  mediaReady,
  mediaError,
  pong,
  unknown,
}

class WsEvent {
  final WsEventKind kind;
  final Map<String, dynamic> data;
  const WsEvent(this.kind, this.data);

  factory WsEvent.fromJson(Map<String, dynamic> j) {
    const map = {
      'connection': WsEventKind.connection,
      'message': WsEventKind.message,
      'reaction': WsEventKind.reaction,
      'typing': WsEventKind.typing,
      'presence': WsEventKind.presence,
      'about': WsEventKind.about,
      'chat_name': WsEventKind.chatName,
      'avatar_changed': WsEventKind.avatarChanged,
      'pair_error': WsEventKind.pairError,
      'pairing_code': WsEventKind.pairingCode,
      'chat_updated': WsEventKind.chatUpdated,
      'channels_updated': WsEventKind.channelsUpdated,
      'message_deleted': WsEventKind.messageDeleted,
      'status': WsEventKind.status,
      'settings': WsEventKind.settings,
      'media_ready': WsEventKind.mediaReady,
      'media_error': WsEventKind.mediaError,
      'pong': WsEventKind.pong,
    };
    final kind = map[j['type']] ?? WsEventKind.unknown;
    return WsEvent(kind, j.cast<String, dynamic>());
  }
}

/// اتصال WebSocket مع إعادة اتصال تلقائي ونبض كل 25 ثانية
class WsService {
  final String base;
  final _events = StreamController<WsEvent>.broadcast();
  StreamSubscription? _sub;
  WebSocketChannel? _channel;
  Timer? _heartbeat, _reconnect;
  int _retry = 0;
  bool _disposed = false;
  bool connected = false;

  Stream<WsEvent> get events => _events.stream;

  WsService(this.base);

  void connect() {
    if (_disposed || !base.startsWith('http')) return;
    final wsUrl = base.replaceFirst(RegExp(r'^http'), 'ws') + '/ws';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _sub = _channel!.stream.listen(
        _onData,
        onError: (_) => _scheduleReconnect(),
        onDone: () => _scheduleReconnect(),
      );
      connected = true;
      _retry = 0;
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(
          const Duration(seconds: 25), (_) => _safeSend({'type': 'ping'}));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onData(dynamic raw) {
    try {
      final j = jsonDecode(raw.toString());
      if (j is Map) {
        connected = true;
        _events.add(WsEvent.fromJson(j.cast<String, dynamic>()));
      }
    } catch (_) {}
  }

  void send(Map<String, dynamic> payload) => _safeSend(payload);

  void _safeSend(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (_) {}
  }

  void _scheduleReconnect() {
    if (_disposed || connected == false && _reconnect?.isActive == true) return;
    connected = false;
    _heartbeat?.cancel();
    _sub?.cancel();
    _channel = null;
    final delay = Duration(seconds: (_retry * 2).clamp(2, 30));
    _retry++;
    _reconnect?.cancel();
    _reconnect = Timer(delay, connect);
  }

  void dispose() {
    _disposed = true;
    _heartbeat?.cancel();
    _reconnect?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _events.close();
  }
}
