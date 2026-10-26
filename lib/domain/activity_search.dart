import '../data/database.dart';

List<String> withAlias(List<String> aliases, String typed) {
  final alias = typed.trim();
  if (alias.isEmpty || aliases.contains(alias)) return aliases;
  return [...aliases, alias];
}

bool activityMatchesQuery(Activity a, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return a.name.toLowerCase().contains(q) ||
      (a.externalId?.toLowerCase().contains(q) ?? false) ||
      a.aliases.any((alias) => alias.toLowerCase().contains(q));
}
