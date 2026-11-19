/// 图书馆: free seats and seminar rooms right now, native seat booking,
/// sign-in/leave/checkout/renew/cancel for active bookings, and entrance QR.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../app/ui_prefs.dart';
import '../data/library_service.dart';
import 'edu_login_page.dart';
import 'layout.dart';
import 'library/library_bookings.dart';
import 'library/library_common.dart';
import 'library/library_media.dart';
import 'library/seat_picker_sheet.dart';
import 'library/seminar_book_sheet.dart';
import 'widgets.dart';
import 'widgets/glass.dart';

export 'library/library_common.dart' show libraryServiceProvider;
export 'library/library_media.dart' show showLibraryQrSheet;

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(eduSessionProvider.select((s) => s.signedIn));
    if (!signedIn) {
      return AuroraBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('图书馆'),
            backgroundColor: Colors.transparent,
          ),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const EmptyState(
                  icon: Icons.local_library_outlined,
                  title: '登录统一身份认证后使用图书馆预约',
                  subtitle: '支持可视化楼层平面图选座、研讨室预约、签到与入馆码',
                ),
                FilledButton(
                  onPressed: () => pushEduLogin(context),
                  child: const Text('去登录'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 3,
      child: AuroraBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('图书馆'),
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                tooltip: '入馆码',
                icon: const Icon(Icons.qr_code_2),
                onPressed: () => showLibraryQrSheet(context),
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: const TabBar(
                    tabs: [
                      Tab(text: '座位'),
                      Tab(text: '研讨室'),
                      Tab(text: '我的预约'),
                    ],
                  ),
                ),
              ),
            ),
          ),
          body: const TabBarView(
            children: [
              _AreaList(kind: LibraryKind.seat),
              _AreaList(kind: LibraryKind.space),
              LibraryBookingsTab(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AreaList extends ConsumerStatefulWidget {
  const _AreaList({required this.kind});
  final LibraryKind kind;

  @override
  ConsumerState<_AreaList> createState() => _AreaListState();
}

class _AreaListState extends ConsumerState<_AreaList>
    with AutomaticKeepAliveClientMixin {
  String? _campus;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final kind = widget.kind;
    final async = ref.watch(libraryAreasProvider(kind));
    final favs = ref.watch(
      uiPrefsProvider.select((p) => p.favoriteLibraryAreas),
    );
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(libraryAreasProvider(kind).future),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => libraryErrorWidget(
          context,
          e,
          () => ref.invalidate(libraryAreasProvider(kind)),
        ),
        data: (areas) {
          if (areas.isEmpty) {
            return ListView(
              children: const [
                EmptyState(icon: Icons.event_busy, title: '今天没有开放'),
              ],
            );
          }
          final campuses = {
            for (final a in areas)
              if (a.campus.isNotEmpty) a.campus,
          }.toList()..sort();
          final activeCampus =
              _campus != null && campuses.contains(_campus) ? _campus : null;
          // Favorites first; within seats, most free first.
          final list = [
            for (final a in areas)
              if (activeCampus == null || a.campus == activeCampus) a,
          ]..sort((a, b) {
              final fa = favs.contains(a.id) ? 0 : 1;
              final fb = favs.contains(b.id) ? 0 : 1;
              if (fa != fb) return fa.compareTo(fb);
              if (kind == LibraryKind.seat) {
                return (b.free ?? 0).compareTo(a.free ?? 0);
              }
              return a.name.compareTo(b.name);
            });
          final free = kind == LibraryKind.seat
              ? list.fold<int>(0, (s, a) => s + (a.free ?? 0))
              : null;
          return ListView(
            padding: libraryListPadding(context),
            children: [
              if (free != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    '今天还有 $free 个空座',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (campuses.length >= 2) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ChoiceChip(
                        label: const Text('全部校区'),
                        selected: activeCampus == null,
                        onSelected: (_) => setState(() => _campus = null),
                      ),
                      for (final c in campuses)
                        ChoiceChip(
                          label: Text(c),
                          selected: activeCampus == c,
                          onSelected: (_) => setState(() => _campus = c),
                        ),
                    ],
                  ),
                ),
              ],
              AdaptiveGrid(
                minColumnWidth: 340,
                maxColumns: 2,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final a in list)
                    _AreaTile(
                      area: a,
                      kind: kind,
                      favorite: favs.contains(a.id),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AreaTile extends ConsumerWidget {
  const _AreaTile({
    required this.area,
    required this.kind,
    this.favorite = false,
  });
  final LibraryArea area;
  final LibraryKind kind;
  final bool favorite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = area.total == null || area.total == 0
        ? null
        : (area.free ?? 0) / area.total!;
    return GlassCard(
      tint: favorite ? scheme.primary : null,
      tintAmount: 0.06,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      onTap: kind == LibraryKind.seat
          ? () async {
              final booked = await showAdaptiveSheet<bool>(
                context,
                scrollControlled: true,
                maxWidth: 820,
                builder: (_) => SeatPickerSheet(area: area),
              );
              if (booked == true && context.mounted) {
                ref.invalidate(libraryAreasProvider(LibraryKind.seat));
                ref.invalidate(libraryBookingsProvider);
              }
            }
          : () async {
              final booked = await showAdaptiveSheet<bool>(
                context,
                scrollControlled: true,
                maxWidth: 680,
                builder: (_) => SeminarBookSheet(area: area),
              );
              if (booked == true && context.mounted) {
                ref.invalidate(libraryAreasProvider(LibraryKind.space));
                ref.invalidate(libraryBookingsProvider);
              }
            },
      child: Row(
        children: [
          if (kind == LibraryKind.space && area.imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 72,
                height: 54,
                child: LibraryImage(url: area.imageUrl, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  area.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    area.campus,
                    area.floor,
                    if (kind == LibraryKind.space) area.typeName,
                    if (area.capacity != null) '可容纳 ${area.capacity} 人',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                if (ratio != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      color: ratio > 0.3
                          ? Colors.green
                          : ratio > 0.1
                          ? Colors.orange
                          : scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (area.free != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${area.free}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: (area.free ?? 0) > 0 ? scheme.primary : scheme.error,
                  ),
                ),
                Text('空 / ${area.total}', style: theme.textTheme.bodySmall),
              ],
            )
          else
            StatusPill(
              label: area.fullyBooked ? '约满' : '可预约',
              color: area.fullyBooked ? scheme.error : Colors.green,
            ),
          IconButton(
            tooltip: favorite ? '取消常用置顶' : '设为常用置顶',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              favorite ? Icons.star : Icons.star_border,
              size: 20,
              color: favorite ? Colors.amber.shade700 : scheme.onSurfaceVariant,
            ),
            onPressed: () => ref
                .read(uiPrefsProvider.notifier)
                .toggleFavoriteLibraryArea(area.id),
          ),
        ],
      ),
    );
  }
}
