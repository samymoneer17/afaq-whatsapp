// نماذج البيانات — مطابقة حرفياً لصيغ JSON الصادرة من الباكند (row_to_json)
library models;

/// معلومات الجلسة — GET /api/session/status
class SessionInfo {
  final String state;
  final bool paired;
  final String qrSvg; // SVG كامل يُعرض مباشرة
  final String pairingCode;
  final String pairError;
  final Map<String, dynamic> me;
  final bool privacyRead;

  const SessionInfo({
    required this.state,
    required this.paired,
    this.qrSvg = '',
    this.pairingCode = '',
    this.pairError = '',
    this.me = const {},
    this.privacyRead = false,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> j) => SessionInfo(
        state: (j['state'] ?? 'disconnected').toString(),
        paired: j['paired'] == true,
        qrSvg: (j['qr'] ?? '').toString(),
        pairingCode: (j['pairing_code'] ?? '').toString(),
        pairError: (j['pair_error'] ?? '').toString(),
        me: j['me'] is Map<String, dynamic>
            ? j['me'] as Map<String, dynamic>
            : const {},
        privacyRead: j['privacy_read'] == true,
      );

  String get myJid => (me['jid'] ?? '').toString();
  String get myName => (me['name'] ??
          me['pushname'] ??
          (myJid.isEmpty ? '' : myJid.split('@').first))
      .toString();

  static const SessionInfo empty =
      SessionInfo(state: 'disconnected', paired: false);
}

/// بيانات الوسائط داخل الرسالة
class MediaData {
  final String path; // نسبة إلى مجلد downloads — يُبنى منه رابط /media/...
  final String mime;
  final String name;
  final int size;
  final int duration; // ثواني — للصوت
  final int width, height;
  final String state; // none | pending | ready | error

  const MediaData({
    this.path = '',
    this.mime = '',
    this.name = '',
    this.size = 0,
    this.duration = 0,
    this.width = 0,
    this.height = 0,
    this.state = 'none',
  });

  factory MediaData.fromJson(Map<String, dynamic>? j) => MediaData(
        path: (j?['path'] ?? '').toString(),
        mime: (j?['mime'] ?? '').toString(),
        name: (j?['name'] ?? '').toString(),
        size: (int.tryParse('${j?['size'] ?? 0}') ?? 0),
        duration: (int.tryParse('${j?['duration'] ?? 0}') ?? 0),
        width: (int.tryParse('${j?['width'] ?? 0}') ?? 0),
        height: (int.tryParse('${j?['height'] ?? 0}') ?? 0),
        state: (j?['state'] ?? 'none').toString(),
      );

  bool get ready => state == 'ready' && path.isNotEmpty;
  bool get isImage => mime.startsWith('image/') && mime != 'image/webp';
  bool get isSticker => mime == 'image/webp';
  bool get isVideo => mime.startsWith('video/');
  bool get isAudio => mime.startsWith('audio/');
}

/// اقتباس الرد
class QuotedData {
  final String id, body, type, sender;
  final bool fromMe;
  const QuotedData(
      {required this.id,
      this.body = '',
      this.type = 'text',
      this.sender = '',
      this.fromMe = false});

  factory QuotedData.fromJson(Map<String, dynamic> j) => QuotedData(
        id: (j['id'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        type: (j['type'] ?? 'text').toString(),
        sender: (j['sender'] ?? '').toString(),
        fromMe: j['from_me'] == true,
      );
}

/// الرسالة — صيغة row_to_json من الباكند
class Message {
  final String id, chat, sender, senderName, type, body, receipt;
  final bool fromMe;
  final MediaData media;
  final int timestamp; // unix seconds
  final QuotedData? quoted;
  final Map<String, String> reactions; // emoji -> sender
  final PollData? poll;

  const Message({
    required this.id,
    required this.chat,
    this.sender = '',
    this.senderName = '',
    this.type = 'text',
    this.body = '',
    this.receipt = 'pending',
    this.fromMe = false,
    this.media = const MediaData(),
    this.timestamp = 0,
    this.quoted,
    this.reactions = const {},
    this.poll,
  });

  factory Message.fromJson(Map<String, dynamic> j) {
    final quoted = j['quoted'];
    final poll = j['poll'];
    final reactionsRaw = j['reactions'];
    final reactions = <String, String>{};
    if (reactionsRaw is Map) {
      reactionsRaw.forEach((k, v) => reactions[k.toString()] = v.toString());
    }
    return Message(
      id: (j['id'] ?? '').toString(),
      chat: (j['chat'] ?? '').toString(),
      sender: (j['sender'] ?? '').toString(),
      senderName: (j['sender_name'] ?? '').toString(),
      type: (j['type'] ?? 'text').toString(),
      body: (j['body'] ?? '').toString(),
      receipt: (j['receipt'] ?? 'pending').toString(),
      fromMe: j['from_me'] == true,
      media: MediaData.fromJson(j['media'] as Map<String, dynamic>?),
      timestamp: int.tryParse('${j['timestamp'] ?? 0}') ?? 0,
      quoted:
          quoted is Map<String, dynamic> ? QuotedData.fromJson(quoted) : null,
      reactions: reactions,
      poll: poll is Map<String, dynamic> ? PollData.fromJson(poll) : null,
    );
  }

  bool get isMedia =>
      const {'image', 'video', 'audio', 'document', 'sticker'}.contains(type);
  bool get isPoll => poll != null;
}

/// بيانات الاستطلاع
class PollData {
  final String name;
  final List<String> options;
  const PollData({required this.name, this.options = const []});

  factory PollData.fromJson(Map<String, dynamic> j) => PollData(
        name: (j['name'] ?? '').toString(),
        options: ((j['options'] ?? const []) as List)
            .map((e) => e.toString())
            .toList(),
      );
}

/// المحادثة — GET /api/chats
class Chat {
  final String jid, name, lastMessage, lastTimeStr, picture;
  final int unread, members;
  final bool isGroup, isNewsletter;

  const Chat({
    required this.jid,
    this.name = '',
    this.lastMessage = '',
    this.lastTimeStr = '',
    this.unread = 0,
    this.isGroup = false,
    this.isNewsletter = false,
    this.picture = '',
    this.members = 0,
  });

  factory Chat.fromJson(Map<String, dynamic> j) => Chat(
        jid: (j['jid'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        lastMessage: (j['last_message'] ?? '').toString(),
        lastTimeStr: (j['last_time'] ?? '').toString(),
        unread: int.tryParse('${j['unread'] ?? 0}') ?? 0,
        isGroup: j['is_group'] == true,
        isNewsletter: j['is_newsletter'] == true,
        picture: (j['picture'] ?? '').toString(),
        members: int.tryParse('${j['members'] ?? 0}') ?? 0,
      );

  bool get isChannelJid => jid.endsWith('@newsletter');
  bool get isStatusJid => jid == 'status@broadcast';
}

/// حالة (Status) — GET /api/statuses
class StatusItem {
  final String id,
      sender,
      senderName,
      type,
      body,
      mediaPath,
      mediaMime,
      mediaState;
  final int timestamp;

  const StatusItem({
    required this.id,
    this.sender = '',
    this.senderName = '',
    this.type = 'text',
    this.body = '',
    this.mediaPath = '',
    this.mediaMime = '',
    this.mediaState = 'none',
    this.timestamp = 0,
  });

  factory StatusItem.fromJson(Map<String, dynamic> j) => StatusItem(
        id: (j['id'] ?? '').toString(),
        sender: (j['sender'] ?? '').toString(),
        senderName: (j['sender_name'] ?? '').toString(),
        type: (j['type'] ?? 'text').toString(),
        body: (j['body'] ?? '').toString(),
        mediaPath: (j['media_path'] ?? '').toString(),
        mediaMime: (j['media_mime'] ?? '').toString(),
        mediaState: (j['media_state'] ?? 'none').toString(),
        timestamp: int.tryParse('${j['timestamp'] ?? 0}') ?? 0,
      );
}

/// قناة (Newsletter) — GET /api/newsletters
class Channel {
  final String jid, name, description, role, picture;
  final int subscribers;

  const Channel({
    required this.jid,
    this.name = '',
    this.description = '',
    this.role = '',
    this.picture = '',
    this.subscribers = 0,
  });

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        jid: (j['jid'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        role: (j['role'] ?? '').toString(),
        picture: (j['picture'] ?? '').toString(),
        subscribers: int.tryParse('${j['subscribers'] ?? 0}') ?? 0,
      );
}

/// معلومات مجموعة — GET /api/groups/{jid}/info
class GroupInfo {
  final String jid, name, topic;
  final List<GroupMember> participants;

  const GroupInfo(
      {required this.jid,
      this.name = '',
      this.topic = '',
      this.participants = const []});

  factory GroupInfo.fromJson(Map<String, dynamic> j) => GroupInfo(
        jid: (j['jid'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        topic: (j['topic'] ?? '').toString(),
        participants: ((j['participants'] ?? const []) as List)
            .whereType<Map>()
            .map((m) => GroupMember.fromJson(m.cast<String, dynamic>()))
            .toList(),
      );

  int get size => participants.length;
}

class GroupMember {
  final String jid;
  final bool isAdmin, isSuperAdmin;
  const GroupMember(
      {required this.jid, this.isAdmin = false, this.isSuperAdmin = false});

  factory GroupMember.fromJson(Map<String, dynamic> j) => GroupMember(
        jid: (j['jid'] ?? '').toString(),
        isAdmin: j['is_admin'] == true,
        isSuperAdmin: j['is_super_admin'] == true,
      );
}

/// معلومات اتصال — GET /api/contact/{jid}/info
class ContactInfo {
  final String jid, about, verifiedName;
  final bool? onWhatsapp;
  const ContactInfo(
      {required this.jid,
      this.about = '',
      this.verifiedName = '',
      this.onWhatsapp});

  factory ContactInfo.fromJson(Map<String, dynamic> j) => ContactInfo(
        jid: (j['jid'] ?? '').toString(),
        about: (j['about'] ?? '').toString(),
        verifiedName: (j['verified_name'] ?? '').toString(),
        onWhatsapp: j['on_whatsapp'] is bool ? j['on_whatsapp'] as bool : null,
      );
}
