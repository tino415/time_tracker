/// Which build this is, stamped in by the Justfile.
///
/// Exists because "is that the version I just installed?" came up constantly and
/// could only be answered by inference. Three clients, two of them awkward to
/// inspect, and an installer that reports "Success" either way.
///
/// Format is `<git describe><-dirty>@<MM-DDTHH:MM>` — the dirty marker separates
/// "this is the code in git" from "this came off a working tree", and the
/// timestamp separates two builds of the same commit, which is most of what
/// happens while debugging.
const kBuildId = String.fromEnvironment('BUILD_ID', defaultValue: 'dev');
