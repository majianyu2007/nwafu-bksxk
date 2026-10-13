/// 图书馆: free seats and seminar rooms right now, the student's bookings and
/// the entrance QR code. Booking, signing in and cancelling open the
/// library's own page (see library_service.dart for why).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/edu_providers.dart';
import '../core/errors.dart';
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
            bottom: const TabBar(
              tabs: [
                Tab(text: '座位'),
                Tab(text: '研讨室'),
                Tab(text: '我的预约'),
              ],
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
  return ListView(
    children: [
      EmptyState(
        icon: Icons.cloud_off_outlined,
        title: err.message,
        subtitle: err.hint ?? '下拉重试',
      ),
      Center(
        child: TextButton(onPressed: retry, child: const Text('重试')),
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
              for (final a in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _AreaTile(area: a, kind: kind),
                ),
              const SizedBox(height: 8),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      _openOfficial(context, '/SeatScreening/${kind.id}'),
                  icon: const Icon(Icons.open_in_new),
                  label: Text('去图书馆页面预约${kind.label}'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AreaTile extends StatelessWidget {
  const _AreaTile({required this.area, required this.kind});
  final LibraryArea area;
  final LibraryKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = area.total == null || area.total == 0
        ? null
        : (area.free ?? 0) / area.total!;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => _openOfficial(context, '/SeatScreening/${kind.id}'),
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
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 12),
                  child: FilledButton.tonalIcon(
                    onPressed: () => _openOfficial(context, '/my/seat'),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('签到、暂离、签退或取消'),
                  ),
                ),
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

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking, this.active = false});
  final LibraryBooking booking;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        tint: active ? scheme.primary : null,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
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
              color: active ? scheme.primary : scheme.outline,
            ),
          ],
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
