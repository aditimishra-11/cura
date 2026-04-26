import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';

const _bg      = Color(0xFF0F0E17);
const _surface2= Color(0xFF1E1D2C);
const _surface3= Color(0xFF262537);
const _border  = Color(0xFF2C2B3D);
const _text1   = Color(0xFFEDECF4);
const _text2   = Color(0xFF9B9AAE);
const _text3   = Color(0xFF5C5B72);
const _accent  = Color(0xFFA78BFA);
const _red     = Color(0xFFF87171);
const _redBg   = Color(0x1AF87171);

final _googleSignIn = GoogleSignIn(scopes: ['email']);

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSignOut;
  const SettingsScreen({super.key, this.onSignOut});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _urlSaved = false;
  String? _userEmail;
  bool _googleConnected = false;
  bool _calLoading = true;

  @override
  void initState() {
    super.initState();
    ApiService.getBaseUrl().then((url) {
      if (mounted) setState(() => _urlController.text = url);
    });
    ApiService.getUserEmail().then((email) {
      setState(() => _userEmail = email);
      if (email != null) _loadCalendarStatus(email);
    });
  }

  Future<void> _loadCalendarStatus(String email) async {
    setState(() => _calLoading = true);
    try {
      final status = await ApiService.googleStatus();
      if (mounted) setState(() { _googleConnected = status.connected; _calLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _calLoading = false);
    }
  }

  Future<void> _saveUrl() async {
    await ApiService.setBaseUrl(_urlController.text.trim());
    setState(() => _urlSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _urlSaved = false);
    });
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface2,
        title: Text('Sign out?', style: TextStyle(color: _text1)),
        content: Text(
          'You will need to sign in again to use Cura.',
          style: TextStyle(color: _text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: _accent)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: _red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ApiService.disconnectGoogle();
    } catch (_) {
      // Clear locally even if backend call fails
      await ApiService.clearUserEmail();
    }
    await _googleSignIn.signOut();

    widget.onSignOut?.call();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text('Settings',
            style: TextStyle(color: _text1, fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: _text2),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF232232)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Account ───────────────────────────────────────────────────
            Text('Account',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: _text1, fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                        color: _surface3, shape: BoxShape.circle),
                    child: const Icon(Icons.person, color: _accent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Signed in',
                            style: GoogleFonts.inter(
                                fontSize: 12, color: _text3,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(_userEmail ?? '—',
                            style: GoogleFonts.inter(
                                fontSize: 13.5, color: _text1,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Google Calendar status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month,
                      size: 18,
                      color: _calLoading
                          ? _text3
                          : _googleConnected ? _accent : _text3),
                  const SizedBox(width: 10),
                  Text(
                    _calLoading
                        ? 'Checking Calendar…'
                        : _googleConnected
                            ? 'Google Calendar connected'
                            : 'Google Calendar not connected',
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _calLoading
                            ? _text3
                            : _googleConnected ? _accent : _text3),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Sign Out'),
                onPressed: _signOut,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: const BorderSide(color: _red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            const SizedBox(height: 32),
            const Divider(color: Color(0xFF232232)),
            const SizedBox(height: 20),

            // ── API Server URL ─────────────────────────────────────────────
            Text('API Server URL',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: _text1, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              style: GoogleFonts.inter(fontSize: 13, color: _text2),
              decoration: InputDecoration(
                hintText: 'https://your-render-app.onrender.com',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _accent)),
                filled: true,
                fillColor: _surface3,
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            Text(
              'For local testing use http://10.0.2.2:8000',
              style: GoogleFonts.inter(fontSize: 11, color: _text3),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saveUrl,
                child: Text(_urlSaved ? 'Saved ✓' : 'Save'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}
