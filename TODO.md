# time_tracker

### Backlog

- [ ] Build debug APKs and run the device recipes in the dev container: its x86_64 SDK tools (aapt2, adb) don't run there yet #chore
- [ ] Calendar and Reports label yesterday "Today" on the day after the spring DST change: their `_dayLabel` floors a 23-hour `difference().inDays` to 0; the timeline already compares calendar dates #bug
