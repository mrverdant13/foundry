/// Escapes Liquid-like sequences so pattern file contents survive as literal
/// text when later rendered by Foundry's template engine.
///
/// Best-effort: when [source] contains `{{` or `{%`, the entire string is
/// wrapped in `{% raw %}…{% endraw %}`. Files that already use `{% raw %}` /
/// `{% endraw %}`, or that embed those tags inside other constructs, may need
/// hand editing after derive. Binary files should not be passed through this
/// helper — copy them byte-for-byte instead.
String liquidizeTemplateContents(String source) {
  if (!_looksLikeLiquid(source)) {
    return source;
  }
  return '{% raw %}$source{% endraw %}';
}

/// Whether [bytes] look like binary content that should not be liquidized.
///
/// Detection is intentionally simple (NUL bytes). Derive copies such files
/// into `template/` unchanged.
bool looksLikeBinaryTemplateBytes(List<int> bytes) {
  return bytes.contains(0);
}

bool _looksLikeLiquid(String source) {
  return source.contains('{{') || source.contains('{%');
}
