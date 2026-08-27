/// Ask the host to keep the local database around, and report what it said.
///
/// Only the web implementation does anything: elsewhere the database is a file
/// and there is nothing to negotiate.
library;

export 'storage_probe_native.dart' if (dart.library.js_interop) 'storage_probe_web.dart';
