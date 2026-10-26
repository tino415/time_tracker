import '../data/database.dart';

List<String> parseAliases(String raw) => [
  for (final part in raw.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];

String formatAliases(List<String> aliases) => aliases.join(', ');

bool activityMatchesQuery(Activity a, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return a.name.toLowerCase().contains(q) ||
      (a.externalId?.toLowerCase().contains(q) ?? false) ||
      a.aliases.any((alias) => alias.toLowerCase().contains(q));
}
