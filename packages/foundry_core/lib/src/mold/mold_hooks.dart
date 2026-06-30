import 'package:meta/meta.dart';

/// Optional lifecycle hook paths declared in a mold manifest.
@immutable
final class MoldHooks {
  /// Creates [MoldHooks].
  const MoldHooks({
    this.prepare,
    this.shape,
    this.finish,
  });

  /// Relative path to the prepare hook Dart file.
  final String? prepare;

  /// Relative path to the shape hook Dart file.
  final String? shape;

  /// Relative path to the finish hook Dart file.
  final String? finish;

  /// Whether any hook path is declared.
  bool get isEmpty => prepare == null && shape == null && finish == null;
}
