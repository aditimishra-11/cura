import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../widgets/chat_bubble.dart';
import 'settings_screen.dart';

class ChatMessage {
  final String text;
  final BubbleType type;
  final String? label;

  ChatMessage({required this.text, required this.type, this.label});
}

class ChatScreen extends StatefulWidget {
  final String? sharedUrl;

  const ChatScreen({super.key, this.sharedUrl});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _addWelcome();
    _checkDigest();
    if (widget.sharedUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send(widget.sharedUrl!));
    }
  }

  void _addWelcome() {
    _messages.add(ChatMessage(
      text: "Hi! Send me a URL to save it, or ask me anything about your saved content.\n\n"
          "Try: *\"teach me about RAG\"*, *\"I'm building a dashboard, what's useful?\"*, "
          "or *\"what haven't I read yet?\"*\n\n"
          "You can also mix: *\"https://example.com — remind me to try this tomorrow\"*",
      type: BubbleType.assistant,
    ));
  }

  Future<void> _checkDigest() async {
    try {
      final digest = await ApiService.fetchDigest();
      if (digest != null && mounted) {
        setState(() {
          _messages.add(ChatMessage(
            text: "📬 **Weekly Digest**\n\n${digest.message}",
            type: BubbleType.assistant,
            label: "Weekly digest",
          ));
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add(ChatMessage(text: text, type: BubbleType.user));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final result = await ApiService.sendMessage(text);
      setState(() {
        _messages.add(ChatMessage(
          text: result.response,
          type: BubbleType.assistant,
          label: result.mode,
        ));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: "Something went wrong. Check your connection and try again.",
          type: BubbleType.system,
        ));
      });
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  Future<void> _sendFromInput() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;
    _controller.clear();
    await _send(text);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cura"),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: "Status",
            onPressed: _showStatus,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => ChatBubble(
                text: _messages[i].text,
                type: _messages[i].type,
                label: _messages[i].label,
              ),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: LinearProgressIndicator(),
            ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                onSubmitted: (_) => _sendFromInput(),
                decoration: InputDecoration(
                  hintText: "Send a URL or ask a question…",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                maxLines: null,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _loading ? null : _sendFromInput,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showStatus() async {
    try {
      final result = await ApiService.status();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text("${result.total} saves"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: result.byIntent.entries
                .map((e) => ListTile(
                      leading: const Icon(Icons.label_outline),
                      title: Text(e.key),
                      trailing: Text("${e.value}", style: const TextStyle(fontWeight: FontWeight.bold)),
                      dense: true,
                    ))
                .toList(),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reach the server")),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
