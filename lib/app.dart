import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'pages/app_root.dart';

class FamilyNaviApp extends StatelessWidget {
  const FamilyNaviApp({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.notoSansScTextTheme(
      ThemeData.light().textTheme,
    );
    return MaterialApp(
      title: '家人拜年导航',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
        textTheme: textTheme,
      ),
      home: const AppRoot(),
    );
  }
}
