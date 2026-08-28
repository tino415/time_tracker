/// Ask the platform whether a mouse — or a trackpad acting like one — is
/// available, so text selection can be offered only where dragging costs
/// nothing.
///
/// Only the web implementation asks the browser anything: elsewhere the
/// target platform itself already answers the question.
library;

export 'pointer_probe_native.dart' if (dart.library.js_interop) 'pointer_probe_web.dart';
