/// Writes a single log [message].
typedef LogSink = void Function(String message);

/// Emits progress, info, warning, and error output on behalf of a running
/// hook.
///
/// The default sinks write to `stdout`/`stderr` via `print`; callers (e.g.
/// tests, or the CLI's TUI boundary) may inject their own sinks to capture or
/// restyle output.
class Logger {
  /// Creates a [Logger], optionally overriding where each log level writes.
  ///
  /// All sinks default to [print] when omitted.
  Logger({
    LogSink? onInfo,
    LogSink? onWarn,
    LogSink? onError,
    LogSink? onProgress,
  })  : _onInfo = onInfo ?? print,
        _onWarn = onWarn ?? print,
        _onError = onError ?? print,
        _onProgress = onProgress ?? print;

  final LogSink _onInfo;
  final LogSink _onWarn;
  final LogSink _onError;
  final LogSink _onProgress;

  /// Logs an informational [message].
  void info(String message) => _onInfo(message);

  /// Logs a warning [message].
  void warn(String message) => _onWarn('[WARN] $message');

  /// Logs an error [message].
  void error(String message) => _onError('[ERROR] $message');

  /// Starts a long-running step described by [message] and returns a
  /// [Progress] handle used to report how it ends.
  Progress progress(String message) {
    _onProgress(message);
    return Progress._(message: message, onUpdate: _onProgress);
  }
}

/// A handle for a long-running step started via [Logger.progress].
///
/// Exactly one of [complete], [fail], or [cancel] is expected to be called
/// once the step is done; [update] may be called any number of times before
/// that to report intermediate status.
class Progress {
  Progress._({required String message, required LogSink onUpdate})
      : _onUpdate = onUpdate,
        _message = message;

  final LogSink _onUpdate;
  final String _message;

  /// Reports intermediate status for the running step.
  void update(String message) => _onUpdate(message);

  /// Marks the step as successfully completed.
  ///
  /// Reports [message] when provided, otherwise the original step message.
  void complete([String? message]) =>
      _onUpdate('[DONE] ${message ?? _message}');

  /// Marks the step as failed.
  ///
  /// Reports [message] when provided, otherwise the original step message.
  void fail([String? message]) => _onUpdate('[FAIL] ${message ?? _message}');

  /// Marks the step as cancelled before completion.
  ///
  /// Reports [message] when provided, otherwise the original step message.
  void cancel([String? message]) =>
      _onUpdate('[CANCELLED] ${message ?? _message}');
}
