// تبويب المكالمات — واجهة مطابقة مع حالة فراغ رسمية (الباكند لا يوفر مكالمات حقيقية)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';

class CallsTab extends StatefulWidget {
  const CallsTab({super.key});

  @override
  State<CallsTab> createState() => _CallsTabState();
}

class _CallsTabState extends State<CallsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final c = WaColors.of(context);
    final s = context.watch<S>();
    final rtl = s.isRtl;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Column(
        children: [
          // ---------------------------------------------------------- بطاقة رابط المكالمة
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [WaColors.green, Color(0xFF017561)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.add_link_rounded,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.t('createCallLink'),
                          style: TextStyle(
                              color: c.text,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('أرسل رابطاً وأشرك الجميع في مكالمة واحدة',
                          style: TextStyle(color: c.muted, fontSize: 12.5)),
                    ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ]),
          ),
          const SizedBox(height: 8),
          const Divider(indent: 16, endIndent: 16),

          // ---------------------------------------------------------- الفراغ
          Expanded(
            child: WaEmpty(
              icon: Icons.phone_outlined,
              title: s.t('noCalls'),
              subtitle: s.t('callsHint'),
            ),
          ),
        ],
      ),
    );
  }
}
