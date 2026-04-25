import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';

const _intents = ['all', 'learn', 'build', 'inspire', 'share', 'reference'];

const _intentColors = {
  'learn': Color(0xFF818CF8),
  'build': Color(0xFF34D399),
  'inspire': Color(0xFFFBBF24),
  'share': Color(0xFF60A5FA),
  'reference': Color(0xFF6EE7B7),
};

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedIntent = 'all';
  List<SavedItem> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _pageSize = 20;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_loading &&
        _hasMore) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    if (reset) {
      _offset = 0;
      _hasMore = true;
    }

    try {
      final result = await ApiService.fetchItems(
        limit: _pageSize,
        offset: _offset,
        intent: _selectedIntent == 'all' ? null : _selectedIntent,
      );
      setState(() {
        if (reset) _items = result.items;
        else _items.addAll(result.items);
        _offset += result.count;
        _hasMore = result.count == _pageSize;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't load library")),
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
        title: Text(_items.isEmpty ? "Library" : "Library · ${_items.length}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _load(reset: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Intent filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: _intents.map((intent) {
                final selected = _selectedIntent == intent;
                final color = intent == 'all'
                    ? Theme.of(context).colorScheme.primary
                    : (_intentColors[intent] ?? Theme.of(context).colorScheme.primary);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(intent),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _selectedIntent = intent);
                      _load(reset: true);
                    },
                    selectedColor: color.withOpacity(0.2),
                    checkmarkColor: color,
                    labelStyle: TextStyle(
                      color: selected ? color : null,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    side: BorderSide(
                      color: selected ? color : Colors.transparent,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _items.isEmpty && !_loading
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    child: ListView.separated(
                      controller: _scrollController,
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                      itemBuilder: (_, i) {
                        if (i == _items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _LibraryCard(
                          item: _items[i],
                          onTap: () => _showDetail(_items[i]),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_books_outlined,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            "Nothing saved yet",
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            "Share a URL into Cura or send one in Chat",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }

  void _showDetail(SavedItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ItemDetailSheet(item: item),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final SavedItem item;
  final VoidCallback onTap;

  const _LibraryCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = _intentColors[item.intent] ?? Theme.of(context).colorScheme.primary;
    final date = _formatDate(item.createdAt);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        item.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.summary != null) ...[
            const SizedBox(height: 4),
            Text(
              item.summary!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.intent,
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                date,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              if (item.remindAt != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.alarm, size: 13, color: Theme.of(context).colorScheme.outline),
              ],
            ],
          ),
        ],
      ),
      trailing: const Icon(Icons.chevron_right, size: 18),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return "today";
      if (diff.inDays == 1) return "yesterday";
      if (diff.inDays < 7) return "${diff.inDays}d ago";
      if (diff.inDays < 30) return "${(diff.inDays / 7).floor()}w ago";
      return "${(diff.inDays / 30).floor()}mo ago";
    } catch (_) {
      return '';
    }
  }
}

class _ItemDetailSheet extends StatelessWidget {
  final SavedItem item;

  const _ItemDetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = _intentColors[item.intent] ?? Theme.of(context).colorScheme.primary;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Intent chip
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  item.intent,
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700),
                ),
              ),
              if (item.source != null) ...[
                const SizedBox(width: 8),
                Text(
                  item.source!,
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            item.displayTitle,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // URL tap-to-open
          GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(item.url);
              if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Text(
              item.url,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 16),

          // Summary
          if (item.summary != null) ...[
            Text(
              "Summary",
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 6),
            MarkdownBody(data: item.summary!),
            const SizedBox(height: 16),
          ],

          // Tags
          if (item.tags.isNotEmpty) ...[
            Text(
              "Tags",
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: item.tags
                  .map((t) => Chip(
                        label: Text(t, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Note
          if (item.userNote != null) ...[
            Text(
              "Your note",
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(item.userNote!, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 16),
          ],

          // Reminder
          if (item.remindAt != null) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.alarm,
                  color: item.reminderSent
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.primary),
              title: Text(
                item.reminderSent ? "Reminder sent" : "Reminder set",
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(_formatRemindAt(item.remindAt!)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatRemindAt(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return "${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return iso;
    }
  }
}
