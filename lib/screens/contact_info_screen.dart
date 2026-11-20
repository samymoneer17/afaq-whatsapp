// شاشة معلومات جهة الاتصال أو المجموعة — الصورة الكبيرة، النبذة، الأعضاء
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';
import 'chats_tab.dart';

class ContactInfoScreen extends StatefulWidget {
  final String jid;
  final String name;
  final bool isGroup;
  const ContactInfoScreen(
      {super.key, required this.jid, required this.name, this.isGroup = false});

  @override
  State<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends State<ContactInfoScreen> {
  ContactInfo? _contact;
  GroupInfo? _group;
  bool _loading = true;
  late S s;

  @override
  void initState() {
    super.initState();
    s = context.read<S>();
    _load();
  }

  Future<void> _load() async {
    final st = context.read<AppState>();
    try {
      if (widget.isGroup || widget.jid.endsWith('@g.us')) {
        final g = await st.api.groupInfo(widget.jid);
        if (mounted)
          setState(() {
            _group = g;
            _loading = false;
          });
      } else {
        final ci = await st.api.contactInfo(widget.jid);
        if (mounted)
          setState(() {
            _contact = ci;
            _loading = false;
          });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final st = context.watch<AppState>();
    final rtl = s.isRtl;
    final isGroup = widget.isGroup || widget.jid.endsWith('@g.us');
    final name = _group?.name ??
        (widget.name.isEmpty ? widget.jid.split('@').first : widget.name);
    final about = _contact?.about ?? (isGroup ? _group?.topic ?? '' : '');
    final avatarUrl = st.avatarCache[widget.jid];

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.chatBg,
        appBar: AppBar(
          backgroundColor: c.appbar,
          title: Text(isGroup ? s.t('groupInfo') : s.t('contactInfo'),
              style: TextStyle(color: c.text, fontSize: 18)),
        ),
        body: _loading
            ? const WaLoader()
            : ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  const SizedBox(height: 26),
                  // ------------------------------------------------ الصورة الكبيرة
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: WaColors.green.withValues(alpha: 0.4),
                            width: 2),
                      ),
                      child: WaAvatar(
                        jid: widget.jid,
                        name: name,
                        picture: avatarUrl ?? '',
                        size: 132,
                        isGroup: isGroup,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                      child: Text(name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: c.text,
                              fontSize: 21,
                              fontWeight: FontWeight.w600))),
                  if (!isGroup) ...[
                    const SizedBox(height: 4),
                    Center(
                        child: Text(widget.jid.split('@').first,
                            style: TextStyle(color: c.muted, fontSize: 14))),
                    if (_contact?.onWhatsapp != null) ...[
                      const SizedBox(height: 6),
                      Center(
                          child: Text(
                        _contact!.onWhatsapp!
                            ? s.t('onWhatsapp')
                            : s.t('notOnWhatsapp'),
                        style: TextStyle(
                            color: _contact!.onWhatsapp!
                                ? WaColors.green
                                : Colors.redAccent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500),
                      )),
                    ],
                  ] else ...[
                    const SizedBox(height: 4),
                    Center(
                        child: Text('${_group?.size ?? 0} ${s.t('members')}',
                            style: TextStyle(color: c.muted, fontSize: 13))),
                  ],
                  const SizedBox(height: 20),

                  // ------------------------------------------------ النبذة
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.t('about'),
                                  style: TextStyle(
                                      color: WaColors.green,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              Text(about.isEmpty ? '—' : about,
                                  style: TextStyle(
                                      color: c.text,
                                      fontSize: 14.5,
                                      height: 1.4)),
                            ]),
                      ),
                      Icon(
                          isGroup
                              ? Icons.info_outline_rounded
                              : Icons.message_outlined,
                          color: c.muted,
                          size: 22),
                    ]),
                  ),

                  // ------------------------------------------------ أزرار سريعة
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(children: [
                      _actionBtn(c, Icons.chat_rounded, s.t('message'), () {
                        Navigator.pop(context);
                        ChatsTab.openChat(context, widget.jid, name);
                      }),
                      const SizedBox(width: 10),
                      _actionBtn(
                          c, Icons.videocam_rounded, s.t('video'), () {}),
                      const SizedBox(width: 10),
                      _actionBtn(c, Icons.call_rounded, s.t('calls'), () {}),
                    ]),
                  ),

                  // ------------------------------------------------ أعضاء المجموعة
                  if (_group != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(14)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                              child: Text('${s.t('members')} (${_group!.size})',
                                  style: TextStyle(
                                      color: WaColors.green,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ),
                            ..._group!.participants.map((p) {
                              final isAdmin = p.isSuperAdmin || p.isAdmin;
                              return ListTile(
                                dense: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                leading: WaAvatar(
                                    jid: p.jid,
                                    name: p.jid.split('@').first,
                                    size: 38),
                                title: Text(p.jid.split('@').first,
                                    style: TextStyle(
                                        color: c.text, fontSize: 14.5)),
                                subtitle: Text(
                                    isAdmin
                                        ? (p.isSuperAdmin
                                            ? '${s.t('admins')} — مجتمع'
                                            : s.t('admins'))
                                        : p.jid.split('@').first,
                                    style: TextStyle(
                                        color: c.muted, fontSize: 12)),
                                trailing: isAdmin
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                            color: WaColors.green
                                                .withValues(alpha: 0.14),
                                            borderRadius:
                                                BorderRadius.circular(9)),
                                        child: Text(s.t('admins'),
                                            style: const TextStyle(
                                                color: WaColors.green,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600)),
                                      )
                                    : null,
                              );
                            }),
                          ]),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _actionBtn(
      WaColors c, IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Icon(icon, color: WaColors.green, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(color: WaColors.green, fontSize: 11.5)),
          ]),
        ),
      ),
    );
  }
}
