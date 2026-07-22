/// Escapes Liquid-like openers so pattern file contents survive as literal
/// text when later rendered by Foundry's template engine.
///
/// Best-effort per-delimiter pre-pass: each source `{{` becomes
/// `{{ "{{" }}` and each source `{%` becomes `{{ "{%" }}`, so accidental
/// braces render as literals while later transforms can still inject live
/// Liquid tags. Binary files should not be passed through this helper —
/// copy them byte-for-byte instead.
String liquidizeTemplateContents(String source) {
  if (!_looksLikeLiquid(source)) {
    return source;
  }
  // Escape `{{` before `{%` so the escape payloads themselves are not
  // re-processed as Liquid openers.
  return source.replaceAll('{{', '{{ "{{" }}').replaceAll('{%', '{{ "{%" }}');
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
