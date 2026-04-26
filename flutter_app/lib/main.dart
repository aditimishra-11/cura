import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'screens/chat_screen.dart';
import 'screens/library_screen.dart';
import 'screens/reminders_screen.dart';
import 'services/notification_service.dart';
import 'firebase_options.dart';

// ── Design palette ──────────────────────────────────────────────────────────
const kBg         = Color(0xFF0F0E17);
const kSurface2   = Color(0xFF1E1D2C);
const kSurface3   = Color(0xFF262537);
const kSurface4   = Color(0xFF2E2D40);
const kBorder     = Color(0xFF2C2B3D);
const kBorderSoft = Color(0xFF232232);
const kText1      = Color(0xFFEDECF4);
const kText2      = Color(0xFF9B9AAE);
const kText3      = Color(0xFF5C5B72);
const kAccent     = Color(0xFFA78BFA);
const kAccentDim  = Color(0xFF7C6DB5);
const kAccentMuted = Color(0x1AA78BFA);   // rgba(167,139,250,.10)
const kRed        = Color(0xFFF87171);
const kRedBg      = Color(0x1AF87171);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kSurface2,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationService.init();
  runApp(const KnowledgeApp());
}

class KnowledgeApp extends StatelessWidget {
  const KnowledgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme);

    return MaterialApp(
      title: 'Cura',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        colorScheme: const ColorScheme.dark(
          background:        kBg,
          surface:           kSurface2,
          surfaceVariant:    kSurface3,
          primary:           kAccent,
          onPrimary:         Colors.white,
          primaryContainer:  kAccentDim,
          onPrimaryContainer: kText1,
          secondary:         kAccentDim,
          onSecondary:       Colors.white,
          onBackground:      kText1,
          onSurface:         kText1,
          onSurfaceVariant:  kText2,
          outline:           kText3,
          outlineVariant:    kBorder,
          error:             kRed,
          errorContainer:    kRedBg,
          onError:           Colors.white,
        ),
        scaffoldBackgroundColor: kBg,
        textTheme: textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: kBg,
          foregroundColor: kText1,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: kText1,
            letterSpacing: -0.3,
          ),
          iconTheme: const IconThemeData(color: kText2),
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: kSurface2,
        ),
        cardTheme: CardTheme(
          color: kSurface2,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kBorderSoft),
          ),
          elevation: 0,
        ),
        dividerColor: kBorderSoft,
        dividerTheme: const DividerThemeData(color: kBorderSoft, thickness: 1),
        chipTheme: ChipThemeData(
          backgroundColor: kSurface3,
          selectedColor: kAccentMuted,
          labelStyle: GoogleFonts.inter(color: kText2, fontSize: 11.5, fontWeight: FontWeight.w500),
          side: const BorderSide(color: kBorder),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: const StadiumBorder(),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: kSurface4,
          contentTextStyle: TextStyle(color: kText1),
        ),
        dialogTheme: const DialogTheme(
          backgroundColor: kSurface2,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface3,
          hintStyle: GoogleFonts.inter(color: kText3, fontSize: 12.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: kAccent),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: kSurface2,
          surfaceTintColor: Colors.transparent,
          modalBackgroundColor: kSurface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
        ),
      ),
      home: const AppEntry(),
    );
  }
}

// ── App entry — handles share intent ────────────────────────────────────────
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
    return MainShell(key: ValueKey(_sharedUrl), sharedUrl: _sharedUrl);
  }
}

// ── Main shell — custom bottom nav + IndexedStack ────────────────────────────
class MainShell extends StatefulWidget {
  final String? sharedUrl;
  const MainShell({super.key, this.sharedUrl});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  int _libraryRefresh = 0;
  int _remindersRefresh = 0;

  @override
  void didUpdateWidget(MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sharedUrl != null && widget.sharedUrl != oldWidget.sharedUrl) {
      setState(() => _currentIndex = 0);
    }
  }

  void switchToChat() => setState(() => _currentIndex = 0);

  /// Called by ChatScreen after a successful URL save so Library/Reminders
  /// pick up the new item without requiring the user to manually switch tabs.
  void onItemSaved() {
    setState(() {
      _libraryRefresh++;
      _remindersRefresh++;
    });
  }

  void _onTabTap(int i) {
    setState(() {
      _currentIndex = i;
      // Always refresh data when the user navigates to Library or Reminders
      if (i == 1) _libraryRefresh++;
      if (i == 2) _remindersRefresh++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ChatScreen(
            sharedUrl: widget.sharedUrl,
            onSwitchToChat: switchToChat,
            onItemSaved: onItemSaved,
          ),
          LibraryScreen(refreshTrigger: _libraryRefresh),
          RemindersScreen(refreshTrigger: _remindersRefresh),
        ],
      ),
      bottomNavigationBar: _CuraBottomNav(
        currentIndex: _currentIndex,
        onTap: _onTabTap,
      ),
    );
  }
}

// ── Custom pill-style bottom nav ─────────────────────────────────────────────
class _CuraBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _CuraBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68 + MediaQuery.of(context).padding.bottom,
      decoration: const BoxDecoration(
        color: kSurface2,
        border: Border(top: BorderSide(color: kBorderSoft, width: 1)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Row(
        children: [
          _NavItem(
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_rounded,
            label: 'Chat',
            active: currentIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            icon: Icons.library_books_outlined,
            activeIcon: Icons.library_books,
            label: 'Library',
            active: currentIndex == 1,
            onTap: () => onTap(1),
          ),
          _NavItem(
            icon: Icons.notifications_outlined,
            activeIcon: Icons.notifications_rounded,
            label: 'Reminders',
            active: currentIndex == 2,
            onTap: () => onTap(2),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? kAccent : kText3;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 52,
              height: 28,
              decoration: BoxDecoration(
                color: active ? kAccentMuted : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(active ? activeIcon : icon, size: 22, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
