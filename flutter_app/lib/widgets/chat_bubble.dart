import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

enum BubbleType { user, assistant, system }

// ── Cura avatar (gradient circle with connected-nodes icon) ─────────────────
class CuraAvatar extends StatelessWidget {
  final double size;
  const CuraAvatar({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6750A4), Color(0xFFA78BFA)],
        ),
      ),
      child: CustomPaint(
        painter: _CuraNodesPainter(),
      ),
    );
  }
}

class _CuraNodesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 - 1;
    // satellite positions
    final satellites = [
      Offset(cx - 6, cy - 5),
      Offset(cx + 6, cy - 5),
      Offset(cx - 6, cy + 5),
      Offset(cx + 6, cy + 5),
    ];
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.45)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    for (final s in satellites) {
      canvas.drawLine(Offset(cx, cy), s, linePaint);
    }
    final satPaint = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..style = PaintingStyle.fill;
    for (final s in satellites) {
      canvas.drawCircle(s, 2.2, satPaint);
    }
    canvas.drawCircle(Offset(cx, cy), 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Chat bubble ──────────────────────────────────────────────────────────────
class ChatBubble extends StatelessWidget {
  final String text;
  final BubbleType type;
  final String? label;

  const ChatBubble({super.key, required this.text, required this.type, this.label});

  @override
  Widget build(BuildContext context) {
    final isUser = type == BubbleType.user;
    final isSystem = type == BubbleType.system;

    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF262537),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9B9AAE)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Cura avatar (left side of assistant bubbles)
          if (!isUser) ...[
            const CuraAvatar(size: 28),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // Message bubble
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF7C6DB5)   // accent-dim
                          : const Color(0xFF262537),  // surface-3
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                    ),
                    child: isUser
                        ? Text(
                            text,
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: Colors.white,
                              height: 1.55,
                            ),
                          )
                        : MarkdownBody(
                            data: text,
                            styleSheet: MarkdownStyleSheet(
                              p: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: const Color(0xFFEDECF4),
                                height: 1.55,
                              ),
                              strong: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFA78BFA), // accent
                                height: 1.55,
                              ),
                              em: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontStyle: FontStyle.italic,
                                color: const Color(0xFF9B9AAE),
                                height: 1.55,
                              ),
                              listBullet: GoogleFonts.inter(
                                fontSize: 12.5,
                                color: const Color(0xFFEDECF4),
                                height: 1.55,
                              ),
                              code: GoogleFonts.jetBrainsMono(
                                fontSize: 11.5,
                                color: const Color(0xFFA78BFA),
                                backgroundColor: const Color(0xFF1E1D2C),
                              ),
                            ),
                          ),
                  ),

                  // Mode tag (e.g. "learn", "build") below assistant bubble
                  if (!isUser && label != null) ...[
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x1AA78BFA),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        label!.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFA78BFA),
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Spacer to mirror avatar on user side
          if (isUser) const SizedBox(width: 35),
        ],
      ),
    );
  }
}

// ── Animated typing indicator ────────────────────────────────────────────────
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _anims;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      final c = AnimationController(
        duration: const Duration(milliseconds: 1200),
        vsync: this,
      );
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) c.repeat();
      });
      return c;
    });
    _anims = _controllers
        .map((c) => TweenSequence([
              TweenSequenceItem(tween: Tween(begin: 0.0, end: -5.0), weight: 30),
              TweenSequenceItem(tween: Tween(begin: -5.0, end: 0.0), weight: 30),
              TweenSequenceItem(tween: ConstantTween(0.0), weight: 40),
            ]).animate(c))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const CuraAvatar(size: 28),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF262537),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                return AnimatedBuilder(
                  animation: _anims[i],
                  builder: (_, __) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      transform: Matrix4.translationValues(0, _anims[i].value, 0),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF5C5B72),
                        ),
                      ),
                    );
                  },
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
