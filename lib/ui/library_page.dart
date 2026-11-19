/// 图书馆: free seats and seminar rooms right now, native seat booking,
/// sign-in/leave/checkout/renew/cancel for active bookings, and entrance QR.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/edu_providers.dart';
import '../app/ui_prefs.dart';
import '../core/errors.dart';
import '../core/web_env.dart';
import '../data/academic_calendar.dart' show schoolDate;
import '../data/library_service.dart';
import 'layout.dart';
import 'widgets.dart';
import 'widgets/glass.dart';

final libraryServiceProvider = Provider<LibraryService>((ref) {
  final client = ref.watch(eduClientProvider);
  return LibraryService(
    client.cas,
    onLoginRequired: ref.read(eduSessionProvider.notifier).silentRelogin,
  );
});

final _areasProvider = FutureProvider.autoDispose
    .family<List<LibraryArea>, LibraryKind>((ref, kind) {
      return ref
          .watch(libraryServiceProvider)
          .areas(kind, schoolDate(DateTime.now()));
    });

final _bookingsProvider = FutureProvider.autoDispose<List<LibraryBooking>>((
  ref,
) async {
  final lib = ref.watch(libraryServiceProvider);
  final seats = await lib.seatBookings();
  List<LibraryBooking> rooms = const [];
  try {
    rooms = await lib.roomBookings();
  } on AppError {
    // Not every account can book rooms; seats alone are still useful.
  }
  return [
    ...seats,
    ...rooms,
  ]..sort((a, b) => (b.begin ?? DateTime(0)).compareTo(a.begin ?? DateTime(0)));
});

final _memberProvider = FutureProvider.autoDispose<LibraryMember>(
  (ref) => ref.watch(libraryServiceProvider).member(),
);

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                onPressed: () => _showQr(context),
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
              _Bookings(),
            ],
          ),
        ),
      ),
    );
  }

  void _showQr(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => const SafeArea(child: _QrSheet()),
    );
  }
}

Widget _error(BuildContext context, Object e, VoidCallback retry) {
  final err = e is AppError
      ? e
      : AppError(AppErrorKind.unknown, message: '图书馆系统暂时不可用');
  final needsBridgeUpdate = kIsWeb && !isFullCampusBridgeReady;
  return ListView(
    children: [
      EmptyState(
        icon: needsBridgeUpdate
            ? Icons.extension_outlined
            : Icons.cloud_off_outlined,
        title: err.message,
        subtitle: err.hint ?? '下拉重试',
      ),
      Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            if (needsBridgeUpdate)
              FilledButton.icon(
                onPressed: openWebBridgeInstaller,
                icon: const Icon(Icons.download_outlined),
                label: const Text('更新桥接脚本 (1.4.2)'),
              ),
            TextButton(onPressed: retry, child: const Text('重试')),
          ],
        ),
      ),
    ],
  );
}

EdgeInsets _pad(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final side = ((w - kReadableMaxWidth) / 2).clamp(12.0, 1e9);
  return EdgeInsets.fromLTRB(side, 12, side, 32);
}

class _AreaList extends ConsumerStatefulWidget {
  const _AreaList({required this.kind});
  final LibraryKind kind;

  @override
  ConsumerState<_AreaList> createState() => _AreaListState();
}

class _AreaListState extends ConsumerState<_AreaList> {
  String? _campus;

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    final async = ref.watch(_areasProvider(kind));
    final favs = ref.watch(
      uiPrefsProvider.select((p) => p.favoriteLibraryAreas),
    );
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(_areasProvider(kind).future),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _error(context, e, () => ref.invalidate(_areasProvider(kind))),
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
            padding: _pad(context),
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
                builder: (_) => _SeatPickerSheet(area: area),
              );
              if (booked == true) {
                ref.invalidate(_areasProvider(LibraryKind.seat));
                ref.invalidate(_bookingsProvider);
              }
            }
          : () async {
              final booked = await showAdaptiveSheet<bool>(
                context,
                scrollControlled: true,
                maxWidth: 680,
                builder: (_) => _SeminarBookSheet(area: area),
              );
              if (booked == true) {
                ref.invalidate(_areasProvider(LibraryKind.space));
                ref.invalidate(_bookingsProvider);
              }
            },
      child: Row(
        children: [
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

class _Bookings extends ConsumerWidget {
  const _Bookings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_bookingsProvider);
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(_bookingsProvider.future),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            _error(context, e, () => ref.invalidate(_bookingsProvider)),
        data: (list) {
          final active = list.where((b) => b.active).toList();
          final past = list.where((b) => !b.active).toList();
          return ListView(
            padding: _pad(context),
            children: [
              if (active.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
                  child: Text('现在没有进行中的预约'),
                )
              else ...[
                const _Heading('进行中'),
                for (final b in active) _BookingTile(booking: b, active: true),
                const SizedBox(height: 8),
              ],
              if (past.isNotEmpty) ...[
                const _Heading('最近记录'),
                for (final b in past.take(20)) _BookingTile(booking: b),
              ],
              if (list.isEmpty)
                Text('还没有预约记录', style: theme.textTheme.bodySmall),
            ],
          );
        },
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _BookingTile extends ConsumerStatefulWidget {
  const _BookingTile({required this.booking, this.active = false});
  final LibraryBooking booking;
  final bool active;

  @override
  ConsumerState<_BookingTile> createState() => _BookingTileState();
}

class _BookingTileState extends ConsumerState<_BookingTile> {
  bool _busy = false;

  Future<void> _runAction({
    required String label,
    required Future<String> Function(LibraryService lib) action,
    bool confirm = false,
  }) async {
    if (_busy) return;
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('确认$label'),
          content: Text(
            '${widget.booking.place} ${widget.booking.seat}\n'
            '${widget.booking.day} ${widget.booking.start}–${widget.booking.end}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(label),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final msg = await action(ref.read(libraryServiceProvider));
      if (!mounted) return;
      showToast(context, msg);
      ref.invalidate(_bookingsProvider);
      ref.invalidate(_areasProvider(LibraryKind.seat));
    } catch (e) {
      if (!mounted) return;
      showToast(context, e is AppError ? e.message : '$label失败');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        tint: widget.active ? scheme.primary : null,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          booking.place,
                          booking.seat,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${booking.day} ${booking.start}–${booking.end}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: booking.statusName,
                  color: widget.active ? scheme.primary : scheme.outline,
                ),
              ],
            ),
            if (widget.active) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (booking.canSignIn)
                    FilledButton.tonalIcon(
                      onPressed: _busy
                          ? null
                          : () => _runAction(
                              label: '签到',
                              action: (lib) => lib.signInBooking(booking.id),
                            ),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('签到'),
                    ),
                  if (booking.canLeave)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _runAction(
                              label: '暂离',
                              confirm: true,
                              action: (lib) => lib.leaveBooking(booking.id),
                            ),
                      icon: const Icon(Icons.pause_circle_outline, size: 18),
                      label: const Text('暂离'),
                    ),
                  if (booking.canRenew)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _runAction(
                              label: '续座',
                              confirm: true,
                              action: (lib) => lib.renewBooking(booking),
                            ),
                      icon: const Icon(Icons.update, size: 18),
                      label: const Text('续座'),
                    ),
                  if (booking.canCheckout)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _runAction(
                              label: '签退',
                              confirm: true,
                              action: (lib) => lib.checkoutBooking(booking.id),
                            ),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('签退'),
                    ),
                  if (booking.canCancel)
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _runAction(
                              label: '取消预约',
                              confirm: true,
                              action: (lib) => lib.cancelBooking(booking),
                            ),
                      icon: Icon(
                        Icons.cancel_outlined,
                        size: 18,
                        color: scheme.error,
                      ),
                      label: Text(
                        '取消预约',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Native seat picker: interactive floorplan map + searchable list, date &
/// time slot selection, one-tap native booking.
class _SeatPickerSheet extends ConsumerStatefulWidget {
  const _SeatPickerSheet({required this.area});
  final LibraryArea area;

  @override
  ConsumerState<_SeatPickerSheet> createState() => _SeatPickerSheetState();
}

class _SeatPickerSheetState extends ConsumerState<_SeatPickerSheet> {
  List<LibraryBookDate>? _dates;
  LibrarySeatMap? _seatMap;
  String? _mapError;
  String? _errorText;
  int _dateIndex = 0;
  int _slotIndex = 0;
  List<LibrarySeat>? _seats;
  LibrarySeat? _selectedSeat;
  bool _loadingSeats = false;
  bool _mapMode = true;
  bool _freeOnly = true;
  bool _booking = false;
  String _query = '';
  final _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    _loadDatesAndMap();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _loadDatesAndMap() async {
    setState(() {
      _dates = null;
      _errorText = null;
      _mapError = null;
      _selectedSeat = null;
    });
    final lib = ref.read(libraryServiceProvider);
    // Fetch floorplan map in parallel; record error rather than swallowing silently.
    String? mapErr;
    final mapFuture = lib.seatMap(widget.area.id).catchError((Object e) {
      mapErr = e is AppError ? e.message : '楼层参考图暂不可用';
      return null;
    });
    try {
      final dates = await lib.seatDates(widget.area.id);
      final map = await mapFuture;
      if (!mounted) return;
      setState(() {
        _dates = dates;
        _seatMap = map;
        _mapError = mapErr;
        _mapMode = map != null && map.hasImage;
        _dateIndex = 0;
        _slotIndex = 0;
      });
      if (dates.isNotEmpty && dates.first.times.isNotEmpty) {
        await _loadSeats();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e is AppError ? e.message : '无法加载可预约时段';
      });
    }
  }

  Future<void> _loadSeats() async {
    final dates = _dates;
    if (dates == null || dates.isEmpty) return;
    final day = dates[_dateIndex];
    if (day.times.isEmpty) {
      setState(() {
        _seats = const [];
        _selectedSeat = null;
      });
      return;
    }
    final slot = day.times[_slotIndex.clamp(0, day.times.length - 1)];
    setState(() {
      _loadingSeats = true;
      _errorText = null;
      _selectedSeat = null;
    });
    try {
      final list = await ref
          .read(libraryServiceProvider)
          .seats(widget.area.id, day: day.day, slot: slot);
      if (!mounted) return;
      setState(() {
        _seats = list;
        _loadingSeats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSeats = false;
        _errorText = e is AppError ? e.message : '无法加载座位列表';
      });
    }
  }

  Future<void> _confirmBook(LibrarySeat seat) async {
    final dates = _dates;
    if (dates == null || _booking) return;
    final day = dates[_dateIndex];
    final slot = day.times[_slotIndex];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认预约座位'),
        content: Text(
          '${widget.area.name} · ${seat.no} 号座\n'
          '${day.day} ${slot.label}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('预约'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _booking = true);
    try {
      final msg = await ref
          .read(libraryServiceProvider)
          .bookSeat(seatId: seat.id, segmentId: slot.id);
      if (!mounted) return;
      showToast(context, msg);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showToast(context, e is AppError ? e.message : '预约失败');
      setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dates = _dates;
    final currentDay = dates != null && dates.isNotEmpty
        ? dates[_dateIndex]
        : null;
    final allSeats = _seats ?? const <LibrarySeat>[];
    final canShowMap = _seatMap != null && _seatMap!.hasImage;
    final filtered = allSeats.where((s) {
      if (_freeOnly && !s.isFree) return false;
      if (_query.isNotEmpty &&
          !s.no.toLowerCase().contains(_query.toLowerCase()) &&
          !s.name.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    final freeCount = allSeats.where((s) => s.isFree).length;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.84,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.area.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            widget.area.campus,
                            widget.area.floor,
                            if (_seats != null) '空座 $freeCount / ${allSeats.length}',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (canShowMap)
                    SegmentedButton<bool>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.map_outlined, size: 16),
                          label: Text('平面图'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.grid_view_outlined, size: 16),
                          label: Text('列表'),
                        ),
                      ],
                      selected: {_mapMode},
                      onSelectionChanged: (v) =>
                          setState(() => _mapMode = v.first),
                    ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (dates == null && _errorText == null)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorText != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorText!),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loadDatesAndMap,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (dates!.isEmpty)
                const Expanded(child: Center(child: Text('当前没有可预约的日期')))
              else ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < dates.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(dates[i].day),
                            selected: i == _dateIndex,
                            onSelected: (_) {
                              setState(() {
                                _dateIndex = i;
                                _slotIndex = 0;
                              });
                              _loadSeats();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                if (currentDay != null && currentDay.times.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < currentDay.times.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(currentDay.times[i].label),
                              selected: i == _slotIndex,
                              onSelected: (_) {
                                setState(() => _slotIndex = i);
                                _loadSeats();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (_mapError != null && !canShowMap) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '平面图未加载：$_mapError（已切换为列表选座）',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
                if (!(_mapMode && canShowMap))
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search, size: 18),
                            hintText: '搜索座位号',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _query = v.trim()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('仅空座'),
                        selected: _freeOnly,
                        onSelected: (v) => setState(() => _freeOnly = v),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Expanded(child: _SeatMapLegend()),
                      IconButton(
                        tooltip: '重置缩放',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.center_focus_strong, size: 20),
                        onPressed: () =>
                            _transform.value = Matrix4.identity(),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _loadingSeats
                      ? const Center(child: CircularProgressIndicator())
                      : (_mapMode && canShowMap)
                      ? _FloorplanSeatMap(
                          imageUrl: _seatMap!.freeUrl,
                          seats: allSeats,
                          selectedSeatId: _selectedSeat?.id,
                          controller: _transform,
                          onSelect: (seat) =>
                              setState(() => _selectedSeat = seat),
                        )
                      : filtered.isEmpty
                      ? const Center(child: Text('该时段没有符合条件的座位'))
                      : LayoutBuilder(
                          builder: (context, c) {
                            final cols = (c.maxWidth / 84).floor().clamp(3, 8);
                            return GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 1.5,
                                  ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final s = filtered[index];
                                final picked = _selectedSeat?.id == s.id;
                                return Material(
                                  color: picked
                                      ? scheme.primary
                                      : s.isFree
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: s.isFree && !_booking
                                        ? () => _confirmBook(s)
                                        : null,
                                    child: Center(
                                      child: Text(
                                        s.no,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: picked
                                                  ? scheme.onPrimary
                                                  : s.isFree
                                                  ? scheme.onPrimaryContainer
                                                  : scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
                if (_selectedSeat != null && currentDay != null) ...[
                  const SizedBox(height: 8),
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    tint: scheme.primary,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '已选 ${_selectedSeat!.no} 号座',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${currentDay.day} ${currentDay.times[_slotIndex].label}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: _booking
                              ? null
                              : () => _confirmBook(_selectedSeat!),
                          child: Text(_booking ? '预约中…' : '立即预约'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SeatMapLegend extends StatelessWidget {
  const _SeatMapLegend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        dot(Colors.green.withValues(alpha: 0.75), '空闲'),
        dot(scheme.primary, '已选'),
        dot(Colors.orange.withValues(alpha: 0.75), '暂离'),
        dot(Colors.blueGrey.withValues(alpha: 0.65), '已约/使用'),
        dot(Colors.grey.withValues(alpha: 0.45), '不可用'),
      ],
    );
  }
}

/// Interactive zoomable/pannable floorplan with percentage-positioned seats.
/// Fetches the reference image through [LibraryService.fetchImageBytes] so Web
/// CanvasKit avoids CORS failures and native works through CampusProxy VPN.
class _FloorplanSeatMap extends ConsumerStatefulWidget {
  const _FloorplanSeatMap({
    required this.imageUrl,
    required this.seats,
    required this.selectedSeatId,
    required this.controller,
    required this.onSelect,
  });

  final String imageUrl;
  final List<LibrarySeat> seats;
  final String? selectedSeatId;
  final TransformationController controller;
  final ValueChanged<LibrarySeat> onSelect;

  @override
  ConsumerState<_FloorplanSeatMap> createState() => _FloorplanSeatMapState();
}

class _FloorplanSeatMapState extends ConsumerState<_FloorplanSeatMap> {
  Uint8List? _bytes;
  double? _aspectRatio;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _FloorplanSeatMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() {
      _bytes = null;
      _aspectRatio = null;
      _loading = true;
      _failed = false;
    });
    try {
      final bytes = await ref
          .read(libraryServiceProvider)
          .fetchImageBytes(widget.imageUrl);
      if (!mounted) return;
      ui.decodeImageFromList(bytes, (img) {
        if (!mounted) return;
        if (img.width > 0 && img.height > 0) {
          setState(() => _aspectRatio = img.width / img.height);
        }
        img.dispose();
      });
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Color _seatColor(LibrarySeat seat, bool selected, ColorScheme scheme) {
    if (selected) return scheme.primary.withValues(alpha: 0.9);
    return switch (seat.visualStatus) {
      LibrarySeatStatus.free => Colors.green.withValues(alpha: 0.34),
      LibrarySeatStatus.leave => Colors.orange.withValues(alpha: 0.55),
      LibrarySeatStatus.booked => Colors.blueGrey.withValues(alpha: 0.5),
      LibrarySeatStatus.inUse => Colors.blueGrey.withValues(alpha: 0.65),
      LibrarySeatStatus.closed => Colors.grey.withValues(alpha: 0.45),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = _aspectRatio ?? (16 / 10);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InteractiveViewer(
          transformationController: widget.controller,
          minScale: 1.0,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(24),
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final h = c.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_bytes != null)
                        Image.memory(
                          _bytes!,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        )
                      else if (_loading)
                        const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_failed)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              '底图未加载（座位仍可直接点选）',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      for (final seat in widget.seats)
                        if (seat.hasCoords)
                          Positioned(
                            left: (seat.pointX! / 100) * w,
                            top: (seat.pointY! / 100) * h,
                            width: (seat.width! / 100) * w,
                            height: (seat.height! / 100) * h,
                            child: Tooltip(
                              message:
                                  '${seat.no} 号座 · ${seat.isFree ? '空闲' : seat.statusName}',
                              child: GestureDetector(
                                onTap: seat.isFree
                                    ? () => widget.onSelect(seat)
                                    : null,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _seatColor(
                                      seat,
                                      seat.id == widget.selectedSeatId,
                                      scheme,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: seat.id == widget.selectedSeatId
                                          ? scheme.onPrimary
                                          : seat.isFree
                                          ? Colors.green.shade700
                                          : Colors.transparent,
                                      width: seat.id == widget.selectedSeatId
                                          ? 1.8
                                          : 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Native seminar room booking sheet (date, time range, title/content/mobile,
/// teammate lookup by student card, AES-encrypted submit).
class _SeminarBookSheet extends ConsumerStatefulWidget {
  const _SeminarBookSheet({required this.area});
  final LibraryArea area;

  @override
  ConsumerState<_SeminarBookSheet> createState() => _SeminarBookSheetState();
}

class _SeminarBookSheetState extends ConsumerState<_SeminarBookSheet> {
  List<String>? _dates;
  int _dateIndex = 0;
  LibrarySeminarDay? _dayInfo;
  bool _loadingDay = false;
  bool _submitting = false;
  bool _addingMember = false;
  String? _errorText;

  String _startTime = '08:00';
  String _endTime = '10:00';
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _mobile = TextEditingController();
  final _card = TextEditingController();
  final _members = <LibraryTeamMember>[];

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _mobile.dispose();
    _card.dispose();
    super.dispose();
  }

  List<String> _halfHourSlots(String start, String end) {
    int toMin(String hhmm) {
      final p = hhmm.split(':');
      final h = int.tryParse(p.first) ?? 8;
      final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
      return h * 60 + m;
    }

    final s = toMin(start);
    final e = toMin(end);
    final out = <String>[];
    for (var m = s; m <= e; m += 30) {
      final hh = (m ~/ 60).toString().padLeft(2, '0');
      final mm = (m % 60).toString().padLeft(2, '0');
      out.add('$hh:$mm');
    }
    return out;
  }

  Future<void> _loadDates() async {
    setState(() {
      _dates = null;
      _errorText = null;
    });
    try {
      final dates = await ref
          .read(libraryServiceProvider)
          .seminarDates(widget.area.id);
      if (!mounted) return;
      setState(() {
        _dates = dates;
        _dateIndex = 0;
      });
      if (dates.isNotEmpty) await _loadDay();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorText = e is AppError ? e.message : '无法加载研讨室可预约日期';
      });
    }
  }

  Future<void> _loadDay() async {
    final dates = _dates;
    if (dates == null || dates.isEmpty) return;
    final day = dates[_dateIndex];
    setState(() => _loadingDay = true);
    try {
      final info = await ref
          .read(libraryServiceProvider)
          .seminarDay(
            roomId: widget.area.id,
            areaId: widget.area.parentId.isNotEmpty
                ? widget.area.parentId
                : widget.area.id,
            day: day,
          );
      if (!mounted) return;
      final slots = _halfHourSlots(info.openStart, info.openEnd);
      setState(() {
        _dayInfo = info;
        _loadingDay = false;
        if (slots.length >= 3) {
          _startTime = slots.first;
          _endTime = slots[2];
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDay = false;
        _errorText = e is AppError ? e.message : '无法加载研讨室时段信息';
      });
    }
  }

  Future<void> _addMember() async {
    final card = _card.text.trim();
    if (card.isEmpty || _addingMember) return;
    final maxP = _dayInfo?.maxPerson ?? widget.area.capacity ?? 10;
    if (_members.length + 1 >= maxP) {
      showToast(context, '已达到最大参与人数 ($maxP 人)');
      return;
    }
    setState(() => _addingMember = true);
    try {
      final day = _dates?[_dateIndex] ?? '';
      final member = await ref
          .read(libraryServiceProvider)
          .lookupSeminarMember(
            card: card,
            areaId: widget.area.id,
            beginTime: day.isNotEmpty ? '$day $_startTime' : null,
            endTime: day.isNotEmpty ? '$day $_endTime' : null,
          );
      if (!mounted) return;
      if (_members.any((m) => m.id == member.id)) {
        showToast(context, '该成员已在列表中');
      } else {
        setState(() {
          _members.add(member);
          _card.clear();
        });
      }
    } catch (e) {
      if (!mounted) return;
      showToast(context, e is AppError ? e.message : '查询成员失败');
    } finally {
      if (mounted) setState(() => _addingMember = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting || _dates == null || _dates!.isEmpty) return;
    final minP = _dayInfo?.minPerson ?? 1;
    if (_members.length + 1 < minP) {
      showToast(context, '至少还需要添加 ${minP - 1 - _members.length} 名参与成员');
      return;
    }
    if (_title.text.trim().isEmpty) {
      showToast(context, '请填写预约主题');
      return;
    }
    if (_content.text.trim().isEmpty) {
      showToast(context, '请填写使用内容');
      return;
    }
    if (_mobile.text.trim().isEmpty) {
      showToast(context, '请填写联系电话');
      return;
    }
    if (_startTime.compareTo(_endTime) >= 0) {
      showToast(context, '结束时间需晚于开始时间');
      return;
    }
    setState(() => _submitting = true);
    try {
      final msg = await ref
          .read(libraryServiceProvider)
          .bookSeminar(
            roomId: widget.area.id,
            day: _dates![_dateIndex],
            startTime: _startTime,
            endTime: _endTime,
            title: _title.text,
            content: _content.text,
            mobile: _mobile.text,
            teamUserIds: [for (final m in _members) m.id],
          );
      if (!mounted) return;
      showToast(context, msg);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showToast(context, e is AppError ? e.message : '研讨室预约失败');
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _dayInfo;
    final slots = info == null
        ? const ['08:00', '10:00', '12:00', '14:00', '16:00', '18:00', '20:00']
        : _halfHourSlots(info.openStart, info.openEnd);
    final minNeed = ((info?.minPerson ?? 1) - 1).clamp(0, 99);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.84,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.area.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            widget.area.campus,
                            widget.area.floor,
                            if (info != null)
                              '${info.minPerson}–${info.maxPerson} 人',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_dates == null && _errorText == null)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorText != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_errorText!),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loadDates,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_dates!.isEmpty)
                const Expanded(child: Center(child: Text('当前没有可预约的日期')))
              else
                Expanded(
                  child: ListView(
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (var i = 0; i < _dates!.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(_dates![i]),
                                  selected: i == _dateIndex,
                                  onSelected: (_) {
                                    setState(() => _dateIndex = i);
                                    _loadDay();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_loadingDay)
                        const LinearProgressIndicator()
                      else ...[
                        if (info != null && info.bookedRanges.isNotEmpty) ...[
                          Text(
                            '当日已约时段：${info.bookedRanges.map((r) => '${r.$1}–${r.$2}').join('、')}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: slots.contains(_startTime)
                                    ? _startTime
                                    : slots.first,
                                decoration: const InputDecoration(
                                  labelText: '开始时间',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  for (final t in slots)
                                    DropdownMenuItem(value: t, child: Text(t)),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _startTime = v);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: slots.contains(_endTime)
                                    ? _endTime
                                    : slots.last,
                                decoration: const InputDecoration(
                                  labelText: '结束时间',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  for (final t in slots)
                                    DropdownMenuItem(value: t, child: Text(t)),
                                ],
                                onChanged: (v) {
                                  if (v != null) setState(() => _endTime = v);
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _title,
                          decoration: const InputDecoration(
                            labelText: '预约主题',
                            hintText: '例如：小组课程讨论',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _content,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: '使用内容',
                            hintText: '简述研讨内容',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _mobile,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: '联系电话',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          minNeed > 0
                              ? '参与成员（含本人至少 ${info!.minPerson} 人，还需添加 ${(minNeed - _members.length).clamp(0, 99)} 人）'
                              : '参与成员（可选）',
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _card,
                                decoration: const InputDecoration(
                                  hintText: '输入同伴学号',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                onSubmitted: (_) => _addMember(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.tonal(
                              onPressed: _addingMember ? null : _addMember,
                              child: Text(_addingMember ? '查询中…' : '添加'),
                            ),
                          ],
                        ),
                        if (_members.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final m in _members)
                                InputChip(
                                  label: Text('${m.name} (${m.card})'),
                                  onDeleted: () => setState(
                                    () => _members.removeWhere(
                                      (x) => x.id == m.id,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: Text(_submitting ? '提交中…' : '确认预约研讨室'),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrSheet extends ConsumerWidget {
  const _QrSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_memberProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: async.when(
        loading: () => const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => SizedBox(
          height: 160,
          child: Center(child: Text(e is AppError ? e.message : '入馆码暂时取不到')),
        ),
        data: (m) {
          final data = m.qrImage;
          final bytes = data == null
              ? null
              : base64Decode(data.substring(data.indexOf(',') + 1));
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('入馆码', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [m.name, m.roleName].where((s) => s.isNotEmpty).join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (bytes == null)
                const Text('图书馆没有返回入馆码')
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Image.memory(
                    bytes,
                    width: 220,
                    height: 220,
                    filterQuality: FilterQuality.none,
                  ),
                ),
              const SizedBox(height: 12),
              Text('在闸机扫码入馆', style: theme.textTheme.bodySmall),
            ],
          );
        },
      ),
    );
  }
}
