/// What the host told us about where the local database lives.
///
/// The PWA's promise is that it keeps working without a network, which only
/// holds if the browser does not evict the database. Browsers grant "persistent"
/// storage (exempt from eviction under pressure) on request, so the app asks and
/// then reports the answer rather than assuming it.
class StorageStatus {
  const StorageStatus({
    required this.kind,
    required this.persistent,
    required this.crossOriginIsolated,
    this.usageBytes,
    this.quotaBytes,
  });

  /// Where the data physically is, in the host's terms — `native` off the web,
  /// otherwise the browser bucket ("opfs", "indexeddb", …).
  final String kind;

  /// True when the browser has promised not to evict this origin's storage.
  /// Off the web this is trivially true: it is an ordinary file.
  final bool persistent;

  /// Whether the page is cross-origin isolated (COOP + COEP), which is what
  /// lets drift use the shared-memory OPFS implementation. Not required for the
  /// app to work — drift falls back — but it is the fastest path.
  final bool crossOriginIsolated;

  final int? usageBytes;
  final int? quotaBytes;

  /// Non-web: a real file on disk, nothing to negotiate.
  static const native = StorageStatus(
    kind: 'native',
    persistent: true,
    crossOriginIsolated: false,
  );

  /// One-line summary for the UI, e.g. `opfs · persistent · isolated`.
  String get summary {
    final bits = <String>[
      kind,
      persistent ? 'persistent' : 'evictable',
      if (crossOriginIsolated) 'isolated',
    ];
    return bits.join(' · ');
  }
}
