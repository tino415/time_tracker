# time_tracker

### Backlog

- [ ] Calendar and Reports label yesterday "Today" on the day after the spring DST change: their `_dayLabel` floors a 23-hour `difference().inDays` to 0; the timeline already compares calendar dates #bug
- [ ] CI/CD for the release APK instead of building it on dev: release builds need an x64 runner, since Flutter ships no aarch64 gen_snapshot; GitHub Actions runs the PR checks; a new release key, with a `.dev` id suffix on debug builds so both install side by side (the key change means an uninstall, so the data has to come back through sync); APKs published as GitHub Release assets and installed by a just recipe; what triggers the Worker deploy is still open #chore
