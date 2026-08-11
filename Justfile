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

# Reads .env from this directory if present, so the sync settings do not have to
# be retyped on every build. It is gitignored: SYNC_TOKEN is the whole security
# boundary. See .env.example.
set dotenv-load := true

# Where the sync server lives, baked into every client build. Put it in .env, or
# pass it for one command:
#
#   SYNC_URL=https://host/ just deploy <serial>
#
# Only the URL: the token identifies an *account* and is set up in the app, not
# compiled in. A token in a web build is served to everyone who loads the page,
# and it could only ever be one account's.
#
# Unset, the client is built without a server and never offers sync — the app is
# complete without it. The URL must be reachable *from the device* over HTTPS:
# Android blocks cleartext, and on the web anything but a secure context has no
# storage to sync in the first place.
sync_defines := if env_var_or_default("SYNC_URL", "") != "" {
    "--dart-define=SYNC_URL=" + env_var("SYNC_URL")
} else { "" }

# Stamped into every client so you can tell, on the device, exactly what is
# running there. `--dirty` matters more than the commit: it is the difference
# between "this is the code in git" and "this came off someone's working tree".
# The timestamp distinguishes two builds of the same commit, which is most of
# what happens during a debugging session.
build_id := `git describe --always --dirty --tags 2>/dev/null || echo unknown` + "@" + `date -u +%m-%dT%H:%M`

# Every recipe that produces a client passes both of these.
client_defines := sync_defines + " --dart-define=BUILD_ID=" + build_id

# From android/app/build.gradle.kts. Hardcoded rather than parsed out of it: it
# changes about as often as the app is renamed.
package_id := "com.otin.time_tracker"

[doc('List these recipes')]
default:
    @just --list

# "What is running where" — the question that costs the most time whenever two
# clients disagree, and one that used to need `git log`, file timestamps,
# `wrangler deployments` and a database pull to answer.
#
# Reads only, and nothing privileged: the repo, the deployed bundle over plain
# HTTP, and each attached device's own copy of the database. The deployed stamp
# comes out of the shipped bundle rather than from Cloudflare's deployment list,
# because what is *serving* is the question — a deploy that half-succeeded shows
# up here and not there.
[doc('What is running where: repo, deployed bundle, and every attached device')]
status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "REPO"
    printf '  head    %s\n' "$(git log -1 --format='%h %s')"
    if [ -n "$(git status --porcelain -- lib test worker tool Justfile 2>/dev/null)" ]; then
        printf '  tree    dirty — a build now would not match any commit\n'
    else
        printf '  tree    clean\n'
    fi
    printf '  next    a build now stamps %s\n' '{{ build_id }}'
    echo
    url='{{ env_var_or_default("SYNC_URL", "") }}'
    if [ -z "$url" ]; then
        echo "DEPLOYED  no SYNC_URL in .env — clients built here would have no server"
    else
        echo "DEPLOYED  $url"
        stamp=$(curl -fsS --max-time 20 "${url%/}/main.dart.js" 2>/dev/null \
            | grep -oE '[A-Za-z0-9._-]+@[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}' | head -1)
        printf '  build   %s\n' "${stamp:-unreachable, or no build stamp in the bundle}"
    fi
    echo
    echo "DEVICES"
    found=0
    for serial in $(adb devices | awk 'NR>1 && $2 == "device" { print $1 }'); do
        found=1
        printf '  %s (%s)\n' "$serial" "$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
        just _sync_state "$serial" '    '
    done
    [ "$found" = 1 ] || echo "  none attached"

[doc('Static analysis')]
analyze:
    flutter analyze

# Needed after changing pubspec.yaml: the test and build recipes pass --no-pub so
# an ordinary run does not stop to re-resolve.
[doc('Resolve Dart dependencies')]
deps:
    flutter pub get

# --no-pub skips the implicit pub get — see `just deps`.
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

# The _headers copy is not incidental: `flutter build web` copies everything in
# web/ *except* files starting with an underscore, so the response headers the
# deployed app needs — cross-origin isolation, no-store on the shell — would
# silently not ship.
[doc('Build the web PWA into build/web')]
web:
    flutter build web {{client_defines}}
    cp web/_headers build/web/_headers

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
#
# A different default port from `worker-dev` on purpose: run both at once and
# the test would silently exercise the dev worker instead — its own database,
# its own token, and a wall of failures that look like a broken Worker.
[doc('Smoke-test the sync worker locally')]
worker-smoke port="4245":
    node tool/worker_smoke.mjs {{port}}

# Apply the schema to a local D1. Safe to re-run — the schema is all
# CREATE TABLE IF NOT EXISTS — and needed once before `worker-dev` will answer.
[doc('Create or update the local sync database')]
worker-db:
    npx wrangler d1 execute track-sync --local \
        --config worker/wrangler.toml \
        --persist-to worker/.wrangler/dev-state \
        --file worker/schema.sql

# A real Worker on a real local D1, for exercising sync from the app. There is
# no server-side secret to pass: a token identifies an account and is created
# through the app, so this database simply starts with no accounts in it.
#
# Point a client at it with SYNC_URL. Serving the app from the same origin — a
# reverse proxy at /api/, prefix stripped — avoids CORS, which is the same
# reason the deployed Worker serves the PWA itself.
[doc('Run the sync worker locally against a persistent D1')]
worker-dev port="4243":
    npx wrangler dev --config worker/wrangler.toml \
        --port {{port}} --ip 0.0.0.0 \
        --persist-to worker/.wrangler/dev-state

# Uploads the Worker *and* build/web as its static assets, so the app and the API
# end up on one origin. Depends on `web`, because it ships whatever is in
# build/web — deploying without rebuilding would publish a stale bundle, quite
# possibly one pointed at a local backend.
#
# First-time setup (account, D1, secret) is in worker/README.md; this recipe
# assumes it is done.
[doc('Deploy the worker and the PWA to Cloudflare')]
worker-deploy: web
    npx wrangler deploy --config worker/wrangler.toml

[doc('Debug APK for a phone (arm64)')]
phone-apk:
    flutter build apk --debug --target-platform android-arm64 {{client_defines}}

# Fat 32+64: Wear devices are often armeabi-v7a, and an arm64-only APK will not
# install on them.
[doc('Debug APK for a watch (fat 32+64)')]
watch-apk:
    flutter build apk --debug --target-platform android-arm,android-arm64 {{client_defines}}

# `adb install -r` rather than `flutter install`. The latter uninstalls the old
# version first, and uninstalling deletes app data — which here is the database
# holding every tracked block. `-r` upgrades in place and keeps it.
#
# The model is echoed first: a silent install into the wrong device also prints
# "Success", and a wireless serial changes port on every reconnect, so the id you
# pass may not be the device you meant.
#   just deploy 192.168.1.158:36915
_install device apk:
    @echo "→ installing to {{device}} ($(adb -s {{device}} shell getprop ro.product.model | tr -d '\r'))"
    adb -s {{device}} install -r {{apk}}

[doc('Build and install on a phone')]
deploy device: phone-apk
    @just _install {{device}} build/app/outputs/flutter-apk/app-debug.apk

[doc('Build and install on a watch')]
deploy-watch device: watch-apk
    @just _install {{device}} build/app/outputs/flutter-apk/app-debug.apk

# One device's view of sync, read straight from the app's own database.
#
# `backend` is the whole pairing question in one string: it is the server URL
# *and* the account, so two devices that print the same value are genuinely
# talking to the same place as the same account, and two that differ cannot
# converge no matter how often either syncs. `cursor` frozen while the server
# has moved on is the signature of a pull that keeps failing — which is silent,
# because a background sync's failures are deliberately inert.
#
# Needs a debug build: `run-as` is how a device without root lets anything read
# app-private storage, and it refuses on a non-debuggable package.
[doc("One device's sync state: backend, cursor and row counts")]
sync-state device:
    @just _sync_state {{device}} ''

_sync_state device indent='':
    #!/usr/bin/env bash
    set -uo pipefail
    if ! command -v sqlite3 >/dev/null 2>&1; then
        printf '{{indent}}sqlite3 is not installed\n'; exit 0
    fi
    db=$(mktemp)
    trap 'rm -f "$db"' EXIT
    adb -s {{device}} exec-out run-as {{package_id}} cat app_flutter/time_tracker.sqlite > "$db" 2>/dev/null
    # Checked by magic, not by size: `run-as` reports its own failures on stdout
    # through exec-out, so a refusal arrives as a perfectly non-empty file.
    if [ "$(head -c 15 "$db" 2>/dev/null)" != "SQLite format 3" ]; then
        printf '{{indent}}no database — app not installed, never opened, or not a debug build\n'; exit 0
    fi
    q() { sqlite3 "$db" "$1" 2>/dev/null; }
    # Spelled out rather than left blank: an empty field reads as "the tool
    # failed", which is the ambiguity this recipe exists to remove.
    printf '{{indent}}backend    %s\n' "$(q "select value from sync_meta where key = 'backend'" | grep . || echo 'none — no sync account on this device')"
    printf '{{indent}}cursor     %s\n' "$(q "select value from sync_meta where key = 'cursor'" | grep . || echo 'none — never pulled')"
    printf '{{indent}}activities %s\n' "$(q 'select count(*) from activities')"
    printf '{{indent}}changes    %s\n' "$(q 'select count(*) from activity_changes')"

[doc('flutter clean')]
clean:
    flutter clean

