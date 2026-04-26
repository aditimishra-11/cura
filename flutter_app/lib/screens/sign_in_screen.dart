import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';

// ignore: avoid_print
void logger(String msg) => developer.log(msg, name: 'SignIn');

const _bg      = Color(0xFF0F0E17);
const _surface = Color(0xFF1E1D2C);
const _surface3= Color(0xFF262537);
const _border  = Color(0xFF2C2B3D);
const _text1   = Color(0xFFEDECF4);
const _text2   = Color(0xFF9B9AAE);
const _text3   = Color(0xFF5C5B72);
const _accent  = Color(0xFFA78BFA);

final _googleSignIn = GoogleSignIn(
  scopes: ['email', 'https://www.googleapis.com/auth/calendar.events'],
  serverClientId: AppConfig.googleWebClientId.isNotEmpty
      ? AppConfig.googleWebClientId
      : null,
);

class SignInScreen extends StatefulWidget {
  final VoidCallback onSignedIn;
  const SignInScreen({super.key, required this.onSignedIn});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() => _loading = false);
        return;
      }

      final serverAuthCode = account.serverAuthCode;

      if (serverAuthCode != null) {
        try {
          // Exchange code with backend — stores calendar tokens + saves email
          await ApiService.connectGoogle(
            serverAuthCode: serverAuthCode,
            email: account.email,
          );
        } catch (calErr) {
          // Calendar token exchange failed (e.g. no refresh_token, bad request)
          // Still allow sign-in — just save the email so the app works
          logger('Calendar token exchange failed: $calErr');
          await ApiService.setUserEmail(account.email);
        }
      } else {
        await ApiService.setUserEmail(account.email);
      }

      // Re-register FCM token with this user's email
      await NotificationService.reRegister();

      widget.onSignedIn();
    } catch (e) {
      setState(() {
        _loading = false;
        _error   = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // App icon
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _border),
                ),
                child: const Icon(Icons.hub_outlined, size: 44, color: _accent),
              ),
              const SizedBox(height: 20),

              // App name
              Text(
                'Cura',
                style: GoogleFonts.inter(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: _text1,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your personal knowledge assistant',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: _text2),
              ),

              const Spacer(flex: 2),

              // Feature bullets
              ...[
                ('💾', 'Save any URL with AI summaries'),
                ('⏰', 'Set reminders in plain language'),
                ('🔍', 'Ask questions about what you\'ve saved'),
              ].map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Text(item.$1, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 14),
                    Text(
                      item.$2,
                      style: GoogleFonts.inter(fontSize: 13.5, color: _text2),
                    ),
                  ],
                ),
              )),

              const Spacer(flex: 2),

              // Sign-in button
              if (_loading)
                const CircularProgressIndicator(color: _accent)
              else
                SizedBox(
                  width: double.infinity,
                  child: _GoogleSignInButton(onTap: _signIn),
                ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0x1AF87171),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: const Color(0xFFF87171)),
                  ),
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GoogleSignInButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _surface3,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Google G logo colours
            _GIcon(),
            const SizedBox(width: 12),
            Text(
              'Continue with Google',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _text1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.width / 2;
    final r = size.width / 2;

    // Simplified coloured circle segments
    final colors = [
      (0.0,   90.0,  const Color(0xFF4285F4)), // blue
      (90.0,  180.0, const Color(0xFF34A853)), // green
      (180.0, 270.0, const Color(0xFFFBBC05)), // yellow
      (270.0, 360.0, const Color(0xFFEA4335)), // red
    ];
    for (final seg in colors) {
      final paint = Paint()..color = seg.$3 ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(c, c)
        ..arcTo(
          Rect.fromCircle(center: Offset(c, c), radius: r),
          seg.$1 * 3.14159 / 180,
          (seg.$2 - seg.$1) * 3.14159 / 180,
          false,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
    // White inner circle
    canvas.drawCircle(
      Offset(c, c), r * 0.55,
      Paint()..color = _surface3,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
