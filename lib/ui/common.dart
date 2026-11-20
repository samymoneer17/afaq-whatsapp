// عناصر واجهة مشتركة: الصور الشخصية، علامات القراءة، التنسيق الزمني، عناصر القوائم
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/strings.dart';

/// صورة شخصية دائرية — تجلب الصورة من الخادم تلقائياً أو تعرض الحرف الأول
class WaAvatar extends StatefulWidget {
  final String jid;
  final String name;
  final String picture; // رابط مباشر إن وجد
  final double size;
  final bool isGroup;
  final VoidCallback? onTap;

  const WaAvatar({
    super.key,
    required this.jid,
    this.name = '',
    this.picture = '',
    this.size = 48,
    this.isGroup = false,
    this.onTap,
  });

  @override
  State<WaAvatar> createState() => _WaAvatarState();
}

class _WaAvatarState extends State<WaAvatar> {
  String _url = '';

  @override
  void initState() {
    super.initState();
    _url = widget.picture;
    _load();
  }

  @override
  void didUpdateWidget(covariant WaAvatar old) {
    super.didUpdateWidget(old);
    if (old.picture != widget.picture || old.jid != widget.jid) {
      _url = widget.picture;
      _load();
    }
  }

  Future<void> _load() async {
    if (widget.picture.isEmpty && widget.jid.isNotEmpty) {
      final st = context.read<AppState>();
      final cached = st.avatarCache[widget.jid] ?? '';
      if (cached.isNotEmpty) {
        if (mounted) setState(() => _url = cached);
        return;
      }
      final url = await st.avatarOf(widget.jid);
      if (mounted && url.isNotEmpty) setState(() => _url = url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final fallbackColor = _colorFor(widget.jid);
    final widget_ = ClipOval(
      child: Container(
        width: widget.size,
        height: widget.size,
        color: c.avatarPlaceholder,
        child: _url.isNotEmpty
            ? Image.network(
                context.read<AppState>().api.mediaUrl(_url),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(fallbackColor),
                frameBuilder: (ctx, child, f, _) => f == null
                    ? child
                    : AnimatedOpacity(
                        opacity: 1,
                        duration: const Duration(milliseconds: 200),
                        child: child),
              )
            : _fallback(fallbackColor),
      ),
    );
    return GestureDetector(
      onTap: widget.onTap,
      child: widget_,
    );
  }

  Widget _fallback(Color color) => Container(
        color: color,
        alignment: Alignment.center,
        child: widget.isGroup
            ? Icon(Icons.groups_rounded,
                color: Colors.white, size: widget.size * 0.55)
            : Text(
                _initial(),
                style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.size * 0.42,
                    fontWeight: FontWeight.w500),
              ),
      );

  String _initial() {
    final n = widget.name.trim();
    if (n.isEmpty) return '?';
    final cp = n.runes.first;
    return String.fromCharCode(cp);
  }

  /// لون ثابت مشتق من الـ jid — نفس ما يفعل واتساب تقريباً
  static Color _colorFor(String jid) {
    const palette = [
      Color(0xFF6A5ACD),
      Color(0xFFCD5C5C),
      Color(0xFF20B2AA),
      Color(0xFFDA70D6),
      Color(0xFFF4A460),
      Color(0xFF7B68EE),
      Color(0xFFE9967A),
      Color(0xFF48D1CC),
      Color(0xFF9ACD32),
      Color(0xFFFFB347),
    ];
    var h = 0;
    for (final cp in jid.runes) {
      h = (h * 31 + cp) & 0x7FFFFFFF;
    }
    return palette[h % palette.length];
  }
}

/// علامات القراءة ✓ / ✓✓ بألوانها الرسمية
class WaTicks extends StatelessWidget {
  final String receipt;
  final double size;
  const WaTicks({super.key, required this.receipt, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final read = receipt == 'read';
    final color = read ? WaColors.tickRead : Colors.grey.shade500;
    switch (receipt) {
      case 'read':
      case 'delivered':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_icon(receipt), color: color, size: size),
          const SizedBox(width: 2),
          Icon(_icon(receipt), color: color, size: size),
        ]);
      case 'sent':
        return Icon(Icons.done, color: color, size: size);
      default:
        return Icon(Icons.schedule,
            color: Colors.grey.shade500, size: size - 1);
    }
  }

  IconData _icon(String r) =>
      r == 'delivered' ? Icons.done_all : Icons.done_all;
}

/// تنسيق الوقت: وقت قصير للقائمة / تسمية يوم داخل المحادثة / توقيت الرسالة
class WaTime {
  static String hhMm(int ts) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// وسم اليوم داخل المحادثة: اليوم / أمس / ١٢ نوفمبر
  static String dayLabel(int ts, bool rtl) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return rtl ? 'اليوم' : 'Today';
    if (diff == 1) return rtl ? 'أمس' : 'Yesterday';
    const monthsAr = [
      '',
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    const monthsEn = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final months = rtl ? monthsAr : monthsEn;
    return '${d.day} ${months[d.month]} ${d.year == now.year ? '' : d.year}';
  }

  /// وقت بجوار آخر رسالة في قائمة المحادثات: الوقت إن اليوم، أمس، أو التاريخ
  static String listTime(int ts, bool rtl) {
    if (ts <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return hhMm(ts);
    if (diff == 1) return rtl ? 'أمس' : 'Yesterday';
    if (now.year == d.year) {
      const monthsAr = [
        '',
        '١',
        '٢',
        '٣',
        '٤',
        '٥',
        '٦',
        '٧',
        '٨',
        '٩',
        '١٠',
        '١١',
        '١٢'
      ];
      return rtl
          ? '${d.day}/${monthsAr[d.month]}'
          : '${d.day}/${d.month}/${d.year}';
    }
    return '${d.day}/${d.month}/${d.year}';
  }
}

/// شريط البحث الدائري أعلى المحادثات
class WaSearchBar extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController controller;
  const WaSearchBar(
      {super.key,
      required this.hint,
      required this.onChanged,
      required this.controller});

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: TextStyle(color: c.text, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(Icons.search_rounded, color: c.muted, size: 22),
          isDense: true,
          filled: true,
          fillColor: c.search,
        ),
      ),
    );
  }
}

/// نص آخر رسالة مع أيقونة نوع الوسائط — كما في قائمة واتساب
class ChatSnippet extends StatelessWidget {
  final Chat chat;
  const ChatSnippet({super.key, required this.chat});

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    final s = context.read<S>();
    Widget text() => Expanded(
          child: Text(
            chat.lastMessage.isEmpty ? '…' : chat.lastMessage,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: c.muted, fontSize: 14, height: 1.25),
          ),
        );

    // محاولة استخراج نوع الوسائط من الملخص
    final lm = chat.lastMessage.toLowerCase();
    Widget? icon;
    if (lm.startsWith('[صورة]') || lm.startsWith('[image]'))
      icon = _mi(context, Icons.photo_outlined, '[صورة] ');
    if (lm.startsWith('[فيديو]') || lm.startsWith('[video]'))
      icon = _mi(context, Icons.videocam_outlined, '[فيديو] ');
    if (lm.startsWith('[صوت]') || lm.startsWith('[audio]'))
      icon = _mi(context, Icons.mic_none_outlined, '[صوت] ');
    if (lm.startsWith('[مستند]') || lm.startsWith('[document]'))
      icon = _mi(context, Icons.description_outlined, '[مستند] ');
    if (icon != null) {
      return Row(children: [icon, text()]);
    }
    return Row(children: [text()]);
  }

  Widget _mi(BuildContext context, IconData i, String strip) {
    final c = WaColors.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Icon(i, size: 15, color: c.muted),
    );
  }
}

/// حالة فراغ رسمية مع أيقونة وعنوان وشرح
class WaEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const WaEmpty(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(color: c.search, shape: BoxShape.circle),
            child: Icon(icon, size: 52, color: c.muted),
          ),
          const SizedBox(height: 18),
          Text(title,
              style: TextStyle(
                  color: c.text, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontSize: 13.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// شعار التحميل الدائري الأخضر
class WaLoader extends StatelessWidget {
  const WaLoader({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator(strokeWidth: 2.6));
}

/// صف معلومات في الإعدادات
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor = WaColors.green,
  });

  @override
  Widget build(BuildContext context) {
    final c = WaColors.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, color: iconColor, size: 24),
      title: Text(title, style: TextStyle(color: c.text, fontSize: 15.5)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TextStyle(color: c.muted, fontSize: 12.5)),
      trailing: trailing,
    );
  }
}
