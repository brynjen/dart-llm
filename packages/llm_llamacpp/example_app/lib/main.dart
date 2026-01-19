import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const LlamaCppTestApp());
}

class LlamaCppTestApp extends StatelessWidget {
  const LlamaCppTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'llama.cpp Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'SF Pro Display',
      ),
      home: const HomeScreen(),
    );
  }
}
