// شاشة الربط — إعداد الخادم ثم كود الإقران أو QR
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../core/models.dart';
import '../core/theme.dart';
import '../core/strings.dart';
import '../ui/common.dart';

/// العتبة الافتراضية لعنوان الخادم — قابلة للتعديل من شاشة الربط نفسها
/// اكتب عنوان خادمك في شاشة الربط (مثال: http://SERVER_IP:8000)
const String kDefaultServerUrl = '';

class PairScreen extends StatefulWidget {
  const PairScreen({super.key});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen>
    with SingleTickerProviderStateMixin {
  final _phoneCtrl = TextEditingController(text: '966');
  final _serverCtrl = TextEditingController();
  bool _connecting = false;
  bool _pairRequested = false;
  String? _error;
  late AnimationController _dots;
  late S s;

  @override
  void initState() {
    super.initState();
    _dots = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
    final st = context.read<AppState>();
    _serverCtrl.text = st.serverUrl.isEmpty ? kDefaultServerUrl : st.serverUrl;
    s = context.read<S>();
    // التحقق الأولي من حالة الجلسة
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await st.refreshSession();
      if (mounted && st.serverUrl.isNotEmpty && st.serverOk)
        setState(() => _connecting = false);
    });
  }

  @override
  void dispose() {
    _dots.dispose();
    _phoneCtrl.dispose();
    _serverCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectServer() async {
    setState(() {
      _connecting = true;
      _error = null;
    });
    final st = context.read<AppState>();
    try {
      await st.setServerUrl(_serverCtrl.text.trim());
      final ms = await st.api.ping();
      if (!mounted) return;
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${s.t('ok')} (${ms.inMilliseconds} ms)')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '${s.t('fail')}: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _requestPair() async {
    final st = context.read<AppState>();
    final phone = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-()+]'), '');
    if (phone.length < 8) {
      setState(() => _error = s.t('phoneNumber'));
      return;
    }
    setState(() {
      _error = null;
      _pairRequested = true;
    });
    try {
      await st.api.pair(phone);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _pairRequested = false;
        });
    }
  }

  Future<void> _requestQr() async {
    final st = context.read<AppState>();
    try {
      await st.api.requestQr();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final c = WaColors.of(context);
    final rtl = s.isRtl;
    final session = st.session;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(s.t('app'),
              style: TextStyle(
                  color: WaColors.green,
                  fontWeight: FontWeight.w700,
                  fontSize: 20)),
          actions: [
            if (st.serverUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Row(children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: st.serverOk
                              ? WaColors.greenBadge
                              : Colors.redAccent),
                    ),
                    const SizedBox(width: 6),
                    Text(st.serverOk ? s.t('ok') : s.t('fail'),
                        style: TextStyle(color: c.muted, fontSize: 12)),
                  ]),
                ),
              ),
          ],
        ),
        body: session.paired
            ? _buildLinked(c, st)
            : _buildPairing(c, st, session),
      ),
    );
  }

  // ------------------------------------------------------------ مقترن — الانتقال للرئيسية تتم في main
  Widget _buildLinked(WaColors c, AppState st) => const SizedBox();

  // ------------------------------------------------------------ شاشة الإقران
  Widget _buildPairing(WaColors c, AppState st, SessionInfo session) {
    // لو صار كود إقران أو QR نعرضهما
    final hasCode = session.pairingCode.isNotEmpty;
    final hasQr = session.qrSvg.isNotEmpty;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            // شعار
            Center(
                child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [WaColors.green, Color(0xFF017561)]),
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                      color: WaColors.green.withValues(alpha: 0.35),
                      blurRadius: 22,
                      offset: const Offset(0, 8))
                ],
              ),
              child:
                  const Icon(Icons.chat_rounded, color: Colors.white, size: 46),
            )),
            const SizedBox(height: 22),
            Text(s.t('pairTitle'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.text, fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(
              session.pairError.isNotEmpty
                  ? '${s.t('pairError')}: ${session.pairError}'
                  : s.t('pairHint1'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color:
                      session.pairError.isNotEmpty ? Colors.redAccent : c.muted,
                  fontSize: 13.5,
                  height: 1.5),
            ),

            // ------------------------------------------------ كود الإقران
            if (hasCode) ...[
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: WaColors.green.withValues(alpha: 0.4),
                        width: 1.4)),
                child: Column(children: [
                  Text(s.t('pairCodeTitle'),
                      style: TextStyle(
                          color: c.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 14),
                  Text(
                    _formatCode(session.pairingCode),
                    style: TextStyle(
                      color: WaColors.green,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(s.t('pairCodeHint'),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: c.muted, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 14),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    _PulsingDots(controller: _dots),
                    const SizedBox(width: 8),
                    Text(s.t('waitingPair'),
                        style: TextStyle(color: c.muted, fontSize: 12.5)),
                  ]),
                ]),
              ),
            ] else if (hasQr) ...[
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                child: SvgPicture.string(
                  session.qrSvg,
                  width: 230,
                  height: 230,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
              Text(s.t('pairHint2'),
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: c.muted, fontSize: 12.5, height: 1.5)),
            ],

            const SizedBox(height: 26),

            // ------------------------------------------------ الخادم
            Text(s.t('connectServer'),
                style: TextStyle(
                    color: c.text,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _serverCtrl,
              keyboardType: TextInputType.url,
              style: TextStyle(color: c.text, fontSize: 14),
              decoration: InputDecoration(
                  hintText: s.t('serverUrl'),
                  suffixIcon: IconButton(
                      icon: Icon(Icons.check_circle_outline_rounded,
                          color: _connecting ? c.muted : WaColors.green),
                      onPressed: _connecting ? null : _connectServer)),
            ),

            const SizedBox(height: 18),
            _ErrorBox(text: _error),

            // ------------------------------------------------ الأزرار
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: WaColors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.link_rounded, size: 20),
              label: Text(s.t('pairBtn'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              onPressed: st.serverOk ? _requestPair : _connectServer,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: WaColors.green,
                side: BorderSide(color: WaColors.green.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.qr_code_rounded, size: 20),
              label: Text(s.t('qrBtn'),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              onPressed: st.serverOk ? _requestQr : _connectServer,
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                _connecting
                    ? s.t('connectingServer')
                    : (st.serverOk ? s.t('connected') : s.t('offline')),
                style: TextStyle(
                    color: st.serverOk ? WaColors.green : Colors.redAccent,
                    fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCode(String code) {
    final clean = code.replaceAll(RegExp(r'\s'), '');
    if (clean.length <= 4) return clean;
    return '${clean.substring(0, 4)}-${clean.substring(4)}';
  }
}

class _ErrorBox extends StatelessWidget {
  final String? text;
  const _ErrorBox({this.text});

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) return const SizedBox(height: 12);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded,
              color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12.5))),
        ]),
      ),
    );
  }
}

/// نقاط نابضة تنتظر الإقران
class _PulsingDots extends StatelessWidget {
  final AnimationController controller;
  const _PulsingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) => Row(
          children: List.generate(3, (i) {
        final v = ((controller.value * 3) - i).clamp(0.0, 1.0);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                WaColors.green.withValues(alpha: 0.25 + 0.75 * (1 - v).abs()),
          ),
        );
      })),
    );
  }
}
