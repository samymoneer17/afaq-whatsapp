// تبويب التحديثات — الحالات ثم القنوات (مثل واتساب الحديث)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';
import 'channel_screen.dart';

class UpdatesTab extends StatefulWidget {
  const UpdatesTab({super.key});

  @override
  State<UpdatesTab> createState() => _UpdatesTabState();
}

class _UpdatesTabState extends State<UpdatesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      st.refreshStatuses();
      st.refreshChannels();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final st = context.watch<AppState>();
    final c = WaColors.of(context);
    final s = context.watch<S>();
    final rtl = s.isRtl;

    // تجميع الحالات حسب المرسل
    final bySender = <String, List<StatusItem>>{};
    for (final st2 in st.statuses) {
      bySender.putIfAbsent(st2.sender, () => []).add(st2);
    }
    final senders = bySender.entries.toList()
      ..sort(
          (a, b) => b.value.first.timestamp.compareTo(a.value.first.timestamp));

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          // ================================================== الحالات
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Text(s.t('status'),
                style: TextStyle(
                    color: WaColors.green,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
          ),
          // حالتي
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Stack(
              children: [
                WaAvatar(
                    jid: st.session.myJid, name: st.session.myName, size: 48),
                PositionedDirectional(
                  end: 0,
                  bottom: 0,
                  child: Container(
                    width: 19,
                    height: 19,
                    decoration: BoxDecoration(
                        color: WaColors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.appbar, width: 2)),
                    child: const Icon(Icons.add, color: Colors.white, size: 12),
                  ),
                ),
              ],
            ),
            title: Text(s.t('myStatus'),
                style: TextStyle(
                    color: c.text, fontSize: 16, fontWeight: FontWeight.w600)),
            subtitle: Text(s.t('statusHint'),
                style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          // حالات الآخرين
          ...senders.map((e) {
            final first = e.value.first;
            final time = WaTime.listTime(first.timestamp, s.isRtl);
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: Stack(children: [
                WaAvatar(
                  jid: first.sender,
                  name: first.senderName.isEmpty
                      ? first.sender.split('@').first
                      : first.senderName,
                  size: 48,
                  onTap: () => _openStatusViewer(context, e.value),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: WaColors.green, width: 2.2),
                      ),
                    ),
                  ),
                ),
              ]),
              title: Text(
                  first.senderName.isEmpty
                      ? first.sender.split('@').first
                      : first.senderName,
                  style: TextStyle(
                      color: c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              subtitle:
                  Text(time, style: TextStyle(color: c.muted, fontSize: 13)),
              onTap: () => _openStatusViewer(context, e.value),
            );
          }),
          if (senders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                  child: Text('لا توجد حالات جديدة',
                      style: TextStyle(color: c.muted, fontSize: 13))),
            ),

          // ================================================== القنوات
          const Divider(indent: 16, endIndent: 16),
          Row(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
              child: Text(s.t('channels'),
                  style: TextStyle(
                      color: WaColors.green,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openJoinChannel(context),
              icon: const Icon(Icons.add_circle_outline_rounded,
                  size: 18, color: WaColors.green),
              label: Text(s.t('findChannels'),
                  style:
                      const TextStyle(color: WaColors.green, fontSize: 12.5)),
            ),
          ]),
          ...st.channels.map((ch) => ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                leading: WaAvatar(
                    jid: ch.jid, name: ch.name, picture: ch.picture, size: 48),
                title: Text(ch.name,
                    style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                subtitle: Text('${ch.subscribers} ${s.t('subscribers')}',
                    style: TextStyle(color: c.muted, fontSize: 13)),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                        builder: (_) => ChannelScreen(channel: ch))),
              )),
          if (st.channels.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: Text('لا توجد قنوات بعد',
                      style: TextStyle(color: c.muted, fontSize: 13))),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------- عارض الحالات
  void _openStatusViewer(BuildContext context, List<StatusItem> items) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => StatusViewer(items: items),
    ));
  }

  void _openJoinChannel(BuildContext context) {
    final c = WaColors.of(context);
    final s = context.read<S>();
    final st = context.read<AppState>();
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Directionality(
        textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 18, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.t('joinChannel'),
                    style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 14),
                TextField(
                    controller: ctrl,
                    decoration:
                        InputDecoration(hintText: s.t('channelJoinLink'))),
                const SizedBox(height: 14),
                FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: WaColors.green),
                  onPressed: () async {
                    try {
                      final invite = ctrl.text.trim();
                      final ch = await st.api.newsletterPreview(invite);
                      await st.api.newsletterJoin(invite);
                      await st.refreshChannels();
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('${s.t('joined')}: ${ch.name}')));
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx)
                            .showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                  },
                  child: Text(s.t('join')),
                ),
              ]),
        ),
      ),
    );
  }
}

// ==================================================================== عارض الحالة ملء الشاشة

class StatusViewer extends StatefulWidget {
  final List<StatusItem> items;
  const StatusViewer({super.key, required this.items});

  @override
  State<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<StatusViewer> {
  int _idx = 0;

  void _next() {
    if (_idx < widget.items.length - 1) {
      setState(() => _idx++);
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<S>();
    final st = widget.items[_idx];
    final app = context.watch<AppState>();
    final url = st.mediaPath.isNotEmpty && st.mediaState == 'ready'
        ? app.api.mediaUrl(st.mediaPath)
        : '';
    final name =
        st.senderName.isEmpty ? st.sender.split('@').first : st.senderName;
    final time = WaTime.hhMm(st.timestamp);

    return Directionality(
      textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: _next,
          child: Stack(children: [
            // المحتوى
            if (st.type == 'image' && url.isNotEmpty)
              Center(
                  child: Image.network(url,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity))
            else if (st.type == 'video' && url.isNotEmpty)
              Center(child: _SimpleVideo(url: url, key: ValueKey(url)))
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    st.body.isEmpty ? '…' : st.body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 22, height: 1.5),
                  ),
                ),
              ),
            // شريط التقدم
            SafeArea(
              child: Column(children: [
                Row(
                  children: List.generate(
                      widget.items.length,
                      (i) => Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              color: i < _idx ? Colors.white : Colors.white24,
                            ),
                          )),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.white24,
                    child: Text(name.isNotEmpty ? name[0] : '?',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 16)),
                  ),
                  const SizedBox(width: 10),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        Text(time,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 11.5)),
                      ]),
                ]),
              ]),
            ),
            // أزرار التنقل
            PositionedDirectional(
              bottom: 26,
              end: 16,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                label: const Text('', style: TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// مشغل فيديو بسيط للحالة
class _SimpleVideo extends StatefulWidget {
  final String url;
  const _SimpleVideo({super.key, required this.url});

  @override
  State<_SimpleVideo> createState() => _SimpleVideoState();
}

class _SimpleVideoState extends State<_SimpleVideo> {
  VideoPlayerController? _ctl;

  @override
  void initState() {
    super.initState();
    _ctl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        _ctl?.play();
        if (mounted) setState(() {});
      }).catchError((_) {});
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ctl != null && _ctl!.value.isInitialized;
    if (!ready) {
      return const SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(color: Colors.white));
    }
    return AspectRatio(
      aspectRatio: _ctl!.value.aspectRatio,
      child: VideoPlayer(_ctl!),
    );
  }
}
