import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Reminders"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _reminders.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
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
          Icon(Icons.alarm_off_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            "No reminders set",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'When you save a URL, add "remind me tomorrow" to set a reminder',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    final now = DateTime.now();
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

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

    final upcoming = _reminders.where((r) {
      if (r.reminderSent) return false;
      final dt = _parseDt(r.remindAt);
      return dt != null && dt.isAfter(todayEnd);
    }).toList();

    final sent = _reminders.where((r) => r.reminderSent).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (overdue.isNotEmpty) ...[
          _sectionHeader(context, "Overdue", Icons.warning_amber_rounded,
              Theme.of(context).colorScheme.error),
          ...overdue.map((r) => _ReminderCard(item: r, isOverdue: true)),
        ],
        if (today.isNotEmpty) ...[
          _sectionHeader(context, "Today", Icons.today_outlined,
              Theme.of(context).colorScheme.primary),
          ...today.map((r) => _ReminderCard(item: r)),
        ],
        if (upcoming.isNotEmpty) ...[
          _sectionHeader(context, "Upcoming", Icons.event_outlined,
              Theme.of(context).colorScheme.secondary),
          ...upcoming.map((r) => _ReminderCard(item: r)),
        ],
        if (sent.isNotEmpty) ...[
          _sectionHeader(context, "Sent", Icons.check_circle_outline,
              Theme.of(context).colorScheme.outline),
          ...sent.map((r) => _ReminderCard(item: r, isSent: true)),
        ],
      ],
    );
  }

  Widget _sectionHeader(
      BuildContext context, String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseDt(String? iso) {
    if (iso == null) return null;
    try {
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return null;
    }
  }
}

class _ReminderCard extends StatelessWidget {
  final SavedItem item;
  final bool isOverdue;
  final bool isSent;

  const _ReminderCard({
    required this.item,
    this.isOverdue = false,
    this.isSent = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final timeStr = _formatRemindAt(item.remindAt);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: isOverdue
          ? scheme.errorContainer.withOpacity(0.3)
          : isSent
              ? scheme.surfaceVariant.withOpacity(0.5)
              : scheme.surfaceVariant,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(
          isOverdue
              ? Icons.warning_amber_rounded
              : isSent
                  ? Icons.check_circle_outline
                  : Icons.alarm,
          color: isOverdue
              ? scheme.error
              : isSent
                  ? scheme.outline
                  : scheme.primary,
        ),
        title: Text(
          item.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: isSent ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.userNote != null) ...[
              const SizedBox(height: 2),
              Text(
                item.userNote!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isOverdue
                    ? scheme.error
                    : isSent
                        ? scheme.outline
                        : scheme.primary,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.open_in_new, size: 18, color: scheme.outline),
          onPressed: () async {
            final uri = Uri.tryParse(item.url);
            if (uri != null) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      ),
    );
  }

  String _formatRemindAt(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = dt.difference(now);

      if (diff.inSeconds < 0) {
        final past = now.difference(dt);
        if (past.inMinutes < 60) return "${past.inMinutes}m overdue";
        if (past.inHours < 24) return "${past.inHours}h overdue";
        return "${past.inDays}d overdue";
      }

      if (diff.inMinutes < 60) return "in ${diff.inMinutes}m";
      if (diff.inHours < 24) return "in ${diff.inHours}h";
      if (diff.inDays == 1) return "tomorrow at ${_timeStr(dt)}";
      return "${dt.day}/${dt.month} at ${_timeStr(dt)}";
    } catch (_) {
      return iso ?? '';
    }
  }

  String _timeStr(DateTime dt) =>
      "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
}
