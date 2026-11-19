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
  int _request = 0;

  bool _current(int request, int sessionEpoch) =>
      mounted &&
      request == _request &&
      _session.isCurrent(sessionEpoch) &&
      _ref.read(eduSessionProvider).account?.username == _accountId;

  /// Fetches the audit. A failure keeps the cached copy on screen.
  Future<void> sync() async {
    final id = _accountId;
    if (id == null || state.loading) return;
    final request = ++_request;
    final sessionEpoch = _session.epoch;
    state = DegreeState(audit: state.audit, loading: true);
    try {
      final audit = await _ref.read(eduClientProvider).ehall.degreeAudit(id);
      if (!_current(request, sessionEpoch)) {
        if (mounted && request == _request) {
          state = DegreeState(audit: state.audit);
        }
        return;
      }
      await _session.cacheFor(
        id,
        () => _current(request, sessionEpoch),
        () => _ref.read(storageProvider).setEduDegreeAudit(id, audit.encode()),
      );
      if (_current(request, sessionEpoch)) {
        state = DegreeState(audit: audit);
      } else if (mounted && request == _request) {
        state = DegreeState(audit: state.audit);
      }
    } catch (e) {
      if (!_current(request, sessionEpoch)) {
        if (mounted && request == _request) {
          state = DegreeState(audit: state.audit);
        }
        return;
      }
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
