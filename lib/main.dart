import 'package:flutter/material.dart';

void main() {
  runApp(const WikiishBattleBoxGenerator());
}

class WikiishBattleBoxGenerator extends StatelessWidget {
  const WikiishBattleBoxGenerator({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.lightBlue),
      ),
      home: const Scaffold(
        body: Center(
          child: Text('WIP'),
        ),
      )
    );
  }
}