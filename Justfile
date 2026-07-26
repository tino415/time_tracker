# Common build / test commands for time_tracker.
# `just` (or `nx just`) lists recipes; `just <name>` runs one.
#
# Notes:
#  * Run everything through the nix env: `nx just <recipe>`.
#  * drift codegen needs --force-jit on this toolchain (plain build_runner hits
#    a "dart compile does not support build hooks" error). Run `just gen` after
#    changing the schema (lib/data/database.dart).
#  * Release APKs fail on this aarch64 host (missing gen_snapshot); APKs are
#    --debug (JIT). Fine for on-device testing.

# List recipes
default:
    @just --list

# Static analysis
analyze:
    flutter analyze

# Unit + widget tests. --no-pub skips the implicit pub get; run `flutter pub get`
# yourself after changing dependencies.
test:
    flutter test --no-pub

# Regenerate drift code (database.g.dart) after a schema change.
gen:
    flutter pub run build_runner build --force-jit

# Watch + regenerate on change.
watch:
    flutter pub run build_runner watch --force-jit

# Build the offline-first web PWA (local drift-wasm; no backend).
web:
    flutter build web

# Web dev server on dev.local:4116.
up:
    flutter run -d web-server --web-hostname dev.local --web-port 4116

# Debug APK for the phone (arm64).
phone-apk:
    flutter build apk --debug --target-platform android-arm64

# Debug APK for the watch + Wear emulator (fat 32+64), for the watch phase.
watch-apk:
    flutter build apk --debug --target-platform android-arm,android-arm64

# flutter clean
clean:
    flutter clean
