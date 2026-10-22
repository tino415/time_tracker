# time_tracker

### Backlog

- [ ] Build debug APKs and run the device recipes in the dev container: its x86_64 SDK tools (aapt2, adb) don't run there yet #chore
- [ ] Reports: switching to week lands a week late across the spring DST change — `_setPeriod` divides whole days by 7, and a 6d23h gap truncates (1 April, 25 March selected, shows This week); round hours to weeks instead #bug
- [ ] Wear OS tile for the current activity: faces like Samsung's Simple Digital take no third-party complication (their line is a built-in candidate, their one androidx slot accepts no types) #feature
