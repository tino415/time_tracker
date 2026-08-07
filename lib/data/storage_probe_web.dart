import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'storage_status.dart';

/// Request persistent storage and report what the browser granted.
///
/// `persist()` is what stops the browser evicting the database when the device
/// is short on space — without it an offline-first PWA can silently lose
/// everything it has recorded. Browsers grant it to installed or sufficiently
/// engaged origins and refuse it otherwise; either way the answer is surfaced
/// rather than assumed.
///
/// Every call is defensive: `navigator.storage` is absent on older browsers and
/// in insecure contexts, and a rejected promise here must not stop the app from
/// starting.
Future<StorageStatus> probeStorage() async {
  final isolated = web.window.crossOriginIsolated;

  final storage = web.window.navigator.storage;
  var persistent = false;
  int? usage;
  int? quota;

  try {
    persistent = (await storage.persisted().toDart).toDart;
    if (!persistent) {
      persistent = (await storage.persist().toDart).toDart;
    }
  } catch (_) {
    // Unsupported or blocked — the app still works, it is just evictable.
  }

  try {
    final estimate = await storage.estimate().toDart;
    usage = estimate.usage;
    quota = estimate.quota;
  } catch (_) {
    // Estimates are advisory; their absence is not an error.
  }

  return StorageStatus(
    kind: await _storageKind(),
    persistent: persistent,
    crossOriginIsolated: isolated,
    usageBytes: usage,
    quotaBytes: quota,
  );
}

/// Which browser bucket drift ended up using. Probing for the OPFS API is the
/// closest we can get without drift exposing its chosen implementation: if the
/// origin has an OPFS root and the page can reach it, that is what drift picked;
/// otherwise it fell back to IndexedDB.
Future<String> _storageKind() async {
  try {
    final root = await web.window.navigator.storage.getDirectory().toDart;
    return root.isDefinedAndNotNull ? 'opfs' : 'indexeddb';
  } catch (_) {
    return 'indexeddb';
  }
}
