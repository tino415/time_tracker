import 'package:web/web.dart' as web;

/// `any-pointer: fine` rather than `pointer: fine` — a touchscreen laptop has
/// both, and the question is whether a mouse is *available*, not which one
/// drove the last event.
bool probeHasPointer() => web.window.matchMedia('(any-pointer: fine)').matches;
