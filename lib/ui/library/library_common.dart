/// Shared providers and layout helpers for the Library feature.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/edu_providers.dart';
import '../../core/errors.dart';
import '../../core/web_env.dart';
import '../../data/academic_calendar.dart' show schoolDate;
import '../../data/library_service.dart';
import '../edu_login_page.dart';
import '../layout.dart';
import '../widgets.dart';

final libraryServiceProvider = Provider<LibraryService>((ref) {
  final client = ref.watch(eduClientProvider);
  client.library.onLoginRequired ??=
      ref.read(eduSessionProvider.notifier).silentRelogin;
  return client.library;
});

void invalidateLibraryProviders(WidgetRef ref) {
  ref.invalidate(libraryAreasProvider(LibraryKind.seat));
  ref.invalidate(libraryAreasProvider(LibraryKind.space));
  ref.invalidate(libraryBookingsProvider);
  ref.invalidate(libraryMemberProvider);
}

final libraryAreasProvider = FutureProvider.autoDispose
    .family<List<LibraryArea>, LibraryKind>((ref, kind) {
      return ref
          .watch(libraryServiceProvider)
          .areas(kind, schoolDate(DateTime.now()));
    });

final libraryBookingsProvider = FutureProvider.autoDispose<List<LibraryBooking>>((
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

final libraryMemberProvider = FutureProvider.autoDispose<LibraryMember>(
  (ref) => ref.watch(libraryServiceProvider).member(),
);

Widget libraryErrorWidget(BuildContext context, Object e, VoidCallback retry) {
  final err = e is AppError
      ? e
      : AppError(AppErrorKind.unknown, message: '图书馆系统暂时不可用');
  final needsBridgeUpdate = kIsWeb && !isFullCampusBridgeReady;
  final needsLogin =
      err.kind == AppErrorKind.sessionExpired ||
      err.kind == AppErrorKind.account;
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
                label: const Text('更新桥接脚本 ($kRecommendedWebBridgeVersion)'),
              ),
            if (needsLogin)
              Consumer(
                builder: (context, ref, _) => FilledButton(
                  onPressed: () async {
                    final ok = await pushEduLogin(context);
                    if (ok == true) {
                      invalidateLibraryProviders(ref);
                      retry();
                    }
                  },
                  child: const Text('重新登录'),
                ),
              ),
            TextButton(onPressed: retry, child: const Text('重试')),
          ],
        ),
      ),
    ],
  );
}

EdgeInsets libraryListPadding(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  final side = ((w - kReadableMaxWidth) / 2).clamp(12.0, 1e9);
  return EdgeInsets.fromLTRB(side, 12, side, 32);
}
