import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/battlebox_editor_screen.dart';

void main() {
  runApp(const ProviderScope(child: WikiishBattleBoxGenerator()));
}

class WikiishBattleBoxGenerator extends StatelessWidget {
  const WikiishBattleBoxGenerator({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Battlebox Generator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F4457),
        ),
        fontFamily: 'Georgia',
        useMaterial3: true,
      ),
      home: const BattleBoxEditorScreen(),
    );
  }
}
