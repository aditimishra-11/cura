import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

// Design palette
const _bg         = Color(0xFF0F0E17);
const _surface2   = Color(0xFF1E1D2C);
const _surface3   = Color(0xFF262537);
const _borderSoft = Color(0xFF232232);
const _border     = Color(0xFF2C2B3D);
const _text1      = Color(0xFFEDECF4);
const _text2      = Color(0xFF9B9AAE);
const _text3      = Color(0xFF5C5B72);
const _accent     = Color(0xFFA78BFA);
const _inspire    = Color(0xFFFBBF24);
const _red        = Color(0xFFF87171);
const _redBg      = Color(0x0AF87171);   // very faint tint
const _green      = Color(0xFF34D399);
const _greenBg    = Color(0x1A34D399);

class RemindersScreen extends StatefulWidget {
  final int refreshTrigger;
  const RemindersScreen({super.key, this.refreshTrigger = 0});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  List<SavedItem> _reminders = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RemindersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await ApiService.fetchReminders();
      setState(() => _reminders = items);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load reminders")),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime? _parseDt(String? iso) {
    if (iso == null) return null;
    try {
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        title: Text(
          "Reminders",
          style: GoogleFonts.inter(
              fontSize: 21, fontWeight: FontWeight.w700,
              color: _text1, letterSpacing: -0.3),
        ),
        actions: [
          Container(
            width: 36, height: 36,
            margin: const EdgeInsets.only(right: 12),
            decoration: const BoxDecoration(
                color: _surface3, shape: BoxShape.circle),
            child: IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: _text2),
              onPressed: _load,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _borderSoft),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : _reminders.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: _accent,
                  backgroundColor: _surface2,
                  onRefresh: _load,
                  child: _buildList(),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_none_rounded, size: 64, color: _text3),
          const SizedBox(height: 16),
          Text("No reminders set",
              style: GoogleFonts.inter(
                  fontSize: 16, fontWeight: FontWeight.w600, color: _text2)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Save a URL and add "remind me tomorrow" to set a reminder',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12, color: _text3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final now       = DateTime.now();
    final todayEnd  = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final weekEnd   = todayEnd.add(const Duration(days: 6));

    final overdue = _reminders.where((r) {
      if (r.reminderSent) return false;
      final dt = _parseDt(r.remindAt);
      return dt != null && dt.isBefore(now);
    }).toList();

    final today = _reminders.where((r) {
      if (r.reminderSent) return false;
      final dt = _parseDt(r.remindAt);
      return dt != null && !dt.isBefore(now) && !dt.isAfter(todayEnd);
    }).toList();

    final thisWeek = _reminders.where((r) {
      if (r.reminderSent) return false;
      final dt = _parseDt(r.remindAt);
      return dt != null && dt.isAfter(todayEnd) && !dt.isAfter(weekEnd);
    }).toList();

    final later = _reminders.where((r) {
      if (r.reminderSent) return false;
      final dt = _parseDt(r.remindAt);
      return dt != null && dt.isAfter(weekEnd);
    }).toList();

    final sent = _reminders.where((r) => r.reminderSent).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 24),
      children: [
        if (overdue.isNotEmpty) ...[
          _GroupLabel(
              label: "Overdue",
              icon: Icons.error_outline_rounded,
              color: _red),
          const SizedBox(height: 4),
          ...overdue.map((r) => _ReminderCard(
              item: r, group: _ReminderGroup.overdue,
              onDone: _load)),
        ],
        if (today.isNotEmpty) ...[
          const SizedBox(height: 4),
          _GroupLabel(
              label: "Today",
              icon: Icons.access_time_rounded,
              color: _inspire),
          const SizedBox(height: 4),
          ...today.map((r) => _ReminderCard(
              item: r, group: _ReminderGroup.today,
              onDone: _load)),
        ],
        if (thisWeek.isNotEmpty) ...[
          const SizedBox(height: 4),
          _GroupLabel(
              label: "This Week",
              icon: Icons.bookmark_border_rounded,
              color: _accent),
          const SizedBox(height: 4),
          ...thisWeek.map((r) => _ReminderCard(
              item: r, group: _ReminderGroup.thisWeek,
              onDone: _load)),
        ],
        if (later.isNotEmpty) ...[
          const SizedBox(height: 4),
          _GroupLabel(
              label: "Later",
              icon: Icons.access_time_outlined,
              color: _text3),
          const SizedBox(height: 4),
          ...later.map((r) => _ReminderCard(
              item: r, group: _ReminderGroup.later,
              onDone: _load)),
        ],
        if (sent.isNotEmpty) ...[
          const SizedBox(height: 4),
          _GroupLabel(
              label: "Sent",
              icon: Icons.check_circle_outline,
              color: _text3),
          const SizedBox(height: 4),
          ...sent.map((r) => _ReminderCard(
              item: r, group: _ReminderGroup.sent,
              onDone: _load)),
        ],
      ],
    );
  }
}

// ── Group section label ───────────────────────────────────────────────────────
class _GroupLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _GroupLabel({required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reminder group enum ────────────────────────────────────────────────────────
enum _ReminderGroup { overdue, today, thisWeek, later, sent }

// ── Reminder card (left-border style) ────────────────────────────────────────
class _ReminderCard extends StatelessWidget {
  final SavedItem item;
  final _ReminderGroup group;
  final VoidCallback onDone;

  const _ReminderCard({
    required this.item,
    required this.group,
    required this.onDone,
  });

  Color get _borderColor {
    switch (group) {
      case _ReminderGroup.overdue:  return _red;
      case _ReminderGroup.today:    return _inspire;
      case _ReminderGroup.thisWeek: return _accent;
      case _ReminderGroup.later:    return _border;
      case _ReminderGroup.sent:     return _border;
    }
  }

  Color get _iconBg {
    switch (group) {
      case _ReminderGroup.overdue:  return const Color(0x1AF87171);
      case _ReminderGroup.today:    return const Color(0x1AFBBF24);
      case _ReminderGroup.thisWeek: return const Color(0x1AA78BFA);
      case _ReminderGroup.later:    return _surface3;
      case _ReminderGroup.sent:     return _surface3;
    }
  }

  Color get _iconColor {
    switch (group) {
      case _ReminderGroup.overdue:  return _red;
      case _ReminderGroup.today:    return _inspire;
      case _ReminderGroup.thisWeek: return _accent;
      case _ReminderGroup.later:    return _text3;
      case _ReminderGroup.sent:     return _text3;
    }
  }

  Color get _timeColor {
    switch (group) {
      case _ReminderGroup.overdue:  return _red;
      case _ReminderGroup.today:    return _inspire;
      case _ReminderGroup.thisWeek: return _accent;
      case _ReminderGroup.later:    return _text3;
      case _ReminderGroup.sent:     return _text3;
    }
  }

  IconData get _iconData {
    switch (group) {
      case _ReminderGroup.overdue:  return Icons.error_outline_rounded;
      case _ReminderGroup.today:    return Icons.access_time_rounded;
      case _ReminderGroup.thisWeek: return Icons.notifications_outlined;
      case _ReminderGroup.later:    return Icons.schedule_outlined;
      case _ReminderGroup.sent:     return Icons.check_circle_outline;
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt  = DateTime.parse(iso).toLocal();
      final now = DateTime.now();

      if (group == _ReminderGroup.sent) return "Reminder sent";

      final diff = dt.difference(now);
      if (diff.inSeconds < 0) {
        final past = now.difference(dt);
        if (past.inMinutes < 60) return "${past.inMinutes}m overdue";
        if (past.inHours < 24)   return "${past.inHours}h overdue";
        return "${past.inDays}d overdue";
      }

      if (diff.inMinutes < 60) return "in ${diff.inMinutes}m";

      // Calendar-day comparison (avoids "Today" when reminder is actually tomorrow)
      final today = DateTime(now.year, now.month, now.day);
      final dtDay = DateTime(dt.year, dt.month, dt.day);
      final daysDiff = dtDay.difference(today).inDays;

      if (daysDiff == 0) return "Today · ${_hm(dt)}";
      if (daysDiff == 1) return "Tomorrow · ${_hm(dt)}";
      if (daysDiff < 7) {
        const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
        return "${days[dt.weekday - 1]}, ${_hm(dt)}";
      }
      return _shortDate(dt);
    } catch (_) {
      return iso ?? '';
    }
  }

  String _hm(DateTime dt) =>
      "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";

  String _shortDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    return "${dt.day} ${months[dt.month - 1]}";
  }

  Future<void> _openUrl() async {
    final uri = Uri.tryParse(item.url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isSent = group == _ReminderGroup.sent;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: group == _ReminderGroup.overdue
            ? _redBg
            : _surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderSoft),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Colored left border
              Container(width: 3, color: _borderColor),
              // Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                  child: Row(
                    children: [
                      // Icon square (34×34)
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _iconBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_iconData, size: 16, color: _iconColor),
                      ),
                      const SizedBox(width: 11),
                      // Text info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isSent ? _text2 : _text1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatTime(item.remindAt),
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: _timeColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Done button (green chip) or Open button
                      if (!isSent)
                        GestureDetector(
                          onTap: () async {
                            await _openUrl();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _greenBg,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check,
                                    size: 11, color: _green),
                                const SizedBox(width: 4),
                                Text(
                                  "Done",
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: _green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: _openUrl,
                          child: Icon(Icons.open_in_new,
                              size: 16, color: _text3),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
