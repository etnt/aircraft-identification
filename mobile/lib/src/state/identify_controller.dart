/// The identify controller: an idle -> loading -> (success | failure)
/// state machine over [AircraftService], exposed via Riverpod.
///
/// `success` carries the full [IdentifyResult] (including the "clear skies"
/// case, `confidence == none`); `failure` carries a stable error code and
/// friendly message so the UI can offer retry.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/identify_config.dart';
import '../data/aircraft_service.dart';
import '../data/errors.dart';
import '../domain/models.dart';

/// UI-facing state for the home screen.
sealed class IdentifyUiState {
  const IdentifyUiState();
}

/// Nothing requested yet.
class IdentifyIdle extends IdentifyUiState {
  const IdentifyIdle();
}

/// A request is in flight.
class IdentifyLoading extends IdentifyUiState {
  const IdentifyLoading();
}

/// The call completed (may still be a "clear skies" no-result).
class IdentifySuccess extends IdentifyUiState {
  final IdentifyResult result;
  const IdentifySuccess(this.result);
}

/// The call failed with a classified error.
class IdentifyFailure extends IdentifyUiState {
  final IdentifyError code;
  final String message;
  const IdentifyFailure(this.code, this.message);
}

/// Drives identifications and publishes [IdentifyUiState] transitions.
class IdentifyController extends StateNotifier<IdentifyUiState> {
  final AircraftService _service;

  IdentifyController(this._service) : super(const IdentifyIdle());

  /// Run an identification for [config], ignoring re-entrant taps while a
  /// request is already in flight.
  Future<void> identify(IdentifyConfig config) async {
    if (state is IdentifyLoading) return;
    state = const IdentifyLoading();

    final result = await _service.identify(config);

    if (result.status == IdentifyStatus.error) {
      final code = result.errorCode is IdentifyError
          ? result.errorCode as IdentifyError
          : IdentifyError.openskyBadResponse;
      state = IdentifyFailure(
        code,
        result.message ?? messageForError(code),
      );
      return;
    }

    state = IdentifySuccess(result);
  }

  /// Return to the initial prompt state.
  void reset() => state = const IdentifyIdle();
}

/// Override this in `main` (or tests) to supply the concrete service.
final aircraftServiceProvider = Provider<AircraftService>((ref) {
  return AircraftService.networked();
});

/// The controller the home screen watches.
final identifyControllerProvider =
    StateNotifierProvider<IdentifyController, IdentifyUiState>((ref) {
  return IdentifyController(ref.watch(aircraftServiceProvider));
});
