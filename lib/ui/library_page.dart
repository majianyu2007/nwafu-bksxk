/// 图书馆: free seats and seminar rooms right now, native seat booking,
/// sign-in/leave/checkout/renew/cancel for active bookings, and entrance QR.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/edu_providers.dart';
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

Future<void> _openOfficial(
  BuildContext context, [
  String route = '/home',
]) async {
  final ok = await launchUrl(
    libraryPage(route),
    mode: LaunchMode.externalApplication,
  );
  if (!ok && context.mounted) showToast(context, '没能打开图书馆页面');
}

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
              IconButton(
                tooltip: '打开图书馆预约页',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => _openOfficial(context),
              ),
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
                label: const Text('更新桥接脚本 (1.4.0)'),
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

class _AreaList extends ConsumerWidget {
  const _AreaList({required this.kind});
  final LibraryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_areasProvider(kind));
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
          // Seats: most free first. Rooms: by campus and floor.
          final list = [...areas];
          if (kind == LibraryKind.seat) {
            list.sort((a, b) => (b.free ?? 0).compareTo(a.free ?? 0));
          }
          final free = kind == LibraryKind.seat
              ? list.fold<int>(0, (s, a) => s + (a.free ?? 0))
              : null;
          return ListView(
            padding: _pad(context),
            children: [
              if (free != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                  child: Text(
                    '今天还有 $free 个空座',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              AdaptiveGrid(
                minColumnWidth: 340,
                maxColumns: 2,
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final a in list) _AreaTile(area: a, kind: kind),
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
  const _AreaTile({required this.area, required this.kind});
  final LibraryArea area;
  final LibraryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = area.total == null || area.total == 0
        ? null
        : (area.free ?? 0) / area.total!;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: kind == LibraryKind.seat
          ? () async {
              final booked = await showAdaptiveSheet<bool>(
                context,
                scrollControlled: true,
                maxWidth: 720,
                builder: (_) => _SeatPickerSheet(area: area),
              );
              if (booked == true) {
                ref.invalidate(_areasProvider(LibraryKind.seat));
                ref.invalidate(_bookingsProvider);
              }
            }
          : () => _openOfficial(context, '/SeatScreening/${kind.id}'),
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

/// Native seat picker: choose date & time slot, filter free seats, tap to book.
class _SeatPickerSheet extends ConsumerStatefulWidget {
  const _SeatPickerSheet({required this.area});
  final LibraryArea area;

  @override
  ConsumerState<_SeatPickerSheet> createState() => _SeatPickerSheetState();
}

class _SeatPickerSheetState extends ConsumerState<_SeatPickerSheet> {
  List<LibraryBookDate>? _dates;
  String? _errorText;
  int _dateIndex = 0;
  int _slotIndex = 0;
  List<LibrarySeat>? _seats;
  bool _loadingSeats = false;
  bool _freeOnly = true;
  bool _booking = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadDates();
  }

  Future<void> _loadDates() async {
    setState(() {
      _dates = null;
      _errorText = null;
    });
    try {
      final dates = await ref
          .read(libraryServiceProvider)
          .seatDates(widget.area.id);
      if (!mounted) return;
      setState(() {
        _dates = dates;
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
      setState(() => _seats = const []);
      return;
    }
    final slot = day.times[_slotIndex.clamp(0, day.times.length - 1)];
    setState(() {
      _loadingSeats = true;
      _errorText = null;
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
    final filtered = (_seats ?? const <LibrarySeat>[]).where((s) {
      if (_freeOnly && !s.isFree) return false;
      if (_query.isNotEmpty &&
          !s.no.toLowerCase().contains(_query.toLowerCase()) &&
          !s.name.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.78,
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
                          [widget.area.campus, widget.area.floor]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
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
              const SizedBox(height: 10),
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
                          onPressed: _loadDates,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (dates!.isEmpty)
                const Expanded(
                  child: Center(child: Text('当前没有可预约的日期')),
                )
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
                  const SizedBox(height: 8),
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
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _loadingSeats
                      ? const Center(child: CircularProgressIndicator())
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
                                return Material(
                                  color: s.isFree
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
                                              color: s.isFree
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
              ],
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
