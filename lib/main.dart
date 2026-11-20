// نقطة التشغيل — تهيئة الحالة، الثيم، اللغة، وتوجيه شاشة الإقران/الرئيسية
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/strings.dart';
import 'core/theme.dart';
import 'screens/home_shell.dart';
import 'screens/pair_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF0B141A),
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const AfaqWhatsAppApp());
}

class AfaqWhatsAppApp extends StatelessWidget {
  const AfaqWhatsAppApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: Consumer<AppState>(
        builder: (context, st, _) {
          // اتجاه الواجهة الافتراضي من لغة النظام
          defaultLocaleIsArabic =
              PlatformDispatcher.instance.locale.languageCode == 'ar';
          return ChangeNotifierProvider(
            create: (_) => S(st),
            child: Consumer<S>(
              builder: (context, s, _) {
                final rtl = s.isRtl;
                final themePref = st.themePref;
                return MaterialApp(
                  title: 'آفاق واتساب',
                  debugShowCheckedModeBanner: false,
                  themeMode: switch (themePref) {
                    ThemeModePref.system => ThemeMode.system,
                    ThemeModePref.light => ThemeMode.light,
                    ThemeModePref.dark => ThemeMode.dark,
                  },
                  theme: waTheme(Brightness.light),
                  darkTheme: waTheme(Brightness.dark),
                  // اتجاه الواجهة (RTL/LTR) مطبق على كل المسارات عبر builder
                  builder: (context, child) => Directionality(
                    textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                    child: child!,
                  ),
                  home: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: st.paired ? const HomeShell() : const PairScreen(),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
