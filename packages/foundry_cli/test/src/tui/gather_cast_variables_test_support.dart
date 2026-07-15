import 'dart:async';

import 'package:nocterm/nocterm.dart';

/// A [TerminalBackend] driven entirely in-memory, so
/// `gatherCastVariablesInteractively` can be exercised end-to-end (through
/// Nocterm's real `runApp`/input pipeline) without a real terminal.
class FakeTerminalBackend implements TerminalBackend {
  final _inputController = StreamController<List<int>>();
  final output = StringBuffer();

  @override
  void writeRaw(String data) {
    output.write(data);
  }

  @override
  Size getSize() => const Size(80, 24);

  @override
  bool get supportsSize => true;

  @override
  Stream<List<int>>? get inputStream => _inputController.stream;

  @override
  Stream<Size>? get resizeStream => null;

  @override
  Stream<void>? get shutdownStream => null;

  @override
  void enableRawMode() {}

  @override
  void disableRawMode() {}

  @override
  bool get isAvailable => true;

  @override
  void requestExit([int exitCode = 0]) {}

  @override
  void notifySizeChanged(Size newSize) {}

  @override
  void dispose() {
    unawaited(_inputController.close());
  }

  /// Sends raw input bytes as if typed at the terminal.
  void sendBytes(List<int> bytes) => _inputController.add(bytes);
}
