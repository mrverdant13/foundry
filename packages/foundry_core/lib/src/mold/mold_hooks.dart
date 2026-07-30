import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

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

  /// Optional author policy filename (`requiredHooks` getter).
  ///
  /// Hosts may load this file to decide which phases are required. Core does
  /// not execute it; see [policyPath].
  static const String policy = 'policy.dart';

  /// Relative path to the prepare hook from the mold root.
  static final String preparePath = p.join(directory, prepare);

  /// Relative path to the shape hook from the mold root.
  static final String shapePath = p.join(directory, shape);

  /// Relative path to the finish hook from the mold root.
  static final String finishPath = p.join(directory, finish);

  /// Relative path to the optional hook policy file from the mold root.
  static final String policyPath = p.join(directory, policy);

  /// All standard hook paths in lifecycle order.
  ///
  /// Does not include [policyPath]; policy is metadata for hosts, not a
  /// lifecycle phase.
  static final List<String> allPaths = [
    preparePath,
    shapePath,
    finishPath,
  ];
}
