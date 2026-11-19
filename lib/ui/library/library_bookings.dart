/// Active & historical library bookings tab with sign-in, leave, renew,
/// checkout, and cancel controls.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/library_service.dart';
import '../widgets.dart';
import '../widgets/glass.dart';
import 'library_common.dart';

class LibraryBookingsTab extends ConsumerStatefulWidget {
  const LibraryBookingsTab({super.key});

  @override
  ConsumerState<LibraryBookingsTab> createState() => _LibraryBookingsTabState();
}

class _LibraryBookingsTabState extends ConsumerState<LibraryBookingsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final async = ref.watch(libraryBookingsProvider);
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(libraryBookingsProvider.future),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => libraryErrorWidget(
          context,
          e,
          () => ref.invalidate(libraryBookingsProvider),
        ),
        data: (list) {
          final active = list.where((b) => b.active).toList();
          final past = list.where((b) => !b.active).toList();
          return ListView(
            padding: libraryListPadding(context),
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
      showToast(context, msg, success: true);
      ref.invalidate(libraryBookingsProvider);
      ref.invalidate(libraryAreasProvider(LibraryKind.seat));
      ref.invalidate(libraryAreasProvider(LibraryKind.space));
    } catch (e) {
      if (!mounted) return;
      showToast(context, e is AppError ? e.message : '$label失败', success: false);
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
                              action: (lib) => lib.checkoutBooking(booking),
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
