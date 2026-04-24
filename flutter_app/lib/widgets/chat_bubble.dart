import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

enum BubbleType { user, assistant, system }

class ChatBubble extends StatelessWidget {
  final String text;
  final BubbleType type;
  final String? label;

  const ChatBubble({super.key, required this.text, required this.type, this.label});

  @override
  Widget build(BuildContext context) {
    final isUser = type == BubbleType.user;
    final isSystem = type == BubbleType.system;
    final colors = Theme.of(context).colorScheme;

    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (label != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 2, left: 4, right: 4),
                child: Text(label!, style: TextStyle(fontSize: 11, color: colors.outline)),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? colors.primary : colors.surfaceVariant,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: isUser
                  ? Text(text, style: TextStyle(color: colors.onPrimary))
                  : MarkdownBody(
                      data: text,
                      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
