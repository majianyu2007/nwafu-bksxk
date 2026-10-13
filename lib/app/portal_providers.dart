/// 消息: unread count, to-dos and notices from the school portals, for the
/// signed-in unified identity. Kept in memory only (they go stale quickly
/// and a message title can be private); native builds only.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/portal_service.dart';
import 'edu_providers.dart';

/// The web bridge does not forward the portal hosts.
const bool kPortalSupported = !kIsWeb;

class PortalState {
  const PortalState({this.inbox, this.loading = false, this.error});
  final PortalInbox? inbox;
  final bool loading;
  final AppError? error;
}

class PortalController extends StateNotifier<PortalState> {
  PortalController(this._ref, this._accountId)
    : _session = _ref.read(eduSessionProvider.notifier),
      _epoch = _ref.read(eduSessionProvider.notifier).epoch,
      super(const PortalState());

  final Ref _ref;
  final String? _accountId;
  final EduSessionController _session;
  final int _epoch;
  int _request = 0;

  bool _current(int request) =>
      mounted && request == _request && _session.isCurrent(_epoch);

  Future<void> refresh() async {
    if (_accountId == null || !kPortalSupported || state.loading) return;
    final request = ++_request;
    state = PortalState(inbox: state.inbox, loading: true);
    try {
      final inbox = await _ref.read(eduClientProvider).portal.inbox();
      if (_current(request)) state = PortalState(inbox: inbox);
    } catch (e) {
      if (!_current(request)) return;
      state = PortalState(
        inbox: state.inbox,
        error: e is AppError
            ? e
            : AppError(
                AppErrorKind.schemaOrRedirect,
                message: '学校消息加载失败',
                raw: e,
              ),
      );
    }
  }
}

final portalProvider = StateNotifierProvider<PortalController, PortalState>(
  (ref) => PortalController(
    ref,
    ref.watch(eduSessionProvider.select((s) => s.account?.username)),
  ),
);

/// Unread messages + to-dos, for a badge. Null until the inbox has loaded.
final portalBadgeProvider = Provider<int?>((ref) {
  final inbox = ref.watch(portalProvider.select((s) => s.inbox));
  if (inbox == null) return null;
  return (inbox.unread ?? 0) + (inbox.todo ?? 0);
});
