import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/theme/theme_provider.dart';

void main() {
  runApp(
    const ProviderScope(
      child: NRSApp(),
    ),
  );
}

class NRSApp extends StatelessWidget {
  const NRSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NRS - Notebook Reservation System',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.deepSeaTheme,
      home: const HomeScreen(),
    );
  }
}
