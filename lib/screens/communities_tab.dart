// تبويب المجتمعات — مجموعاتك + الانضمام برابط دعوة
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';
import 'chats_tab.dart';
import 'contact_info_screen.dart';

class CommunitiesTab extends StatefulWidget {
  const CommunitiesTab({super.key});

  @override
  State<CommunitiesTab> createState() => _CommunitiesTabState();
}

class _CommunitiesTabState extends State<CommunitiesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().refreshGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final st = context.watch<AppState>();
    final c = WaColors.of(context);
    final s = context.watch<S>();
    final rtl = s.isRtl;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          // ---------------------------------------------------------- ترويسة المجتمع (شكل واتساب)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Row(children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: c.search,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.groups_2_rounded, size: 30, color: c.muted),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('communities'),
                          style: TextStyle(
                              color: c.text,
                              fontSize: 17.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 3),
                      Text(s.t('communityHint'),
                          style: TextStyle(
                              color: c.muted, fontSize: 13, height: 1.3)),
                    ]),
              ),
            ]),
          ),
          // ---------------------------------------------------------- بطاقة إنشاء مجتمع
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: WaColors.green,
                side: BorderSide(color: WaColors.green.withValues(alpha: 0.55)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
              icon: const Icon(Icons.group_add_outlined, size: 20),
              label: Text(s.t('newCommunity'),
                  style: const TextStyle(fontSize: 14)),
              onPressed: () {},
            ),
          ),
          const Divider(indent: 16, endIndent: 16),

          // ---------------------------------------------------------- مجموعاتك
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
            child: Text(s.t('yourGroups'),
                style: TextStyle(
                    color: WaColors.green,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700)),
          ),
          ...st.groups.map((g) {
            final jid = g['jid']?.toString() ?? '';
            final name = g['name']?.toString() ?? '';
            final size = int.tryParse('${g['size'] ?? 0}') ?? 0;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              leading: WaAvatar(jid: jid, name: name, isGroup: true, size: 48),
              title: Text(name.isEmpty ? jid.split('@').first : name,
                  style: TextStyle(
                      color: c.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              subtitle: Text('$size ${s.t('members')}',
                  style: TextStyle(color: c.muted, fontSize: 13)),
              onTap: () => ChatsTab.openChat(
                  context, jid, name.isEmpty ? jid.split('@').first : name),
              onLongPress: () => Navigator.of(context, rootNavigator: true)
                  .push(MaterialPageRoute(
                      builder: (_) => ContactInfoScreen(
                          jid: jid, name: name, isGroup: true))),
            );
          }),
          if (st.groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                  child: Text('لا توجد مجموعات بعد',
                      style: TextStyle(color: c.muted, fontSize: 13))),
            ),

          // ---------------------------------------------------------- الانضمام برابط
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: WaColors.green,
                side: BorderSide(color: WaColors.green.withValues(alpha: 0.55)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
              icon: const Icon(Icons.link_rounded, size: 20),
              label: Text(s.t('joinGroup'),
                  style: const TextStyle(fontSize: 13.5)),
              onPressed: () => _joinByLink(context),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _joinByLink(BuildContext context) async {
    final c = WaColors.of(context);
    final s = context.read<S>();
    final st = context.read<AppState>();
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(s.t('joinGroup')),
          content: TextField(
              controller: ctrl,
              decoration: InputDecoration(hintText: s.t('groupJoinLink'))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.t('cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: WaColors.green),
              onPressed: () async {
                try {
                  await st.api.joinGroup(ctrl.text.trim());
                  await st.refreshGroups();
                  await st.refreshChats();
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx)
                        .showSnackBar(SnackBar(content: Text(s.t('joined'))));
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
          ],
        ),
      ),
    );
  }
}
