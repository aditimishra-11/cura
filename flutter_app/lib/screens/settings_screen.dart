import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config.dart';
import '../services/api_service.dart';

final _googleSignIn = GoogleSignIn(
  scopes: [
    'email',
    'https://www.googleapis.com/auth/calendar.events',
  ],
  serverClientId: AppConfig.googleWebClientId.isNotEmpty
      ? AppConfig.googleWebClientId
      : null,
);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlController = TextEditingController();
  bool _urlSaved = false;

  // Google Calendar state
  bool _googleLoading = true;
  bool _googleConnected = false;
  String? _googleEmail;
  String? _googleError;

  @override
  void initState() {
    super.initState();
    ApiService.getBaseUrl().then((url) {
      if (mounted) setState(() => _urlController.text = url);
    });
    _loadGoogleStatus();
  }

  Future<void> _loadGoogleStatus() async {
    setState(() { _googleLoading = true; _googleError = null; });
    try {
      final status = await ApiService.googleStatus();
      if (mounted) {
        setState(() {
          _googleConnected = status.connected;
          _googleEmail = status.email;
          _googleLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _googleLoading = false; });
    }
  }

  Future<void> _saveUrl() async {
    await ApiService.setBaseUrl(_urlController.text.trim());
    setState(() => _urlSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _urlSaved = false);
    });
  }

  Future<void> _connectGoogle() async {
    setState(() { _googleLoading = true; _googleError = null; });
    try {
      // Trigger Google sign-in to obtain serverAuthCode
      final account = await _googleSignIn.signIn();
      if (account == null) {
        setState(() { _googleLoading = false; });
        return; // user cancelled
      }

      final auth = await account.authentication;
      final serverAuthCode = account.serverAuthCode;

      if (serverAuthCode == null) {
        setState(() {
          _googleLoading = false;
          _googleError = 'Could not get server auth code. Make sure the OAuth client ID is configured correctly.';
        });
        return;
      }

      final status = await ApiService.connectGoogle(
        serverAuthCode: serverAuthCode,
        email: account.email,
      );

      if (mounted) {
        setState(() {
          _googleConnected = status.connected;
          _googleEmail = status.email ?? account.email;
          _googleLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _googleLoading = false;
          _googleError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _disconnectGoogle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Google Calendar?'),
        content: const Text(
          'Future reminders will no longer create calendar events. Existing events are not deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() { _googleLoading = true; _googleError = null; });
    try {
      await ApiService.disconnectGoogle();
      await _googleSignIn.signOut();
      if (mounted) {
        setState(() {
          _googleConnected = false;
          _googleEmail = null;
          _googleLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _googleLoading = false;
          _googleError = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── API Server URL ─────────────────────────────────────────────
            Text('API Server URL',
                style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'https://your-render-app.onrender.com',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 8),
            Text(
              'For local testing on Android emulator use http://10.0.2.2:8000\n'
              'For Render deploy use your Render URL.',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saveUrl,
                child: Text(_urlSaved ? 'Saved ✓' : 'Save'),
              ),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 20),

            // ── Google Calendar ────────────────────────────────────────────
            Row(
              children: [
                Image.network(
                  'https://upload.wikimedia.org/wikipedia/commons/a/a5/Google_Calendar_icon_%282020%29.svg',
                  width: 24,
                  height: 24,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.calendar_month, size: 24),
                ),
                const SizedBox(width: 10),
                Text(
                  'Google Calendar',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: cs.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Connect your Google Calendar so reminders also create calendar events.',
              style: TextStyle(fontSize: 13, color: cs.outline),
            ),
            const SizedBox(height: 16),

            if (_googleLoading)
              const Center(child: CircularProgressIndicator())
            else if (_googleConnected) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Connected',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onPrimaryContainer)),
                          if (_googleEmail != null)
                            Text(_googleEmail!,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: cs.onPrimaryContainer)),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: _disconnectGoogle,
                      child: Text('Disconnect',
                          style: TextStyle(color: cs.error)),
                    ),
                  ],
                ),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Connect Google Calendar'),
                  onPressed: _connectGoogle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],

            if (_googleError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: cs.error, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_googleError!,
                          style:
                              TextStyle(color: cs.onErrorContainer, fontSize: 13)),
                    ),
                  ],
                ),
              ),
            ],

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
