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

# A subset of the same suite, for a tight edit/run loop. Takes any `flutter test`
# arguments — one or more files, or a name filter:
#   just test-only test/calendar_test.dart
#   just test-only --plain-name moveBoundary
#   just test-only test/calendar_test.dart test/domain_test.dart
test-only +args:
    flutter test --no-pub {{args}}

# Only what failed, with the full failure output and no progress spam.
test-failures +args="test":
    flutter test --no-pub --reporter=failures-only {{args}}

# On-device end-to-end test of the phone flow. Needs a running emulator — start
# one with the `droid` CLI. `flutter devices` lists the ids; override with
# `just e2e device=<id>` if the emulator came up on a different port.
e2e device="127.0.0.1:5557":
    flutter test integration_test/flow_test.dart --no-pub -d {{device}}

# The Wear OS shell on the watch emulator. A different suite, not the phone one:
# the watch has its own shell because the phone layout does not fit a 227x227
# round screen.
e2e-watch device="127.0.0.1:5555":
    flutter test integration_test/watch_flow_test.dart --no-pub -d {{device}}

# Regenerate drift code (database.g.dart) after a schema change.
gen:
    flutter pub run build_runner build --force-jit

# Watch + regenerate on change.
watch:
    flutter pub run build_runner watch --force-jit

# Build the offline-first web PWA (local drift-wasm; no backend).
web:
    flutter build web

# Serve the built PWA with COOP/COEP, which `flutter run -d web-server` cannot
# set — without them the page is not cross-origin isolated and drift drops to a
# slower OPFS implementation. Build first with `just web`.
web-serve port="4242":
    dart tool/serve_web.dart build/web {{port}}

# Install the browser tooling used by `web-smoke` (playwright-core). The browser
# binaries themselves come from the environment, not from npm.
node-deps:
    npm install --no-audit --no-fund

# Build, serve, and smoke-test the PWA in a real browser: cross-origin
# isolation, OPFS, persistence, data surviving a reload, and a reload with the
# network cut. Chromium runs headed under Xvfb — headless swiftshader paints
# blank CanvasKit frames.
web-smoke port="4242": web
    xvfb-run -a node tool/web_smoke.mjs {{port}}

# Web dev server on dev.local:4116. NOTE: 4116 collides with gym_tracker, and
# this device cannot send COOP/COEP — prefer `just web-serve`.
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
