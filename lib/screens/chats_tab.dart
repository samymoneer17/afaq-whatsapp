// تبويب المحادثات — قائمة واتساب الكلاسيكية مع الفلاتر والبحث
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';
import 'chat_screen.dart';

class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  /// فتح محادثة من أي مكان
  static void openChat(BuildContext context, String jid, String name) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => ChatScreen(jid: jid, title: name),
    ));
  }

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab>
    with AutomaticKeepAliveClientMixin {
  int _filter = 0; // 0 الكل، 1 غير مقروءة، 2 مجموعات
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final st = context.watch<AppState>();
    final c = WaColors.of(context);
    final s = context.watch<S>();
    final rtl = s.isRtl;

    var list = st.chats
        .where((ch) => !ch.isNewsletter && ch.jid != 'status@broadcast')
        .toList();
    if (_filter == 1) list = list.where((ch) => ch.unread > 0).toList();
    if (_filter == 2) list = list.where((ch) => ch.isGroup).toList();
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((ch) =>
              ch.name.toLowerCase().contains(q) ||
              ch.jid.contains(q) ||
              ch.lastMessage.toLowerCase().contains(q))
          .toList();
    }

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        children: [
          WaSearchBar(
            hint: s.t('search'),
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
          ),
          Expanded(
            child: list.isEmpty && _query.isEmpty && st.chats.isEmpty
                ? const WaEmpty(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'لا توجد محادثات بعد',
                    subtitle: 'ابدأ محادثة جديدة من الزر الأخضر أسفل الشاشة',
                  )
                : list.isEmpty && _query.isNotEmpty
                    ? const WaEmpty(
                        icon: Icons.search_off_rounded,
                        title: 'لا نتائج',
                        subtitle: 'جرّب كلمة أو رقم آخر',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 90),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(
                            indent: 76,
                            color: c.divider,
                            thickness: 0.5,
                            height: 0.5),
                        itemBuilder: (_, i) => _ChatTile(chat: list[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

// ==================================================================== الفلاتر

/// شرائح الفلاتر أعلى قائمة المحادثات — الكل / غير مقروءة / المجموعات
class ChatsFilterChips extends StatelessWidget {
  final ValueChanged<int> onChanged;
  const ChatsFilterChips({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = WaColors.of(context);
    final unread =
        st.chats.fold<int>(0, (a, ch) => a + (ch.unread > 0 ? 1 : 0));
    final groups = st.chats.where((ch) => ch.isGroup).length;
    final chips = <(String, int)>[
      ('الكل', st.chats.length),
      ('غير مقروءة', unread),
      ('المجموعات', groups),
    ];

    return SizedBox(
      height: 44,
      child: StatefulBuilder(
        builder: (context, setState) {
          int selected = 0;
          return Row(
            children: List.generate(chips.length, (i) {
              final (label, count) = chips[i];
              final sel = i == selected;
              return Padding(
                padding: EdgeInsetsDirectional.only(start: i == 0 ? 14 : 8),
                child: GestureDetector(
                  onTap: () {
                    setState(() => selected = i);
                    onChanged(i);
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: sel
                          ? WaColors.green.withValues(alpha: 0.16)
                          : c.search,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: sel
                              ? WaColors.green.withValues(alpha: 0.5)
                              : Colors.transparent),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(label,
                          style: TextStyle(
                              color: sel ? WaColors.green : c.muted,
                              fontSize: 12.8,
                              fontWeight:
                                  sel ? FontWeight.w600 : FontWeight.w500)),
                      if (count > 0 && i != 0) ...[
                        const SizedBox(width: 5),
                        Text('$count',
                            style: TextStyle(
                                color: sel ? WaColors.green : c.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700)),
                      ],
                    ]),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ==================================================================== بلاطة المحادثة

class _ChatTile extends StatelessWidget {
  final Chat chat;
  const _ChatTile({required this.chat});

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final st = context.read<AppState>();
    final s = context.read<S>();
    final timeTs = int.tryParse(chat.lastTimeStr) ?? 0;
    final typing = st.typing[chat.jid];

    final title = chat.name.isEmpty ? chat.jid.split('@').first : chat.name;

    return InkWell(
      onTap: () => ChatsTab.openChat(context, chat.jid, title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            WaAvatar(
              jid: chat.jid,
              name: title,
              picture: chat.picture,
              isGroup: chat.isGroup,
              onTap: () => ChatsTab.openChat(context, chat.jid, title),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        WaTime.listTime(timeTs, s.isRtl),
                        style: TextStyle(
                          color: chat.unread > 0 ? WaColors.green : c.muted,
                          fontSize: 12,
                          fontWeight: chat.unread > 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: typing != null
                            ? Text(
                                typing == 'recording'
                                    ? s.t('recording')
                                    : s.t('typing'),
                                style: const TextStyle(
                                    color: WaColors.green,
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic),
                              )
                            : ChatSnippet(chat: chat),
                      ),
                      if (chat.unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: WaColors.greenBadge,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${chat.unread}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
