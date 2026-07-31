/// Explicit Liquid projection surface for custom Dart objects in cast context.
///
/// Implement this on objects that hooks keep as rich Dart values but that
/// templates must read via dotted Liquid access. [toLiquid] should return a
/// Liquid-compatible value: a primitive, a string-keyed map, a list, another
/// [FoundryLiquidView], or a liquify `Drop`.
///
/// Projection runs only at template render time; hooks continue to see the
/// original object on `FoundryContext`.
// Intentionally a one-member protocol so mold authors can implement a clear
// Liquid surface without depending on liquify `Drop`.
// ignore: one_member_abstracts
abstract interface class FoundryLiquidView {
  /// Returns the Liquid-facing representation of this object.
  Object? toLiquid();
}
