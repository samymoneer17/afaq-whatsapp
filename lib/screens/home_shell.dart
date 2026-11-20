// الهيكل الرئيسي — تبويبات واتساب الحديثة مع مؤشر الحبة الخضراء
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';
import 'chats_tab.dart';
import 'communities_tab.dart';
import 'calls_tab.dart';
import 'settings_screen.dart';
import 'updates_tab.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late S s;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    s = context.read<S>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await st.refreshAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = WaColors.of(context);
    final rtl = s.isRtl;
    final session = st.session;

    // انقطع الاقتران → شاشة الربط تظهر تلقائياً (يديرها main)

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.bg,
        body: Column(
          children: [
            // ------------------------------------------------ ترويسة واتساب
            Container(
              color: c.appbar,
              child: Column(
                children: [
                  SizedBox(height: MediaQuery.of(context).padding.top),
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        const SizedBox(width: 20),
                        Text(_titleOf(_index),
                            style: TextStyle(
                                color: _index == 0 ? WaColors.green : c.text,
                                fontSize: 21,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        // حالة الاتصال الصغيرة
                        _ConnDot(state: session.state, paired: session.paired),
                        const SizedBox(width: 6),
                        _HeaderIcon(
                            icon: Icons.camera_alt_outlined,
                            tooltip: s.t('camera')),
                        _HeaderIcon(
                            icon: Icons.search_rounded, tooltip: s.t('search')),
                        PopupMenuButton<String>(
                          tooltip: s.t('more'),
                          color: c.surface,
                          iconColor: c.muted,
                          onSelected: (v) {
                            if (v == 'settings') {
                              Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                      builder: (_) => const SettingsScreen()));
                            }
                            if (v == 'logout') {
                              _confirmLogout(context);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                                value: 'group', child: Text(s.t('newGroup'))),
                            PopupMenuItem(
                                value: 'community',
                                child: Text(s.t('newCommunity'))),
                            PopupMenuItem(
                                value: 'broadcast',
                                child: Text(s.t('newBroadcast'))),
                            PopupMenuItem(
                                value: 'link', child: Text(s.t('linkDevice'))),
                            PopupMenuItem(
                                value: 'starred', child: Text(s.t('starred'))),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                                value: 'settings',
                                child: Text(s.t('settings'))),
                            PopupMenuItem(
                                value: 'logout', child: Text(s.t('logout'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ------------------------------------------------ التبويبات العلوية (المحادثات فقط لها فلاتر)
                  if (_index == 0)
                    ChatsFilterChips(
                      onChanged: (_) {},
                    ),
                ],
              ),
            ),
            // ------------------------------------------------ المحتوى
            Expanded(child: _body()),
          ],
        ),
        // ------------------------------------------------ شريط التبويبات السفلي
        bottomNavigationBar: Container(
          color: c.appbar,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 62,
              child: Row(
                children: List.generate(4, (i) {
                  return Expanded(
                      child: _TabItem(
                    index: i,
                    selected: _index == i,
                    icon: _iconOf(i),
                    badge: _badgeOf(i),
                    label: null,
                    onTap: () => setState(() => _index = i),
                  ));
                }),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ]),
        ),
        floatingActionButton: _fab(c, st),
      ),
    );
  }

  Widget _body() {
    switch (_index) {
      case 0:
        return const ChatsTab();
      case 1:
        return const UpdatesTab();
      case 2:
        return const CommunitiesTab();
      default:
        return const CallsTab();
    }
  }

  String _titleOf(int i) {
    switch (i) {
      case 0:
        return s.t('chats');
      case 1:
        return s.t('updates');
      case 2:
        return s.t('communities');
      default:
        return s.t('calls');
    }
  }

  IconData _iconOf(int i) {
    switch (i) {
      case 0:
        return Icons.chat_bubble_outline_rounded;
      case 1:
        return Icons.update_outlined;
      case 2:
        return Icons.groups_2_outlined;
      default:
        return Icons.phone_outlined;
    }
  }

  int? _badgeOf(int i) {
    final st = context.read<AppState>();
    if (i == 0) {
      final n = st.chats.fold<int>(0, (a, c) => a + c.unread);
      return n > 0 ? n : null;
    }
    if (i == 1 && st.statuses.isNotEmpty) return st.statuses.length;
    return null;
  }

  Widget? _fab(WaColors c, AppState st) {
    switch (_index) {
      case 0:
        return FloatingActionButton(
          onPressed: () => _openNewChat(context),
          child:
              const Icon(Icons.message_rounded, color: Colors.white, size: 26),
        );
      case 1:
        return FloatingActionButton(
          onPressed: () => _toast(s.t('statusHint')),
          child: const Icon(Icons.add_a_photo_outlined,
              color: Colors.white, size: 26),
        );
      case 2:
        return FloatingActionButton(
          onPressed: () => _toast(s.t('newCommunity')),
          child: const Icon(Icons.group_add_outlined,
              color: Colors.white, size: 26),
        );
      default:
        return FloatingActionButton(
          onPressed: () => _toast(s.t('createCallLink')),
          child:
              const Icon(Icons.add_link_rounded, color: Colors.white, size: 26),
        );
    }
  }

  void _openNewChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: WaColors.of(context).surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => NewChatSheet(onPick: (jid, name) {
        Navigator.of(context).pop();
        ChatsTab.openChat(context, jid, name);
      }),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final c = WaColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          backgroundColor: c.surface,
          title: Text(s.t('logout')),
          content: Text(s.t('logoutConfirm')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.t('cancel'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('logout')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AppState>().logout();
    }
  }
}

// ==================================================================== عناصر مساعدة

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  const _HeaderIcon({required this.icon, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: () {},
      icon: Icon(icon, size: 22, color: c.muted),
    );
  }
}

/// نقطة حالة الاتصال مع الخادم
class _ConnDot extends StatelessWidget {
  final String state;
  final bool paired;
  const _ConnDot({required this.state, required this.paired});

  @override
  Widget build(BuildContext context) {
    final color = !paired
        ? Colors.redAccent
        : state == 'connected'
            ? WaColors.greenBadge
            : Colors.orangeAccent;
    return Tooltip(
      message: paired ? state : 'pairing',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// عنصر تبويب سفلي — حبة دائرية خضراء حول الأيقونة المحددة مثل واتساب
class _TabItem extends StatelessWidget {
  final int index;
  final bool selected;
  final IconData icon;
  final int? badge;
  final String? label;
  final VoidCallback onTap;

  const _TabItem({
    required this.index,
    required this.selected,
    required this.icon,
    required this.onTap,
    this.badge,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final accent = selected ? WaColors.green : c.muted;
    return InkWell(
      onTap: onTap,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? WaColors.green.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 26, color: accent),
              if (badge != null)
                PositionedDirectional(
                  end: -8,
                  top: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: WaColors.greenBadge,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text(
                      '$badge',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ورقة بدء محادثة جديدة برقم هاتف
class NewChatSheet extends StatefulWidget {
  final void Function(String jid, String name) onPick;
  const NewChatSheet({super.key, required this.onPick});

  @override
  State<NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends State<NewChatSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _result;

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final st = context.read<AppState>();
    final phone = _ctrl.text.trim().replaceAll(RegExp(r'[\s\-()+]'), '');
    try {
      final j = await st.api.startChat(phone);
      if (!mounted) return;
      if (j['on_whatsapp'] == false) {
        setState(() {
          _result = context.read<S>().t('notOnWhatsapp');
          _busy = false;
        });
        return;
      }
      final jid = (j['jid'] ?? '$phone@s.whatsapp.net').toString();
      final name = (j['name'] ?? j['verified_name'] ?? phone).toString();
      await st.refreshChats();
      if (mounted) {
        setState(() => _busy = false);
        widget.onPick(jid, name);
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _result = e.toString();
          _busy = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final s = context.watch<S>();
    return Directionality(
      textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                  child: Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                          color: c.muted.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(3)))),
              const SizedBox(height: 16),
              Text(s.t('startChat'),
                  style: TextStyle(
                      color: c.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 14),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: c.text, fontSize: 15),
                decoration: InputDecoration(hintText: s.t('phoneNumber')),
              ),
              if (_result != null) ...[
                const SizedBox(height: 10),
                Text(_result!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12.5)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: WaColors.green,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _start,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.chat_rounded, size: 20),
                label:
                    Text(s.t('send'), style: const TextStyle(fontSize: 14.5)),
              ),
            ]),
      ),
    );
  }
}
