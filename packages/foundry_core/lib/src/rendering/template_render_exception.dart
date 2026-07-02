/// Thrown when rendering a mold's `template/` directory fails.
final class TemplateRenderException implements Exception {
  /// Creates a [TemplateRenderException] with a human-readable [message].
  const TemplateRenderException(this.message);

  /// Human-readable description of the problem.
  final String message;

  @override
  String toString() => 'TemplateRenderException: $message';
}
