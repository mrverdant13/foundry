/// Thrown when a mold cannot be derived from a pattern directory.
///
/// Covers invalid pattern paths, destination conflicts without `force`, and
/// filesystem failures while staging or writing the derived mold.
final class MoldDeriveException implements Exception {
  /// Creates a [MoldDeriveException].
  const MoldDeriveException(this.message);

  /// Human-readable description of why derive failed.
  final String message;

  @override
  String toString() => 'MoldDeriveException: $message';
}
