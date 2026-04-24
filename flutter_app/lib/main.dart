import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'screens/chat_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService.init();
  runApp(const KnowledgeApp());
}

class KnowledgeApp extends StatelessWidget {
  const KnowledgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Knowledge Assistant',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
      home: const AppEntry(),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  StreamSubscription? _intentSub;
  String? _sharedUrl;

  @override
  void initState() {
    super.initState();

    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((value) {
      final url = _extractUrl(value);
      if (url != null) setState(() => _sharedUrl = url);
    });

    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      final url = _extractUrl(value);
      if (url != null) setState(() => _sharedUrl = url);
      ReceiveSharingIntent.instance.reset();
    });
  }

  String? _extractUrl(List<SharedMediaFile> files) {
    if (files.isEmpty) return null;
    final text = files.first.path;
    final urlMatch = RegExp(r'https?://\S+').firstMatch(text);
    return urlMatch?.group(0);
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatScreen(key: ValueKey(_sharedUrl), sharedUrl: _sharedUrl);
  }
}
