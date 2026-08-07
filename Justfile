# Build / test / run commands for time_tracker.
#
# `just` lists them; `just <recipe>` runs one. Each carries a [doc('…')]
# one-liner for that listing and, where the reasoning is not obvious, a comment
# above it with the why. The listing is the reference — nothing duplicates it
# elsewhere, so it cannot go stale.
#
# Two standing constraints:
#  * drift codegen needs --force-jit (plain build_runner hits a "dart compile
#    does not support build hooks" error). Run `just gen` after changing the
#    schema in lib/data/database.dart.
#  * Every APK here is --debug. Release builds need a toolchain that can produce
#    gen_snapshot for the target, which not every host has; debug is JIT and
#    slower, but installs and runs fine on a device.

[doc('List these recipes')]
default:
    @just --list

[doc('Static analysis')]
analyze:
    flutter analyze

# --no-pub skips the implicit pub get; run `flutter pub get` yourself after
# changing dependencies.
[doc('Unit + widget tests')]
test:
    flutter test --no-pub

# Takes any `flutter test` arguments — one or more files, or a name filter:
#   just test-only test/calendar_test.dart
#   just test-only --plain-name moveBoundary
#   just test-only test/calendar_test.dart test/domain_test.dart
[doc('A subset of the suite, for a tight edit/run loop')]
test-only +args:
    flutter test --no-pub {{args}}

[doc('The suite, printing only failures')]
test-failures +args="test":
    flutter test --no-pub --reporter=failures-only {{args}}

# Needs a running emulator or a connected device. `flutter devices` lists the
# ids; a phone paired over wifi gets a new ip:port each pairing, so pass it
# explicitly when it changes.
[doc('On-device run of the phone flow')]
e2e device="127.0.0.1:5557":
    flutter test integration_test/flow_test.dart --no-pub -d {{device}}

# A *different suite*, not the phone one on a smaller screen: the watch has its
# own shell because the phone layout does not fit a 227x227 round display.
[doc('On-device run of the watch shell')]
e2e-watch device="127.0.0.1:5555":
    flutter test integration_test/watch_flow_test.dart --no-pub -d {{device}}

[doc('Regenerate drift code after a schema change')]
gen:
    flutter pub run build_runner build --force-jit

[doc('Regenerate drift code on every change')]
watch:
    flutter pub run build_runner watch --force-jit

[doc('Build the web PWA into build/web')]
web:
    flutter build web

# The *built* bundle rather than a dev server, because that is the real artefact
# — service worker, offline reload, installability, hashed assets — and a dev
# build has none of it. No hot reload as a result; re-run to pick up changes.
#
# Binds 0.0.0.0 so a browser on another machine can reach it.
[doc('Build and serve the PWA on :4242 — the way to review it')]
up port="4242": web
    dart tool/serve_web.dart build/web {{port}}

# Only playwright-core comes from npm; the browser binaries are expected on the
# machine already, found via PLAYWRIGHT_BROWSERS_PATH. package.json pins
# playwright to a version matching those binaries.
[doc('Install the browser tooling web-smoke needs (playwright-core)')]
node-deps:
    npm install --no-audit --no-fund

# Checks cross-origin isolation, OPFS, persistence, data surviving a reload, and
# a reload with the network cut. Runs headed under Xvfb — headless swiftshader
# paints blank CanvasKit frames.
[doc('Build, serve, and smoke-test the PWA in a real browser')]
web-smoke port="4242": web
    xvfb-run -a node tool/web_smoke.mjs {{port}}

# Runs the real Worker on workerd against a local D1 — no account, no deploy, no
# network. The Dart suite proves the client's half against a FakeServer written
# to mirror this Worker; if the Worker diverges from that model, only this
# notices.
[doc('Smoke-test the sync worker locally')]
worker-smoke port="4243":
    node tool/worker_smoke.mjs {{port}}

# Apply the schema to a local D1. Safe to re-run — the schema is all
# CREATE TABLE IF NOT EXISTS — and needed once before `worker-dev` will answer.
[doc('Create or update the local sync database')]
worker-db:
    npx wrangler d1 execute track-sync --local \
        --config worker/wrangler.toml \
        --persist-to worker/.wrangler/dev-state \
        --file worker/schema.sql

# A real Worker on a real local D1, for exercising sync from the app. The token
# is a throwaway: it only guards a database on this machine, and the deployed one
# takes its token from `wrangler secret` instead.
#
# Build the client against it — same origin as wherever the app is served, so the
# request is not cross-origin and not mixed content:
#   flutter build web --dart-define=SYNC_URL=https://<host>/api/ \
#                     --dart-define=SYNC_TOKEN=local-dev-token
# with /api/ reverse-proxied to this port, prefix stripped.
[doc('Run the sync worker locally against a persistent D1')]
worker-dev port="4243" token="local-dev-token":
    npx wrangler dev --config worker/wrangler.toml \
        --port {{port}} --ip 0.0.0.0 \
        --var SYNC_TOKEN:{{token}} \
        --persist-to worker/.wrangler/dev-state

[doc('Debug APK for a phone (arm64)')]
phone-apk:
    flutter build apk --debug --target-platform android-arm64

# Fat 32+64: Wear devices are often armeabi-v7a, and an arm64-only APK will not
# install on them.
[doc('Debug APK for a watch (fat 32+64)')]
watch-apk:
    flutter build apk --debug --target-platform android-arm,android-arm64

# One APK serves both form factors; only the ABI differs.
#   just deploy device=192.168.1.158:36915
[doc('Build and install on a phone')]
deploy device: phone-apk
    flutter install -d {{device}} --debug

[doc('Build and install on a watch')]
deploy-watch device: watch-apk
    flutter install -d {{device}} --debug

[doc('flutter clean')]
clean:
    flutter clean
