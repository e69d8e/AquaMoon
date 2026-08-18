import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'views/home/home_page.dart';

class SoundCraftApp extends StatelessWidget {
  const SoundCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '水月音',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light, // Set default to clean light mode
      home: const HomePage(),
    );
  }
}
