// شاشة المحادثة — فقاعات، رد باقتباس، تفاعلات، مؤشر كتابة، تسجيل صوتي، مرفقات، استطلاعات
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';
import 'contact_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final String jid;
  final String title;
  const ChatScreen({super.key, required this.jid, required this.title});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  Message? _replyTo;
  bool _emojiOpen = false;
  bool _recording = false;
  Duration _recDuration = Duration.zero;
  Timer? _recTimer;
  final _recorder = AudioRecorder();
  String _recPath = '';
  bool _sending = false;
  Timer? _pauseTimer;

  late S s;

  @override
  void initState() {
    super.initState();
    s = context.read<S>();
    final st = context.read<AppState>();
    st.loadMessages(widget.jid);
    st.markRead(widget.jid);
    st.sendOpenChat(widget.jid);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _recTimer?.cancel();
    _pauseTimer?.cancel();
    _stopRecording(cancel: true, silent: true);
    _recorder.dispose();
    context.read<AppState>().sendOpenChat('');
    super.dispose();
  }

  // ============================================================ الإرسال

  void _bumpPresence(bool composing, {bool audio = false}) {
    final st = context.read<AppState>();
    st.sendPresence(widget.jid, composing, audio: audio);
    _pauseTimer?.cancel();
    if (composing) {
      _pauseTimer = Timer(
          const Duration(seconds: 4), () => st.sendPresence(widget.jid, false));
    }
  }

  Future<void> _sendText() async {
    final body = _inputCtrl.text.trim();
    if (body.isEmpty) return;
    final st = context.read<AppState>();
    setState(() => _sending = true);
    try {
      final m = await st.sendMessage(widget.jid,
          type: 'text', body: body, replyTo: _replyTo?.id ?? '');
      _inputCtrl.clear();
      _clearReply();
      _bumpPresence(false);
      _scrollToBottom();
      _refreshReceipt(m);
    } catch (e) {
      _toast('${s.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendMedia(
      {required String type,
      required Uint8List bytes,
      String? fileName,
      String? mime,
      String? caption}) async {
    final st = context.read<AppState>();
    setState(() => _sending = true);
    try {
      await st.sendMessage(widget.jid,
          type: type,
          body: caption ?? '',
          replyTo: _replyTo?.id ?? '',
          bytes: bytes,
          fileName: fileName,
          mime: mime);
      _clearReply();
      _scrollToBottom();
    } catch (e) {
      _toast('${s.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendPoll(String question, List<String> options) async {
    final st = context.read<AppState>();
    try {
      await st.sendMessage(widget.jid,
          type: 'poll',
          body: question,
          replyTo: _replyTo?.id ?? '',
          options: options.toString());
      _clearReply();
      _scrollToBottom();
    } catch (e) {
      _toast('${s.t('error')}: $e');
    }
  }

  Future<void> _refreshReceipt(Message m) async {
    // تحديث حالة التسليم بعد ثوانٍ — يعتمد على أحداث لاحقة إن وجدت
    final st = context.read<AppState>();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      await st.loadMessages(widget.jid, force: true);
    }
  }

  // ============================================================ التسجيل الصوتي

  Future<void> _startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        final path = '${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc),
            path: path);
        _recPath = path;
        setState(() {
          _recording = true;
          _recDuration = Duration.zero;
        });
        _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          setState(() => _recDuration += const Duration(seconds: 1));
        });
      }
    } catch (_) {}
  }

  Future<void> _stopRecording(
      {bool cancel = false, bool silent = false}) async {
    _recTimer?.cancel();
    if (!_recording && !silent) return;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (!silent) {
      setState(() => _recording = false);
      if (!cancel && path != null) {
        try {
          final f = XFile(path);
          final bytes = await f.readAsBytes();
          await _sendMedia(
              type: 'audio',
              bytes: bytes,
              fileName: 'voice.ogg',
              mime: 'audio/ogg');
        } catch (_) {}
      }
    }
    setState(() {
      _recording = false;
    });
  }

  // ============================================================ المرفقات

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final x =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 88);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _sendMedia(
        type: 'image', bytes: bytes, fileName: x.name, mime: 'image/jpeg');
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final x =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 88);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _sendMedia(
        type: 'image', bytes: bytes, fileName: x.name, mime: 'image/jpeg');
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final x = await picker.pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    await _sendMedia(
        type: 'video', bytes: bytes, fileName: x.name, mime: 'video/mp4');
  }

  Future<void> _pickDocument() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    if (f.bytes == null) return;
    await _sendMedia(
        type: 'document',
        bytes: f.bytes!,
        fileName: f.name,
        mime: f.extension == 'pdf'
            ? 'application/pdf'
            : 'application/octet-stream');
  }

  Future<void> _openPollDialog() async {
    final qCtrl = TextEditingController();
    final optCtrls = <TextEditingController>[
      TextEditingController(),
      TextEditingController()
    ];
    final s = this.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => Directionality(
          textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            title: Text(s.t('createPoll')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: qCtrl,
                    decoration: InputDecoration(hintText: s.t('pollQuestion'))),
                const SizedBox(height: 12),
                ...List.generate(
                    optCtrls.length,
                    (i) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                              controller: optCtrls[i],
                              decoration: InputDecoration(
                                  hintText: '${s.t('pollOptions')} ${i + 1}')),
                        )),
                TextButton.icon(
                  onPressed: () =>
                      setD(() => optCtrls.add(TextEditingController())),
                  icon: const Icon(Icons.add, size: 18, color: WaColors.green),
                  label: Text(s.t('addOption'),
                      style: const TextStyle(color: WaColors.green)),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(s.t('cancel'))),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: WaColors.green),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.t('createPoll')),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      final opts = optCtrls
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();
      if (qCtrl.text.trim().isNotEmpty && opts.length >= 2) {
        await _sendPoll(qCtrl.text.trim(), opts);
      }
    }
  }

  void _openAttachmentSheet() {
    final c = WaColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Directionality(
        textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _attachItem(c, Icons.insert_drive_file_rounded,
                    const Color(0xFF7F66FF), s.t('document'), _pickDocument),
                _attachItem(c, Icons.photo_camera_rounded,
                    const Color(0xFFFF2E74), s.t('camera'), _pickFromCamera),
                _attachItem(c, Icons.photo_rounded, const Color(0xFF25D366),
                    s.t('gallery'), _pickFromGallery),
                _attachItem(c, Icons.videocam_rounded, const Color(0xFF00A884),
                    s.t('video'), _pickVideo),
                _attachItem(c, Icons.poll_rounded, const Color(0xFFFFB02E),
                    s.t('poll'), _openPollDialog),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachItem(WaColors c, IconData icon, Color color, String label,
      VoidCallback onTap) {
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        Future.delayed(const Duration(milliseconds: 250), onTap);
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(18)),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 7),
          Text(label, style: TextStyle(color: c.muted, fontSize: 11.5)),
        ]),
      ),
    );
  }

  // ============================================================ التفاعل والرد

  void _showBubbleActions(Message m, Offset position) {
    final c = WaColors.of(context);
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
    final st = context.read<AppState>();
    final rtl = s.isRtl;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy - 130, position.dx + 220, 0),
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: emojis.map((e) {
                final mine = m.reactions[e] != null;
                return GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await st.api.react(m.chat, m.id, mine ? '' : e);
                      await st.loadMessages(m.chat, force: true);
                    } catch (_) {}
                  },
                  child: Text(e,
                      style: TextStyle(
                          fontSize: mine ? 26 : 22,
                          decoration: mine
                              ? TextDecoration.underline
                              : TextDecoration.none)),
                );
              }).toList()),
        ),
        _menuItem(s.t('reply'), Icons.reply_rounded,
            () => setState(() => _replyTo = m)),
        _menuItem(s.t('copy'), Icons.copy_rounded, () async {
          await Clipboard.setData(ClipboardData(text: m.body));
          if (context.mounted) _toast(s.t('copy'));
        }),
        _menuItem(s.t('info'), Icons.info_outline_rounded, () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ContactInfoScreen(
                jid: m.fromMe ? widget.jid : m.sender,
                name: m.senderName.isEmpty ? widget.title : m.senderName),
          ));
        }),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(
      String label, IconData icon, VoidCallback onTap) {
    final c = WaColors.of(context);
    return PopupMenuItem<String>(
      onTap: onTap,
      child: Row(children: [
        Icon(icon, size: 20, color: c.muted),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: c.text, fontSize: 14.5)),
      ]),
    );
  }

  void _clearReply() => setState(() => _replyTo = null);

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ============================================================ البناء

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = WaColors.of(context);
    final rtl = s.isRtl;
    final msgs = st.messagesOf(widget.jid);
    final typing = st.typing[widget.jid];

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.chatBg,
        appBar: _buildAppBar(c, st, typing),
        body: Column(
          children: [
            Expanded(
              child: msgs.isEmpty
                  ? Stack(children: [
                      Center(
                          child: Text(s.t('noMessages'),
                              style: TextStyle(color: c.muted, fontSize: 13))),
                      if (_sending)
                        const Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4)),
                          ),
                        ),
                    ])
                  : _buildMessages(c, st, msgs, typing),
            ),
            _buildInput(c, st),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------ الترويسة
  PreferredSizeWidget _buildAppBar(WaColors c, AppState st, String? typing) {
    final isGroup = widget.jid.endsWith('@g.us');
    return AppBar(
      backgroundColor: c.appbar,
      titleSpacing: 4,
      title: InkWell(
        onTap: () =>
            Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => ContactInfoScreen(
              jid: widget.jid, name: widget.title, isGroup: isGroup),
        )),
        child: Row(children: [
          WaAvatar(
              jid: widget.jid, name: widget.title, size: 38, isGroup: isGroup),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600)),
                Text(
                  typing != null
                      ? (typing == 'recording'
                          ? s.t('recording')
                          : s.t('typing'))
                      : (isGroup ? '${s.t('groupInfo')}' : s.t('online')),
                  maxLines: 1,
                  style: TextStyle(
                    color: typing != null ? WaColors.green : c.muted,
                    fontSize: 12.5,
                    fontStyle:
                        typing != null ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
      actions: [
        IconButton(
            icon: Icon(Icons.videocam_rounded, color: c.muted),
            onPressed: () => _toast(s.t('noCalls'))),
        IconButton(
            icon: Icon(Icons.call_outlined, color: c.muted),
            onPressed: () => _toast(s.t('noCalls'))),
        PopupMenuButton<String>(
          color: c.surface,
          iconColor: c.muted,
          onSelected: (v) {
            if (v == 'info') {
              Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
                builder: (_) => ContactInfoScreen(
                    jid: widget.jid, name: widget.title, isGroup: isGroup),
              ));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'info', child: Text(s.t('info'))),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------ قائمة الرسائل
  Widget _buildMessages(
      WaColors c, AppState st, List<Message> msgs, String? typing) {
    final isGroup = widget.jid.endsWith('@g.us');
    final meJid = st.session.myJid;
    return ListView.builder(
      controller: _scrollCtrl,
      reverse: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      itemCount: msgs.length + (typing != null ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i >= msgs.length) return const TypingBubble();
        final m = msgs[i];
        // وسم اليوم بين الرسائل
        final showDay = i == 0 ||
            WaTime.dayLabel(msgs[i - 1].timestamp, s.isRtl) !=
                WaTime.dayLabel(m.timestamp, s.isRtl);
        Widget bubble = MessageBubble(
          m: m,
          isGroup: isGroup,
          meJid: meJid,
          onLongPress: (offset) => _showBubbleActions(m, offset),
          onTap: () {},
        );
        return Column(
          children: [
            if (showDay) _DayChip(label: WaTime.dayLabel(m.timestamp, s.isRtl)),
            bubble,
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------ شريط الإدخال
  Widget _buildInput(WaColors c, AppState st) {
    final hasText = _inputCtrl.text.trim().isNotEmpty;

    // واجهة التسجيل الجارية
    if (_recording) {
      return Container(
        color: c.appbar,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: Colors.redAccent, size: 26),
                onPressed: () => _stopRecording(cancel: true),
              ),
              const SizedBox(width: 4),
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                    color: WaColors.recording, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(_fmtDuration(_recDuration),
                  style: const TextStyle(
                      color: WaColors.recording,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(s.t('recordingNow'),
                  style: TextStyle(color: c.muted, fontSize: 13)),
              const SizedBox(width: 14),
              CircleAvatar(
                radius: 22,
                backgroundColor: WaColors.green,
                child: IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 22),
                  onPressed: () => _stopRecording(),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      );
    }

    return Container(
      color: c.appbar,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // معاينة الرد
            if (_replyTo != null)
              _ReplyPreview(c: c, m: _replyTo!, onClose: _clearReply),

            // صف الإدخال
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(
                children: [
                  // أيقونة الإيموجي
                  IconButton(
                    icon: Icon(
                        _emojiOpen
                            ? Icons.keyboard_rounded
                            : Icons.emoji_emotions_outlined,
                        color: c.muted,
                        size: 26),
                    onPressed: () => setState(() => _emojiOpen = !_emojiOpen),
                  ),
                  // حقل النص
                  Expanded(
                    child: TextField(
                      controller: _inputCtrl,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      onChanged: (v) {
                        setState(() {});
                        _bumpPresence(v.trim().isNotEmpty);
                      },
                      style:
                          TextStyle(color: c.text, fontSize: 15.5, height: 1.3),
                      decoration: InputDecoration(
                        hintText: s.t('message'),
                        filled: true,
                        fillColor: c.input,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  // المرفقات
                  IconButton(
                    icon: Icon(Icons.attach_file_rounded,
                        color: c.muted, size: 25),
                    onPressed: _openAttachmentSheet,
                  ),
                  // الكاميرا أو الإرسال/الميكروفون
                  if (hasText)
                    GestureDetector(
                      onTap: _sending ? null : _sendText,
                      child: Container(
                        margin: const EdgeInsetsDirectional.only(end: 4),
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                            color: WaColors.green, shape: BoxShape.circle),
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(11),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4, color: Colors.white))
                            : const Icon(Icons.send_rounded,
                                color: Colors.white, size: 21),
                      ),
                    )
                  else ...[
                    IconButton(
                      icon: Icon(Icons.photo_camera_outlined,
                          color: c.muted, size: 25),
                      onPressed: _pickFromCamera,
                    ),
                    GestureDetector(
                      onLongPressStart: (_) => _startRecording(),
                      onLongPressEnd: (_) => _stopRecording(),
                      child: Container(
                        margin: const EdgeInsetsDirectional.only(end: 6),
                        width: 42,
                        height: 42,
                        decoration: const BoxDecoration(
                            color: WaColors.green, shape: BoxShape.circle),
                        child: const Icon(Icons.mic_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // لوحة الإيموجي
            if (_emojiOpen)
              EmojiPanel(onPick: (e) {
                _inputCtrl.text += e;
                setState(() {});
              }),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

// ==================================================================== عناصر الرسائل

class _DayChip extends StatelessWidget {
  final String label;
  const _DayChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
            color: c.search,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 3,
                  offset: const Offset(0, 1))
            ]),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                color: c.muted, fontSize: 11.5, fontWeight: FontWeight.w500)),
      ),
    );
  }
}

/// فقاعة الرسالة الكاملة — نص/وسائط/استطلاع + اقتباس + تفاعلات + علامات
class MessageBubble extends StatelessWidget {
  final Message m;
  final bool isGroup;
  final String meJid;
  final void Function(Offset offset) onLongPress;
  final VoidCallback onTap;

  const MessageBubble({
    super.key,
    required this.m,
    required this.isGroup,
    required this.meJid,
    required this.onLongPress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final st = context.read<AppState>();
    final isOut = m.fromMe;
    final bg = isOut ? c.bubbleOut : c.bubbleIn;
    final time = WaTime.hhMm(m.timestamp);

    Widget content = _buildContent(context, c, st);

    final bubble = Container(
      margin: EdgeInsets.only(
        top: 2.5,
        bottom: m.reactions.isNotEmpty ? 6 : 2.5,
        left: isOut ? 64 : 6,
        right: isOut ? 6 : 64,
      ),
      child: GestureDetector(
        onLongPressStart: (d) => onLongPress(d.globalPosition),
        onTap: onTap,
        child: Column(
          crossAxisAlignment:
              isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isOut ? 9 : 3),
                  topRight: Radius.circular(isOut ? 3 : 9),
                  bottomLeft: const Radius.circular(9),
                  bottomRight: const Radius.circular(9),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // اسم المرسل في المجموعات
                  if (isGroup && !isOut && m.senderName.isNotEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.only(bottom: 2, left: 4, right: 4),
                      child: Text(m.senderName,
                          style: TextStyle(
                              color: _senderColor(m.sender),
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  // الاقتباس
                  if (m.quoted != null)
                    _QuotedPreview(c: c, q: m.quoted!, isOut: isOut),
                  // المحتوى
                  content,
                  // الوقت والعلامات
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(time,
                          style: TextStyle(
                              color: isOut
                                  ? Colors.grey.shade700.withValues(alpha: 0.75)
                                  : c.muted,
                              fontSize: 10.5)),
                      if (isOut) ...[
                        const SizedBox(width: 3),
                        WaTicks(receipt: m.receipt, size: 13),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // التفاعلات أسفل الفقاعة
            if (m.reactions.isNotEmpty)
              Padding(
                padding: EdgeInsetsDirectional.only(
                    start: isOut ? 0 : 8, end: isOut ? 8 : 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.search,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.divider),
                  ),
                  child: Text(m.reactions.keys.join(' '),
                      style: const TextStyle(fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
    return bubble;
  }

  Color _senderColor(String jid) {
    const palette = [
      Color(0xFFE542A3),
      Color(0xFF20B2AA),
      Color(0xFFF4A460),
      Color(0xFF7B68EE),
      Color(0xFFE9967A),
      Color(0xFF48D1CC)
    ];
    var h = 0;
    for (final cp in jid.runes) {
      h = (h * 31 + cp) & 0x7FFFFFFF;
    }
    return palette[h % palette.length];
  }

  // ------------------------------------------------------------ المحتوى حسب النوع
  Widget _buildContent(BuildContext context, WaColors c, AppState st) {
    switch (m.type) {
      case 'image':
        return _ImageContent(m: m, isOut: m.fromMe, caption: m.body);
      case 'video':
        return _VideoContent(m: m, isOut: m.fromMe, caption: m.body);
      case 'audio':
        return _AudioContent(m: m, isOut: m.fromMe);
      case 'sticker':
        return _StickerContent(m: m);
      case 'document':
        return _DocumentContent(c: c, m: m);
      case 'poll':
        return _PollContent(c: c, m: m);
      default:
        return SelectionContainer.disabled(
          child: Text(m.body.isEmpty ? '…' : m.body,
              style: TextStyle(color: c.text, fontSize: 15, height: 1.32)),
        );
    }
  }
}

/// الاقتباس داخل الفقاعة
class _QuotedPreview extends StatelessWidget {
  final WaColors c;
  final QuotedData q;
  final bool isOut;
  const _QuotedPreview({required this.c, required this.q, required this.isOut});

  @override
  Widget build(BuildContext context) {
    final accent = q.fromMe ? WaColors.greenDeep : WaColors.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        border: BorderDirectional(start: BorderSide(color: accent, width: 3.5)),
        color: Colors.black.withValues(alpha: isOut ? 0.06 : 0.05),
        borderRadius: BorderRadius.circular(5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            q.fromMe
                ? context.read<S>().t('you')
                : (q.sender.isEmpty ? '' : q.sender.split('@').first),
            style: TextStyle(
                color: accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
        Text(q.body.isEmpty ? '…' : q.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.muted, fontSize: 13)),
      ]),
    );
  }
}

/// محتوى صورة — تحميل من الخادم
class _ImageContent extends StatelessWidget {
  final Message m;
  final bool isOut;
  final String caption;
  const _ImageContent(
      {required this.m, required this.isOut, required this.caption});

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final url = m.media.ready ? st.api.mediaUrl(m.media.path) : '';
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: url.isEmpty
          ? Container(
              width: 190,
              height: 150,
              color: Colors.black.withValues(alpha: 0.15),
              child: Center(
                  child:
                      Text('…', style: TextStyle(color: Colors.grey.shade600))),
            )
          : Image.network(
              url,
              width: 210,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 190,
                height: 130,
                color: Colors.black12,
                child: const Icon(Icons.broken_image_outlined, size: 34),
              ),
              loadingBuilder: (ctx, child, prog) => prog == null
                  ? child
                  : Container(
                      width: 190,
                      height: 130,
                      color: Colors.black12,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2))),
            ),
    );
  }
}

/// ملصق — عرض بحجم صغير بلا خلفية
class _StickerContent extends StatelessWidget {
  final Message m;
  const _StickerContent({required this.m});

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final url = m.media.ready ? st.api.mediaUrl(m.media.path) : '';
    return SizedBox(
      width: 140,
      height: 140,
      child: url.isEmpty
          ? const Center(child: Icon(Icons.sticky_note_2_outlined, size: 30))
          : Image.network(url, fit: BoxFit.contain),
    );
  }
}

/// فيديو — مشغل مدمج
class _VideoContent extends StatefulWidget {
  final Message m;
  final bool isOut;
  final String caption;
  const _VideoContent(
      {required this.m, required this.isOut, required this.caption});

  @override
  State<_VideoContent> createState() => _VideoContentState();
}

class _VideoContentState extends State<_VideoContent> {
  VideoPlayerController? _ctl;
  bool _failed = false;

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  void _init(String url) {
    _ctl = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      });
  }

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final url =
        widget.m.media.ready ? st.api.mediaUrl(widget.m.media.path) : '';
    final ready = _ctl != null && _ctl!.value.isInitialized;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (url.isEmpty || _failed)
        Container(
          width: 200,
          height: 140,
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6)),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_outlined,
                    color: Colors.white54, size: 32),
                const SizedBox(height: 6),
                Text(widget.m.media.name,
                    style:
                        const TextStyle(color: Colors.white54, fontSize: 11)),
              ]),
        )
      else if (!ready)
        Container(
          width: 200,
          height: 140,
          color: Colors.black.withValues(alpha: 0.2),
          child: const Center(
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white70)),
        )
      else
        GestureDetector(
          onTap: () => setState(() {
            _ctl!.value.isPlaying ? _ctl!.pause() : _ctl!.play();
          }),
          child: Stack(alignment: Alignment.center, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AspectRatio(
                aspectRatio: _ctl!.value.aspectRatio,
                child: VideoPlayer(_ctl!),
              ),
            ),
            if (!_ctl!.value.isPlaying)
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 30),
              ),
          ]),
        ),
      if (url.isNotEmpty && !_failed)
        Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.download_rounded,
                size: 20, color: Colors.white70),
            onPressed: () => _init(url),
          ),
        ),
      if (widget.caption.isNotEmpty)
        Text(widget.caption,
            style: TextStyle(
                color: widget.isOut ? Colors.white : Colors.white,
                fontSize: 14.5,
                height: 1.3)),
    ]);
  }
}

/// رسالة صوتية — مشغل مع شريط تقدم
class _AudioContent extends StatefulWidget {
  final Message m;
  final bool isOut;
  const _AudioContent({required this.m, required this.isOut});

  @override
  State<_AudioContent> createState() => _AudioContentState();
}

class _AudioContentState extends State<_AudioContent> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  bool _ready = false;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    final st = context.read<AppState>();
    final url =
        widget.m.media.ready ? st.api.mediaUrl(widget.m.media.path) : '';
    if (url.isEmpty) return;
    try {
      await _player.setUrl(url);
      _dur = _player.duration ?? Duration(seconds: widget.m.media.duration);
      if (mounted) setState(() => _ready = true);
      _player.positionStream.listen((p) {
        if (mounted) setState(() => _pos = p);
      });
      _player.playerStateStream.listen((s) {
        if (mounted) setState(() => _playing = s.playing);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final seconds = _dur.inSeconds;
    final progress = seconds > 0 ? _pos.inSeconds / seconds : 0.0;
    return SizedBox(
      width: 210,
      child: Row(children: [
        GestureDetector(
          onTap: () {
            if (_ready) _playing ? _player.pause() : _player.play();
          },
          child: Icon(
              _playing
                  ? Icons.pause_circle_filled_rounded
                  : Icons.play_circle_fill_rounded,
              color: Colors.white,
              size: 34),
        ),
        const SizedBox(width: 6),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // موجة صوتية مبسطة
            SizedBox(
              height: 22,
              child: Row(
                children: List.generate(24, (i) {
                  final active = progress * 24 > i;
                  final h = 5.0 + ((i * 7) % 14);
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    width: 3,
                    height: h,
                    decoration: BoxDecoration(
                      color: active
                          ? (widget.isOut ? Colors.white : WaColors.green)
                          : (widget.isOut
                              ? Colors.white30
                              : Colors.grey.shade500),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              ),
            ),
            Text(_fmt(_playing || _pos > Duration.zero ? _pos : _dur),
                style: TextStyle(
                    color: widget.isOut ? Colors.white70 : c.muted,
                    fontSize: 10.5)),
          ]),
        ),
        const SizedBox(width: 4),
        Icon(widget.isOut ? Icons.mic_rounded : Icons.person_rounded,
            size: 16, color: widget.isOut ? Colors.white70 : c.muted),
      ]),
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}

/// مستند
class _DocumentContent extends StatelessWidget {
  final WaColors c;
  final Message m;
  const _DocumentContent({required this.c, required this.m});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(children: [
        const Icon(Icons.description_rounded,
            color: Color(0xFF7F66FF), size: 30),
        const SizedBox(width: 9),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.media.name.isEmpty ? 'document' : m.media.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(_size(m.media.size),
                style: TextStyle(color: c.muted, fontSize: 11)),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.download_rounded, size: 20, color: c.muted),
          onPressed: () {},
        ),
      ]),
    );
  }

  String _size(int b) {
    if (b <= 0) return '';
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// استطلاع رأي
class _PollContent extends StatelessWidget {
  final WaColors c;
  final Message m;
  const _PollContent({required this.c, required this.m});

  @override
  Widget build(BuildContext context) {
    final poll = m.poll!;
    return Container(
      constraints: const BoxConstraints(maxWidth: 250),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(poll.name,
            style: TextStyle(
                color: c.text, fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ...poll.options.map((o) => Container(
              margin: const EdgeInsets.only(bottom: 7),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.black.withValues(alpha: 0.12)),
              ),
              child: Row(children: [
                Icon(Icons.radio_button_unchecked_rounded,
                    size: 17, color: c.muted),
                const SizedBox(width: 9),
                Expanded(
                    child: Text(o,
                        style: TextStyle(color: c.text, fontSize: 13.5))),
              ]),
            )),
        Text('${s.t('pollVotes')}: 0',
            style: TextStyle(color: c.muted, fontSize: 11)),
      ]),
    );
  }
}

/// فقاعة الكتابة المتحركة
class TypingBubble extends StatefulWidget {
  const TypingBubble({super.key});

  @override
  State<TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<TypingBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.bubbleIn,
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 2)
          ],
        ),
        child: AnimatedBuilder(
          animation: _ctl,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final v = ((_ctl.value * 3) - i).clamp(0.0, 1.0);
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.muted.withValues(alpha: 0.35 + 0.55 * (1 - v).abs()),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// معاينة الرد فوق حقل الإدخال
class _ReplyPreview extends StatelessWidget {
  final WaColors c;
  final Message m;
  final VoidCallback onClose;
  const _ReplyPreview(
      {required this.c, required this.m, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final isOut = m.fromMe;
    final accent = isOut ? WaColors.greenDeep : WaColors.green;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      padding: const EdgeInsetsDirectional.only(start: 10),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: BorderDirectional(start: BorderSide(color: accent, width: 4)),
      ),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.fromMe ? context.read<S>().t('you') : m.senderName,
                style: TextStyle(
                    color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(m.body.isEmpty ? (m.isMedia ? '…' : '') : m.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.muted, fontSize: 13)),
          ]),
        ),
        IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: c.muted),
            onPressed: onClose),
      ]),
    );
  }
}

/// لوحة إيموجي مبسطة بفئات
class EmojiPanel extends StatelessWidget {
  final ValueChanged<String> onPick;
  const EmojiPanel({super.key, required this.onPick});

  static const _faces = [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '🤣',
    '😂',
    '🙂',
    '🙃',
    '😉',
    '😊',
    '😇',
    '🥰',
    '😍',
    '🤩',
    '😘',
    '😗',
    '😚',
    '😙',
    '🥲',
    '😋',
    '😛',
    '😜',
    '🤪',
    '😝',
    '🤗',
    '🤭',
    '🤫',
    '🤔',
    '🤐',
    '😐',
    '😑',
    '😶',
    '😏',
    '😒',
    '🙄',
    '😬',
    '😔',
    '😪',
    '🤤',
    '😴',
    '😷',
    '🤒',
    '🤕',
    '🤢',
    '🥵',
    '🥶',
    '😵',
    '🤯',
    '🤠',
    '🥳',
    '😎',
    '🤓',
    '🧐',
    '😕',
    '😟',
    '🙁',
    '😮',
    '😯',
    '😲',
    '😳',
    '🥺',
    '😦',
    '😧',
    '😨',
    '😰',
    '😥',
    '😢',
    '😭',
    '😱',
    '😖',
    '😣',
    '😞',
    '😓',
    '😩',
    '😫',
    '🥱',
    '😤',
    '😡',
    '😠',
    '🤬',
    '😈',
    '👿',
    '💀',
    '🤡',
    '👻',
    '👽',
    '🤖'
  ];
  static const _gestures = [
    '👍',
    '👎',
    '👌',
    '🤌',
    '🤏',
    '✌️',
    '🤞',
    '🤟',
    '🤘',
    '🤙',
    '👈',
    '👉',
    '👆',
    '👇',
    '☝️',
    '✋',
    '🤚',
    '🖐',
    '🖖',
    '👋',
    '🤝',
    '🙏',
    '💪',
    '🦾',
    '✍️',
    '💅',
    '👏',
    '🙌',
    '👐',
    '🤲',
    '🫶',
    '🤛',
    '🤜',
    '✊',
    '👊',
    '🫵',
    '🫱',
    '🫲'
  ];
  static const _hearts = [
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🖤',
    '🤍',
    '🤎',
    '💔',
    '❣️',
    '💕',
    '💞',
    '💓',
    '💗',
    '💖',
    '💘',
    '💝',
    '💟',
    '✨',
    '⭐',
    '🌟',
    '💫',
    '🔥',
    '💥',
    '💯',
    '🎉',
    '🎊',
    '🎈',
    '🎁',
    '🏆',
    '🥇',
    '⚡',
    '🌈',
    '☀️',
    '🌙'
  ];
  static const _others = [
    '🐶',
    '🐱',
    '🐭',
    '🐹',
    '🐰',
    '🦊',
    '🐻',
    '🐼',
    '🐨',
    '🐯',
    '🦁',
    '🐮',
    '🐷',
    '🐸',
    '🐵',
    '🙈',
    '🙉',
    '🙊',
    '🐔',
    '🐧',
    '🐦',
    '🦆',
    '🦅',
    '🦉',
    '🐴',
    '🦄',
    '🐝',
    '🦋',
    '🐞',
    '🐢',
    '🐍',
    '🐙',
    '🦑',
    '🦐',
    '🐠',
    '🐬',
    '🐳',
    '🌸',
    '🌺',
    '🌻',
    '🌹',
    '🌷',
    '🌴',
    '🌵',
    '🍀',
    '🌍',
    '🎉',
    '🍕',
    '🍔',
    '🍟',
    '⚽',
    '🏀',
    '🎮',
    '🎵',
    '📱',
    '💻',
    '✈️',
    '🚗',
    '🕌',
    '🌙',
    '🕌',
    '📖'
  ];

  @override
  Widget build(BuildContext context) {
    final groups = {
      '😊': _faces,
      '👍': _gestures,
      '❤️': _hearts,
      '🌵': _others
    };
    return Container(
      height: 220,
      color: WaColors.of(context).appbar,
      child: DefaultTabController(
        length: groups.length,
        child: Column(children: [
          TabBar(
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            indicatorColor: WaColors.green,
            labelColor: WaColors.green,
            unselectedLabelColor: Colors.grey.shade500,
            tabs: groups.keys
                .map((k) =>
                    Tab(child: Text(k, style: const TextStyle(fontSize: 20))))
                .toList(),
          ),
          Expanded(
            child: TabBarView(
              children: groups.values
                  .map((list) => GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 8,
                                mainAxisSpacing: 4,
                                crossAxisSpacing: 4),
                        itemCount: list.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => onPick(list[i]),
                          child: Center(
                              child: Text(list[i],
                                  style: const TextStyle(fontSize: 25))),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ]),
      ),
    );
  }
}
