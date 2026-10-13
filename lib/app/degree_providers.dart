/// 学业进度: the degree audit of the signed-in unified identity, cached per
/// identity so it opens offline.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/degree_audit.dart';
import 'edu_providers.dart';
import 'providers.dart';

class DegreeState {
  const DegreeState({this.audit, this.loading = false, this.error});
  final DegreeAudit? audit;
  final bool loading;
  final AppError? error;
}

class DegreeController extends StateNotifier<DegreeState> {
  DegreeController(this._ref, this._accountId)
    : _session = _ref.read(eduSessionProvider.notifier),
      _epoch = _ref.read(eduSessionProvider.notifier).epoch,
      super(
        DegreeState(
          audit: _accountId == null
              ? null
              : DegreeAudit.decode(
                  _ref.read(storageProvider).eduDegreeAudit(_accountId),
                ),
        ),
      );

  final Ref _ref;
  final String? _accountId;
  final EduSessionController _session;
  final int _epoch;
  int _request = 0;

  bool _current(int request) =>
      mounted && request == _request && _session.isCurrent(_epoch);

  /// Fetches the audit. A failure keeps the cached copy on screen.
  Future<void> sync() async {
    final id = _accountId;
    if (id == null || state.loading) return;
    final request = ++_request;
    state = DegreeState(audit: state.audit, loading: true);
    try {
      final audit = await _ref.read(eduClientProvider).ehall.degreeAudit(id);
      if (!_current(request)) return;
      await _session.cacheFor(
        id,
        () => _current(request),
        () => _ref.read(storageProvider).setEduDegreeAudit(id, audit.encode()),
      );
      if (_current(request)) state = DegreeState(audit: audit);
    } catch (e) {
      if (!_current(request)) return;
      state = DegreeState(
        audit: state.audit,
        error: e is AppError
            ? e
            : AppError(
                AppErrorKind.schemaOrRedirect,
                message: '学业进度同步失败',
                raw: e,
              ),
      );
    }
  }
}

final degreeProvider = StateNotifierProvider<DegreeController, DegreeState>(
  (ref) => DegreeController(
    ref,
    ref.watch(eduSessionProvider.select((s) => s.account?.username)),
  ),
);
