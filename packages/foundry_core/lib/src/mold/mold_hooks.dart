import 'package:meta/meta.dart';

/// Standard lifecycle hook file paths relative to a mold directory.
///
/// Hooks are optional; missing files are treated as no-ops at cast time.
@immutable
abstract final class MoldHooks {
  /// Directory containing lifecycle hook Dart files.
  static const String directory = 'hooks';

  /// Prepare-phase hook filename.
  static const String prepare = 'prepare.dart';

  /// Shape-phase hook filename.
  static const String shape = 'shape.dart';

  /// Finish-phase hook filename.
  static const String finish = 'finish.dart';

  /// Relative path to the prepare hook from the mold root.
  static const String preparePath = '$directory/$prepare';

  /// Relative path to the shape hook from the mold root.
  static const String shapePath = '$directory/$shape';

  /// Relative path to the finish hook from the mold root.
  static const String finishPath = '$directory/$finish';

  /// All standard hook paths in lifecycle order.
  static const List<String> allPaths = [
    preparePath,
    shapePath,
    finishPath,
  ];
}
