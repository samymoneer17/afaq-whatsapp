// شاشة الإعدادات — الحساب، الخصوصية، المظهر، اللغة، الخادم، الخروج
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// سلسلة الترجمة الحالية — متاحة داخل build (المراقبة) وخارجه (القراءة)
  S get s => context.read<S>();

  final _serverCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    _serverCtrl.text = st.serverUrl;
  }

  @override
  void dispose() {
    _serverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = context.watch<S>();
    final c = WaColors.of(context);
    final rtl = s.isRtl;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(s.t('settings'), style: TextStyle(color: c.text)),
          titleSpacing: 20,
        ),
        body: ListView(
          children: [
            // ================================================== بطاقة الحساب
            Container(
              margin: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: c.surface, borderRadius: BorderRadius.circular(15)),
              child: Row(children: [
                WaAvatar(
                  jid: st.session.myJid,
                  name: st.session.myName,
                  size: 62,
                  onTap: () {},
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            st.session.myName.isEmpty ? '—' : st.session.myName,
                            style: TextStyle(
                                color: c.text,
                                fontSize: 18,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 3),
                        Text(st.session.myJid.split('@').first,
                            style: TextStyle(color: c.muted, fontSize: 13.5)),
                        const SizedBox(height: 3),
                        Row(children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: st.session.state == 'connected'
                                    ? WaColors.greenBadge
                                    : Colors.orangeAccent),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            st.session.state == 'connected'
                                ? s.t('connected')
                                : s.t('connecting'),
                            style: TextStyle(color: c.muted, fontSize: 12),
                          ),
                        ]),
                      ]),
                ),
              ]),
            ),

            // ================================================== الخصوصية
            _section(c, s.t('privacy')),
            SettingsRow(
              icon: Icons.visibility_off_outlined,
              title: s.t('hideRead'),
              subtitle: s.t('privacy'),
              trailing: Switch(
                value: st.privacyRead,
                onChanged: (v) => context.read<AppState>().setPrivacyRead(v),
              ),
            ),

            // ================================================== المظهر واللغة
            _section(c, s.t('appearance')),
            SettingsRow(
              icon: Icons.dark_mode_outlined,
              title: s.t('themeMode'),
              subtitle: _themeLabel(st.themePref),
              onTap: () => _pickTheme(c),
            ),
            SettingsRow(
              icon: Icons.language_rounded,
              title: s.t('language'),
              subtitle: _langLabel(st.lang),
              onTap: () => _pickLang(c),
            ),

            // ================================================== الخادم
            _section(c, s.t('serverSettings')),
            SettingsRow(
              icon: Icons.dns_outlined,
              title: s.t('serverStatus'),
              subtitle: st.serverOk ? s.t('ok') : s.t('fail'),
              trailing: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        st.serverOk ? WaColors.greenBadge : Colors.redAccent),
              ),
              onTap: () async {
                final st2 = context.read<AppState>();
                try {
                  await st2.api.ping();
                  st2.serverOk = true;
                } catch (_) {
                  st2.serverOk = false;
                }
                st2.notifyListeners();
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
              child: Column(children: [
                TextField(
                  controller: _serverCtrl,
                  keyboardType: TextInputType.url,
                  style: TextStyle(color: c.text, fontSize: 13.5),
                  decoration: InputDecoration(
                      hintText: s.t('serverUrl'), isDense: true),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: WaColors.green,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9)),
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: Text(s.t('save'),
                        style: const TextStyle(fontSize: 12.5)),
                    onPressed: () async {
                      final st2 = context.read<AppState>();
                      await st2.setServerUrl(_serverCtrl.text.trim());
                      await st2.refreshSession();
                      if (st2.paired && mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text(s.t('save'))));
                      }
                    },
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: WaColors.green,
                        side: BorderSide(
                            color: WaColors.green.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 9)),
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: Text(s.t('logout'),
                        style: const TextStyle(fontSize: 12.5)),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(s.t('logout')),
                          content: Text(s.t('logoutConfirm')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: Text(s.t('cancel'))),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.redAccent),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(s.t('logout')),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        await context.read<AppState>().logout();
                        if (mounted) Navigator.pop(context);
                      }
                    },
                  ),
                ]),
              ]),
            ),

            // ================================================== عام
            _section(c, s.t('more')),
            SettingsRow(
                icon: Icons.bookmark_outline_rounded,
                title: s.t('starred'),
                onTap: () {}),
            SettingsRow(
                icon: Icons.help_outline_rounded,
                title: s.t('help'),
                onTap: () {}),
            SettingsRow(
                icon: Icons.person_add_alt_1_outlined,
                title: s.t('inviteFriend'),
                onTap: () {}),
            const SizedBox(height: 20),
            Center(
                child: Text('${s.t('app')} · v2.0',
                    style: TextStyle(
                        color: c.muted.withValues(alpha: 0.7),
                        fontSize: 11.5))),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(WaColors c, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Text(title.toUpperCase(),
            style: TextStyle(
                color: WaColors.green,
                fontSize: 12.5,
                fontWeight: FontWeight.w700)),
      );

  String _themeLabel(ThemeModePref p) {
    switch (p) {
      case ThemeModePref.system:
        return s.t('themeSystem');
      case ThemeModePref.light:
        return s.t('themeLight');
      case ThemeModePref.dark:
        return s.t('themeDark');
    }
  }

  String _langLabel(AppLang l) {
    switch (l) {
      case AppLang.system:
        return s.t('langSystem');
      case AppLang.arabic:
        return s.t('langAr');
      case AppLang.english:
        return s.t('langEn');
    }
  }

  Future<void> _pickTheme(WaColors c) async {
    final st = context.read<AppState>();
    final result = await showDialog<ThemeModePref>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: SimpleDialog(
          backgroundColor: c.surface,
          title: Text(s.t('themeMode'),
              style: TextStyle(color: c.text, fontSize: 17)),
          children: [
            _themeOption(ctx, st, ThemeModePref.system, s.t('themeSystem'),
                Icons.settings_suggest_outlined),
            _themeOption(ctx, st, ThemeModePref.light, s.t('themeLight'),
                Icons.light_mode_outlined),
            _themeOption(ctx, st, ThemeModePref.dark, s.t('themeDark'),
                Icons.dark_mode_outlined),
          ],
        ),
      ),
    );
    if (result != null) await st.setTheme(result);
  }

  Widget _themeOption(BuildContext ctx, AppState st, ThemeModePref v,
      String label, IconData icon) {
    final sel = st.themePref == v;
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, v),
      child: Row(children: [
        Icon(icon,
            size: 20, color: sel ? WaColors.green : WaColors.of(ctx).muted),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                color: sel ? WaColors.green : WaColors.of(ctx).text,
                fontSize: 15)),
        const Spacer(),
        if (sel)
          const Icon(Icons.check_rounded, color: WaColors.green, size: 20),
      ]),
    );
  }

  Future<void> _pickLang(WaColors c) async {
    final st = context.read<AppState>();
    final result = await showDialog<AppLang>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: SimpleDialog(
          backgroundColor: c.surface,
          title: Text(s.t('language'),
              style: TextStyle(color: c.text, fontSize: 17)),
          children: [
            _langOption(ctx, st, AppLang.system, s.t('langSystem'),
                Icons.settings_suggest_outlined),
            _langOption(ctx, st, AppLang.arabic, s.t('langAr'),
                Icons.translate_rounded),
            _langOption(ctx, st, AppLang.english, s.t('langEn'),
                Icons.translate_rounded),
          ],
        ),
      ),
    );
    if (result != null) await st.setLang(result);
  }

  Widget _langOption(
      BuildContext ctx, AppState st, AppLang v, String label, IconData icon) {
    final sel = st.lang == v;
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, v),
      child: Row(children: [
        Icon(icon,
            size: 20, color: sel ? WaColors.green : WaColors.of(ctx).muted),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                color: sel ? WaColors.green : WaColors.of(ctx).text,
                fontSize: 15)),
        const Spacer(),
        if (sel)
          const Icon(Icons.check_rounded, color: WaColors.green, size: 20),
      ]),
    );
  }
}
