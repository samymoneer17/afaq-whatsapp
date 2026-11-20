// شاشة القناة — المنشورات والتفاعل بالإيموجي ومغادرة القناة
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';

class ChannelScreen extends StatefulWidget {
  final Channel channel;
  const ChannelScreen({super.key, required this.channel});

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen> {
  late Channel _ch;
  List<Message> _posts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ch = widget.channel;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final st = context.read<AppState>();
    try {
      final posts = await st.api.newsletterPosts(_ch.jid);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _react(Message m, String emoji) async {
    final st = context.read<AppState>();
    try {
      await st.api.react(_ch.jid, m.id, emoji);
      await _load();
    } catch (_) {}
  }

  Future<void> _leave() async {
    final s = context.read<S>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('leaveChannel')),
        content: Text(widget.channel.name),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('leaveChannel')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final st = context.read<AppState>();
      try {
        await st.api.newsletterLeave(_ch.jid);
        await st.refreshChannels();
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final s = context.watch<S>();
    final rtl = s.isRtl;
    final st = context.watch<AppState>();

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.chatBg,
        appBar: AppBar(
          title: InkWell(
            onTap: () {},
            child: Row(children: [
              WaAvatar(
                  jid: _ch.jid, name: _ch.name, picture: _ch.picture, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_ch.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.text,
                              fontSize: 16.5,
                              fontWeight: FontWeight.w600)),
                      Text('${_ch.subscribers} ${s.t('subscribers')}',
                          style: TextStyle(color: c.muted, fontSize: 12)),
                    ]),
              ),
            ]),
          ),
          actions: [
            PopupMenuButton<String>(
              color: c.surface,
              iconColor: c.muted,
              onSelected: (v) {
                if (v == 'leave') _leave();
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'leave', child: Text(s.t('leaveChannel'))),
              ],
            ),
          ],
        ),
        body: _loading
            ? const WaLoader()
            : _error != null
                ? Center(
                    child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13)),
                  ))
                : _posts.isEmpty
                    ? const WaEmpty(
                        icon: Icons.campaign_outlined,
                        title: 'لا منشورات بعد',
                        subtitle: 'منشورات هذه القناة ستظهر هنا',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: WaColors.green,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: _posts.length,
                          itemBuilder: (_, i) =>
                              _ChannelPost(m: _posts[i], onReact: _react),
                        ),
                      ),
        // تفاعل سريع أسفل الشاشة؟ لا — التفاعل عبر الضغط المطول على المنشور
      ),
    );
  }
}

class _ChannelPost extends StatelessWidget {
  final Message m;
  final Future<void> Function(Message, String) onReact;
  const _ChannelPost({required this.m, required this.onReact});

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final st = context.read<AppState>();
    final url = m.media.ready ? st.api.mediaUrl(m.media.path) : '';
    const emojis = ['👍', '❤️', '😂', '😮', '😢'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.bubbleIn,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 3,
              offset: const Offset(0, 1))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (m.type == 'image' && url.isNotEmpty)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.network(url,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 2)),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(
                  WaTime.dayLabel(m.timestamp, true) +
                      ' · ' +
                      WaTime.hhMm(m.timestamp),
                  style: TextStyle(color: c.muted, fontSize: 11)),
            ]),
            if (m.body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(m.body,
                  style:
                      TextStyle(color: c.text, fontSize: 14.5, height: 1.35)),
            ],
            const SizedBox(height: 10),
            Row(
                children: emojis.map((e) {
              final mine = m.reactions[e] != null;
              return Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: GestureDetector(
                  onTap: () => onReact(m, mine ? '' : e),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: mine
                          ? WaColors.green.withValues(alpha: 0.15)
                          : c.search,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: mine
                              ? WaColors.green.withValues(alpha: 0.5)
                              : c.divider),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 14)),
                  ),
                ),
              );
            }).toList()),
          ]),
        ),
      ]),
    );
  }
}
