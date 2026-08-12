import '../data/database.dart';

/// The catch-all activity behind "start now, name it later".
///
/// Switching normally means deciding *what* you are switching to, and that
/// decision costs seconds you are usually not willing to spend — so the naming
/// ends up charged to whatever you were doing before, which is precisely
/// backwards. Starting the boundary against this activity makes the tap
/// instantaneous; the block is re-pointed at a real activity afterwards, keeping
/// its original start, so the time spent naming belongs to the thing named.
///
/// The id is a fixed string rather than a uuid on purpose: every device derives
/// the same one, so two devices that each create it converge on a single row
/// under version-LWW instead of ending up with two catch-alls.
///
/// That also means this value can never change: it is the row's identity on
/// every device that has ever synced. So the code says "unsorted" and the user
/// reads "Unnamed" — the identifiers here are named after the persisted id, not
/// after the label, and [kUnsortedName] is the only thing a person sees.
const kUnsortedActivityId = 'unsorted';

/// What the catch-all is called everywhere a person can read it: the timeline,
/// the activity list, the Now hero, the watch and the CSV export.
///
/// Deliberately the *stored* name rather than a literal at each render site.
/// Those literals are how this drifted before — the timeline and the activity
/// list showed the row's name ("Unsorted") while Now and the watch printed their
/// own "unnamed", so the same block was two different words on two screens.
const kUnsortedName = 'Unnamed';

/// The name shipped before [kUnsortedName] settled, corrected on sight by
/// `ensureUnsorted`. Kept only so that correction can recognise it.
const kUnsortedLegacyName = 'Unsorted';

/// Deliberately the muted grey rather than a palette colour — unsorted time is a
/// gap to be filled in, not a category to look at.
const kUnsortedColor = '#9A9B95';

bool isUnsorted(Activity activity) => activity.syncId == kUnsortedActivityId;

/// True when [activities] is *only* the catch-all, i.e. the block is still
/// waiting to be named. A block tagged with both the catch-all and a real
/// activity has been answered, so it does not count.
bool isUnsortedSet(List<Activity> activities) =>
    activities.length == 1 && isUnsorted(activities.first);
