/// Result of interpreting a pasted work-task string like `CU-1234 Fix the thing`.
class PastedTask {
  const PastedTask({required this.name, this.externalId});

  /// The activity name (the full trimmed paste — the id stays visible in it).
  final String name;

  /// The extracted tracker id (`CU-1234`), or null if the paste had no id prefix.
  final String? externalId;
}

final _idPrefix = RegExp(r'^([A-Za-z]{1,10}-\d+)\b');

/// Interpret a pasted string: if it begins with a `LETTERS-digits` token (e.g.
/// `CU-1234`, `JIRA-42`), lift that out as [PastedTask.externalId]; the name is
/// always the whole trimmed string so the id remains readable in the timeline.
PastedTask parsePastedTask(String raw) {
  final text = raw.trim();
  final m = _idPrefix.firstMatch(text);
  return PastedTask(name: text, externalId: m?.group(1)?.toUpperCase());
}
