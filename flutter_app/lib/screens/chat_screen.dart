import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../widgets/chat_bubble.dart';
import 'settings_screen.dart';

// Design palette (local aliases)
const _bg        = Color(0xFF0F0E17);
const _surface2  = Color(0xFF1E1D2C);
const _surface3  = Color(0xFF262537);
const _surface4  = Color(0xFF2E2D40);
const _border    = Color(0xFF2C2B3D);
const _text1     = Color(0xFFEDECF4);
const _text2     = Color(0xFF9B9AAE);
const _text3     = Color(0xFF5C5B72);
const _accent    = Color(0xFFA78BFA);
// ignore: unused_element
const _accentDim = Color(0xFF7C6DB5);

class ChatMessage {
  final String text;
  final BubbleType type;
  final String? label;
  ChatMessage({required this.text, required this.type, this.label});
}

// Quick action chip definition
class _Chip {
  final IconData icon;
  final String label;
  final String fill;      // text to put in the input field
  const _Chip(this.icon, this.label, this.fill);
}

const _quickChips = [
  _Chip(Icons.auto_awesome_outlined,  "What's new?",   "What's new in my library?"),
  _Chip(Icons.menu_book_outlined,     "Teach me",      "Teach me about "),
  _Chip(Icons.construction_outlined,  "Help me build", "I'm building "),
  _Chip(Icons.notifications_outlined, "Digest",        "Show me my weekly digest"),
];

class ChatScreen extends StatefulWidget {
  final String? sharedUrl;
  final VoidCallback? onSwitchToChat;
  final VoidCallback? onItemSaved;
  final VoidCallback? onSignOut;

  const ChatScreen({super.key, this.sharedUrl, this.onSwitchToChat, this.onItemSaved, this.onSignOut});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller     = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _loading = false;

  // Pending share URL (shows preview card instead of auto-sending)
  String? _pendingUrl;

  @override
  void initState() {
    super.initState();
    _addWelcome();
    _checkDigest();
    if (widget.sharedUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _pendingUrl = widget.sharedUrl),
      );
    }
  }

  @override
  void didUpdateWidget(ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedUrl != null && widget.sharedUrl != oldWidget.sharedUrl) {
      setState(() => _pendingUrl = widget.sharedUrl);
      _scrollToBottom();
    }
  }

  void _addWelcome() {
    _messages.add(ChatMessage(
      text: "Hi! Share a URL to save it, or ask me anything about your knowledge base.\n\n"
          "**Try:** \"teach me about RAG\", \"what haven't I read?\", or mix: "
          "a URL + \"remind me to try this tomorrow\"",
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
            label: "digest",
          ));
        });
        _scrollToBottom();
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _buildHistory() {
    final conversational = _messages
        .where((m) => m.type == BubbleType.user || m.type == BubbleType.assistant)
        .toList();
    final recent = conversational.length > 6
        ? conversational.sublist(conversational.length - 6)
        : conversational;
    return recent
        .map((m) => {
              'role': m.type == BubbleType.user ? 'user' : 'assistant',
              'content': m.text,
            })
        .toList();
  }

  Future<void> _send(String text) async {
    text = text.trim();
    if (text.isEmpty || _loading) return;

    final history = _buildHistory();
    setState(() {
      _messages.add(ChatMessage(text: text, type: BubbleType.user));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final result = await ApiService.sendMessage(text, history: history);
      setState(() {
        _messages.add(ChatMessage(
          text: result.response,
          type: BubbleType.assistant,
          label: result.mode,
        ));
      });
      // Notify parent to refresh Library + Reminders when a URL was saved
      if (result.mode == 'ingest') {
        widget.onItemSaved?.call();
      }
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

  // Save shared URL with optional note
  Future<void> _saveUrl(String url, String note) async {
    setState(() => _pendingUrl = null);
    final payload = note.trim().isEmpty ? url : "$url — ${note.trim()}";
    await _send(payload);
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
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(
          "Cura",
          style: GoogleFonts.inter(
              fontSize: 21, fontWeight: FontWeight.w700, color: _text1, letterSpacing: -0.3),
        ),
        actions: [
          _AppBarIconBtn(
            icon: Icons.bar_chart_outlined,
            onTap: _showStatus,
          ),
          const SizedBox(width: 8),
          _AppBarIconBtn(
            icon: Icons.settings_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(onSignOut: widget.onSignOut),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF232232)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemCount: _messages.length +
                  (_loading ? 1 : 0) +
                  (_pendingUrl != null ? 1 : 0),
              itemBuilder: (_, i) {
                // Quick chips before first message
                if (i == 0) {
                  return Column(
                    children: [
                      _buildQuickChips(),
                      ChatBubble(
                        text: _messages[0].text,
                        type: _messages[0].type,
                        label: _messages[0].label,
                      ),
                    ],
                  );
                }
                // Regular messages
                if (i < _messages.length) {
                  return ChatBubble(
                    text: _messages[i].text,
                    type: _messages[i].type,
                    label: _messages[i].label,
                  );
                }
                // Typing indicator
                if (_loading && i == _messages.length) {
                  return const TypingIndicator();
                }
                // Share card
                if (_pendingUrl != null) {
                  return _ShareCard(
                    url: _pendingUrl!,
                    onSave: (note) => _saveUrl(_pendingUrl!, note),
                    onSkip: () => setState(() => _pendingUrl = null),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  // Quick chips row
  Widget _buildQuickChips() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        children: _quickChips.map((chip) {
          return GestureDetector(
            onTap: () {
              _controller.text = chip.fill;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: chip.fill.length),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 7),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _surface3,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chip.icon, size: 12, color: _text2),
                  const SizedBox(width: 5),
                  Text(
                    chip.label,
                    style: GoogleFonts.inter(
                        fontSize: 11.5, fontWeight: FontWeight.w500, color: _text2),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // Dark-themed input bar
  Widget _buildInputBar() {
    return Container(
      decoration: const BoxDecoration(
        color: _surface2,
        border: Border(top: BorderSide(color: Color(0xFF232232))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 38),
                decoration: BoxDecoration(
                  color: _surface3,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                ),
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: null,
                  minLines: 1,
                  style: GoogleFonts.inter(fontSize: 12.5, color: _text2),
                  decoration: InputDecoration(
                    hintText: "Message Cura…",
                    hintStyle: GoogleFonts.inter(fontSize: 12.5, color: _text3),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    isDense: true,
                    filled: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _loading ? null : _sendFromInput,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _loading ? _text3 : _accent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded, size: 17, color: Colors.white),
              ),
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
          backgroundColor: _surface2,
          title: Text(
            "${result.total} saves",
            style: GoogleFonts.inter(color: _text1, fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: result.byIntent.entries
                .map((e) => ListTile(
                      leading: const Icon(Icons.label_outline, color: _accent),
                      title: Text(e.key,
                          style: GoogleFonts.inter(color: _text1, fontSize: 13)),
                      trailing: Text("${e.value}",
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold, color: _text2)),
                      dense: true,
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close", style: GoogleFonts.inter(color: _accent)),
            )
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
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

// ── App-bar icon button (36px surface-3 circle) ──────────────────────────────
class _AppBarIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _AppBarIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: _surface3,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: _text2),
      ),
    );
  }
}

// ── Share preview card ────────────────────────────────────────────────────────
class _ShareCard extends StatefulWidget {
  final String url;
  final void Function(String note) onSave;
  final VoidCallback onSkip;

  const _ShareCard({required this.url, required this.onSave, required this.onSkip});

  @override
  State<_ShareCard> createState() => _ShareCardState();
}

class _ShareCardState extends State<_ShareCard> {
  final _noteCtrl = TextEditingController();

  String get _domain {
    try {
      return Uri.parse(widget.url).host.replaceFirst('www.', '');
    } catch (_) {
      return widget.url;
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.share_outlined, size: 13, color: _accent),
              const SizedBox(width: 6),
              Text(
                "SHARED URL",
                style: GoogleFonts.inter(
                    fontSize: 10, fontWeight: FontWeight.w700, color: _accent, letterSpacing: 0.6),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // URL row
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _surface3,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.link_rounded, size: 20, color: _accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _domain,
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w700, color: _text1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.url,
                      style: GoogleFonts.inter(fontSize: 11, color: _text2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Optional note
          Text(
            "Add a note (optional)",
            style: GoogleFonts.inter(fontSize: 11, color: _text2),
          ),
          const SizedBox(height: 7),
          Container(
            decoration: BoxDecoration(
              color: _surface3,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: TextField(
              controller: _noteCtrl,
              style: GoogleFonts.inter(fontSize: 12, color: _text2),
              decoration: InputDecoration(
                hintText: 'e.g. "for my next project"',
                hintStyle: GoogleFonts.inter(fontSize: 12, color: _text3),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                filled: false,
              ),
            ),
          ),
          const SizedBox(height: 11),
          // Buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => widget.onSave(_noteCtrl.text),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "Save to Cura",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                          fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: widget.onSkip,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _surface4,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "Skip",
                    style: GoogleFonts.inter(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: _text2),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
