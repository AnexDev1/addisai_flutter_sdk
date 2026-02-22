import 'package:flutter/material.dart';
import 'package:addis_ai_sdk/addis_ai_sdk.dart';
import 'chat_tab.dart';
import 'tts_tab.dart';
import 'realtime_tab.dart';

// Please use your real API key below or set it here for testing
const String apiKey = 'API KEY';

void main() {
  runApp(const AddisAIDemoApp());
}

class AddisAIDemoApp extends StatelessWidget {
  const AddisAIDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Addis AI SDK Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  late final AddisAI _client;

  @override
  void initState() {
    super.initState();
    _client = AddisAI(apiKey: apiKey);
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (apiKey == 'YOUR_API_KEY') {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Please add your real API key in main.dart to run the example.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
        ),
      );
    }

    final screens = [
      ChatTab(client: _client),
      TtsTab(client: _client),
      RealtimeTab(client: _client),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: 'TTS',
          ),
          NavigationDestination(
            icon: Icon(Icons.compare_arrows),
            label: 'Realtime',
          ),
        ],
      ),
    );
  }
}
