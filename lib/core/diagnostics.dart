/// Category-tagged diagnostics logging (plan 28).
///
/// The logger foundation is category-aware from the start: every
/// record carries a [DiagCategory], and the enabled category set
/// is selectable in the settings UI, so "AKE only", "UI only" or
/// "EPG only" tracing can be turned on independently. The master
/// switch and the category set are persisted by the app layer
/// (app/debug_log.dart); this file is the platform-free core.
///
/// HARD RULE: records carry stage transitions, error
/// classifications, HTTP statuses, AKE response codes, byte
/// counts and durations ONLY. Credential material and session
/// keys (the device certificate and private key, the
/// authentication key, exchange keys, content keys, nonces,
/// signatures, MACs) must NEVER be logged, in any mode. The rule
/// is enforced by construction — no call site receives a key
/// value to format — and by the audit tests in
/// test/debug_log_test.dart and test/dtcp_test.dart.
library;

/// One diagnostics category, aligned with the module structure.
enum DiagCategory {
  /// DTCP-IP AKE (authentication, RTT, exchange keys, SRM).
  ake,

  /// Playback session lifecycle (engine + loopback proxy).
  playback,

  /// Content HTTP fetches (HEAD / GET).
  network,

  /// Programme guide (EPG) fetches.
  epg,

  /// nasne discovery (SSDP / subnet scan).
  discovery,

  /// UI-level events (e.g. a playback failure shown to the user).
  ui,
}

/// A category-filtered diagnostics sink handle.
///
/// The default everywhere is [DiagLog.none] (records nothing), so
/// library code can log unconditionally; the app injects a real
/// logger only when the user enables debug mode.
class DiagLog {
  const DiagLog(this._write, this._isEnabled);

  /// A logger that discards everything.
  const DiagLog.none()
      : _write = _discard,
        _isEnabled = _never;

  static void _discard(DiagCategory category, String message) {}

  static bool _never(DiagCategory category) => false;

  final void Function(DiagCategory category, String message) _write;
  final bool Function(DiagCategory category) _isEnabled;

  /// Whether [category] currently records.
  bool enabledFor(DiagCategory category) => _isEnabled(category);

  /// Records [message] under [category] when enabled.
  void call(DiagCategory category, String message) {
    if (_isEnabled(category)) _write(category, message);
  }
}
