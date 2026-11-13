# Build / test / run commands for time_tracker.
#
# `just` lists them; `just <recipe>` runs one. Each [doc('…')] one-liner is
# written to be sufficient on its own: what the recipe does, what it rebuilds or
# needs first, and the one thing that would otherwise surprise you. The listing
# is the reference — you should not have to open this file to run something, and
# nothing duplicates it elsewhere, so it cannot go stale.
#
# The comments above a recipe are the *why*, for whoever changes it. If using a
# recipe ever requires reading one of them, that belongs in its [doc] instead.
#
# Two standing constraints:
#  * drift codegen needs --force-jit (plain build_runner hits a "dart compile
#    does not support build hooks" error). Run `just gen` after changing the
#    schema in lib/data/database.dart.
#  * APKs are release builds unless the recipe ends in -debug. Release needs
#    gen_snapshot for the host, which Flutter ships only for linux-x64; an
#    aarch64 host runs that one through qemu, copied into the engine's
#    linux-arm64 folder. Both build types sign with the same debug key and
#    stay debuggable, so either installs over the other and run-as still works.

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

[doc('List these recipes — the full command reference, no need to open the Justfile')]
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
[doc('What is running where: repo, deployed bundle, and every attached device. Read-only')]
status:
    #!/usr/bin/env bash
    set -uo pipefail
    echo "REPO"
    printf '  head    %s\n' "$(git log -1 --format='%h %s')"
    # The whole tree, because that is what `git describe --dirty` in build_id
    # judges — reporting a narrower "clean" beside a `-dirty` stamp is the kind
    # of contradiction this recipe exists to remove. Named, not just counted:
    # the answer to "why is my build dirty" is the file list.
    dirty=$(git status --porcelain | awk '{ print $NF }' | tr '\n' ' ')
    if [ -n "$dirty" ]; then
        printf '  tree    dirty: %s\n' "$dirty"
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
        # Cache-busted, and not politely: a plain GET here is answered by the
        # edge cache, so this reported the *previous* deploy's stamp for minutes
        # after a successful upload — the exact lie the recipe exists to catch.
        stamp=$(curl -fsS --max-time 20 -H 'Cache-Control: no-cache' \
            "${url%/}/main.dart.js?cachebust=$(date +%s)" 2>/dev/null \
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

[doc('Static analysis (flutter analyze) over the whole package')]
analyze:
    flutter analyze

# The exclusion is the whole reason this is a recipe rather than `dart format .`.
# Drift writes lib/data/database.g.dart at the formatter's default 80 columns, so
# formatting it to ours would be undone by the next `just gen` and churn back on
# every regeneration. That file's formatting belongs to the generator.
#
# The width itself is in analysis_options.yaml, so plain `dart format` picks it
# up and nothing here passes it.
[doc('Format every hand-written Dart file — skips generated code, whose formatting drift owns')]
fmt:
    find lib test integration_test tool -name '*.dart' ! -name '*.g.dart' -print0 \
        | xargs -0 dart format

# Needed after changing pubspec.yaml: the test and build recipes pass --no-pub so
# an ordinary run does not stop to re-resolve.
[doc('Resolve Dart dependencies — needed after a pubspec change; every other recipe passes --no-pub')]
deps:
    flutter pub get

# --no-pub skips the implicit pub get — see `just deps`.
# TZ: a zone with DST, or the tests pinning a DST change run in UTC and skip.
[doc('Unit + widget tests — the whole suite under test/, in Europe/Bratislava so DST cases run')]
test:
    TZ=Europe/Bratislava flutter test --no-pub

# Takes any `flutter test` arguments — one or more files, or a name filter:
#   just test-only test/calendar_test.dart
#   just test-only --plain-name moveBoundary
#   just test-only test/calendar_test.dart test/domain_test.dart
[doc('A subset of the suite, for a tight edit/run loop — takes any flutter test args: files, --plain-name, --update-goldens; same TZ as test')]
test-only +args:
    TZ=Europe/Bratislava flutter test --no-pub {{args}}

[doc('The suite, printing only failures; same TZ as test')]
test-failures +args="test":
    TZ=Europe/Bratislava flutter test --no-pub --reporter=failures-only {{args}}

# The Kotlin under android/ is the Wear transport, the queue and cache it keeps
# on disk, and the widget and complication surfaces — none of it reachable from
# `flutter test`, which is why Gradle is driven directly here.
#
# Both cache redirects are mandatory, not tuning. The Flutter Gradle plugin is
# pulled in as a composite build straight from the SDK, and when that SDK sits on
# a read-only path Gradle and the Kotlin compiler both try to write their scratch
# state beside it. The Kotlin one at least reports a missing .kotlin/sessions
# file; Gradle's own project cache fails *silently* — no output at all, a
# non-zero exit, and a daemon that logs the build as successful. Absolute paths:
# a relative one resolves against the included build, not this directory. Parked
# in .gradle-test-cache/ rather than build/ so `clean` (flutter clean, which
# wipes build/) does not cost the next run a cold reconfigure and recompile.
[doc('JVM unit tests for the Kotlin sources under android/ — Robolectric, so no device or emulator; takes gradle test args, so a subset is --tests "*WearBridgeTest*". First run fetches Gradle and the Robolectric android-all jar; its private Gradle cache means no lock against deploy/e2e/up — do not run them at the same time')]
android-test *args:
    cd android && ./gradlew \
      --project-cache-dir="{{justfile_directory()}}/.gradle-test-cache/project" \
      -Pkotlin.project.persistent.dir="{{justfile_directory()}}/.gradle-test-cache/kotlin" \
      :app:testDebugUnitTest {{args}}

# Needs a running emulator or a connected device. `flutter devices` lists the
# ids; a phone paired over wifi gets a new ip:port each pairing, so pass it
# explicitly when it changes.
[doc('On-device run of the phone flow — needs an emulator or device; `flutter devices` lists the ids')]
e2e device="127.0.0.1:5557":
    flutter test integration_test/flow_test.dart --no-pub -d {{device}}

# A *different suite*, not the phone one on a smaller screen: the watch has its
# own shell because the phone layout does not fit a 227x227 round display.
[doc('On-device run of the watch shell — a different suite from `e2e`, not the same one on a smaller screen')]
e2e-watch device="127.0.0.1:5555":
    flutter test integration_test/watch_flow_test.dart --no-pub -d {{device}}

[doc('Regenerate drift code — run after editing the schema in lib/data/database.dart')]
gen:
    flutter pub run build_runner build --force-jit

[doc('Regenerate drift code on every change (watching `gen`)')]
watch:
    flutter pub run build_runner watch --force-jit

# The _headers copy is not incidental: `flutter build web` copies everything in
# web/ *except* files starting with an underscore, so the response headers the
# deployed app needs — cross-origin isolation, no-store on the shell — would
# silently not ship.
[doc('Build the web PWA into build/web — also copies web/_headers, which the build itself skips')]
web:
    flutter build web {{client_defines}}
    cp web/_headers build/web/_headers

# The *built* bundle rather than a dev server, because that is the real artefact
# — service worker, offline reload, installability, hashed assets — and a dev
# build has none of it. No hot reload as a result; re-run to pick up changes.
#
# Binds 0.0.0.0 so a browser on another machine can reach it.
[doc('Build and serve the PWA on :4242 — the way to review it. Rebuilds `web`; no hot reload, re-run to pick up changes')]
up port="4242": web
    dart tool/serve_web.dart build/web {{port}}

# Only playwright-core comes from npm; the browser binaries are expected on the
# machine already, found via PLAYWRIGHT_BROWSERS_PATH. package.json pins
# playwright to a version matching those binaries.
[doc('Install the browser tooling web-smoke needs (playwright-core); browser binaries must already be on the machine')]
node-deps:
    npm install --no-audit --no-fund

# Checks cross-origin isolation, OPFS, persistence, data surviving a reload, and
# a reload with the network cut. Runs headed under Xvfb — headless swiftshader
# paints blank CanvasKit frames.
[doc('Build, serve, and smoke-test the PWA in a real browser — rebuilds `web`; needs `node-deps` and Xvfb')]
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
#
# Depends on `web` because wrangler.toml serves build/web as the Worker's
# assets, and wrangler refuses to start when that directory is missing.
[doc('Smoke-test the sync worker locally on :4245 — rebuilds `web` (wrangler will not start without build/web) and stops wrangler when done; do not run alongside `worker-dev`')]
worker-smoke port="4245": web
    node tool/worker_smoke.mjs {{port}}

# Apply the schema to a local D1. Safe to re-run — the schema is all
# CREATE TABLE IF NOT EXISTS — and needed once before `worker-dev` will answer.
[doc('Create or update the local sync database — run once before `worker-dev`; safe to re-run')]
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
[doc('Run the sync worker locally against a persistent D1 on :4243 — needs `worker-db` first; starts with no accounts')]
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
[doc('Deploy the worker and the PWA to Cloudflare — rebuilds `web` first, so it ships this working tree, SYNC_URL and all')]
worker-deploy: web
    npx wrangler deploy --config worker/wrangler.toml

[doc("Release APK for a phone (arm64) into build/app/outputs/flutter-apk/app-release.apk — on an aarch64 host, needs Flutter's linux-x64 gen_snapshot copied into the release engines' linux-arm64 folders")]
phone-apk:
    flutter build apk --release --target-platform android-arm64 {{client_defines}}

# Each upload needs a higher versionCode than the last, and phone and watch
# bundles share that space. `tool/play-upload.sh --next-code` on the host gives
# the number: the phone takes it, the watch takes it plus 1.
[doc("Play app bundle for a phone (arm64) into build/app/outputs/bundle/release/app-release.aab, not debuggable and signed with the upload key whose properties are in the android-user volume — build is the versionCode from tool/play-upload.sh --next-code; upload it from the host with tool/play-upload.sh; on an aarch64 host, needs the gen_snapshot copy phone-apk needs")]
phone-aab build:
    cp /root/.android/upload.properties android/key.properties
    PLAY_UPLOAD=1 flutter build appbundle --release --build-number {{build}} --target-platform android-arm64 {{client_defines}}

[doc('Debug APK for a phone (arm64) into build/app/outputs/flutter-apk/app-debug.apk — JIT, slower on the device, but builds on any host')]
phone-apk-debug:
    flutter build apk --debug --target-platform android-arm64 {{client_defines}}

# Fat 32+64: Wear devices are often armeabi-v7a, and an arm64-only APK will not
# install on them.
[doc('Release APK for a watch (fat 32+64) into build/app/outputs/flutter-apk/app-release.apk — Wear devices are often armeabi-v7a; bakes in SYNC_URL like the phone, so the watch can reach the backend on its own once the phone hands it a token; on an aarch64 host, needs the gen_snapshot copy phone-apk needs')]
watch-apk:
    flutter build apk --release --target-platform android-arm,android-arm64 {{client_defines}}

[doc("Play app bundle for a watch (fat 32+64) into build/app/outputs/bundle/release/app-release.aab, declaring itself a standalone Wear OS app and signed like phone-aab — build is the phone versionCode plus 1; upload it to a wear: track, such as wear:internal, from the host with tool/play-upload.sh; on an aarch64 host, needs the gen_snapshot copy phone-apk needs")]
watch-aab build:
    cp /root/.android/upload.properties android/key.properties
    PLAY_UPLOAD=1 PLAY_FORM_FACTOR=watch flutter build appbundle --release --build-number {{build}} --target-platform android-arm,android-arm64 {{client_defines}}

[doc('Debug APK for a watch (fat 32+64) into build/app/outputs/flutter-apk/app-debug.apk — JIT, slower on the device, but builds on any host; bakes in SYNC_URL like watch-apk')]
watch-apk-debug:
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

[doc('Build release and install on a phone — positional serial (`just deploy <serial>`); upgrades in place over a release or debug install, keeping the database')]
deploy device: phone-apk
    @just _install {{device}} build/app/outputs/flutter-apk/app-release.apk

[doc('Build debug and install on a phone — positional serial; upgrades in place over a release or debug install, keeping the database')]
deploy-debug device: phone-apk-debug
    @just _install {{device}} build/app/outputs/flutter-apk/app-debug.apk

[doc('Build release and install on a watch — positional serial; upgrades in place over a release or debug install, keeping the database')]
deploy-watch device: watch-apk
    @just _install {{device}} build/app/outputs/flutter-apk/app-release.apk

[doc('Build debug and install on a watch — positional serial; upgrades in place over a release or debug install, keeping the database')]
deploy-watch-debug device: watch-apk-debug
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
# Needs a debuggable build, which release and debug both are: `run-as` is how a
# device without root lets anything read app-private storage, and it refuses on
# a non-debuggable package.
[doc("One device's sync state: backend, cursor and row counts — positional serial; needs a debuggable build (release and debug both are) and sqlite3")]
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
        printf '{{indent}}no database — app not installed, never opened, or not debuggable\n'; exit 0
    fi
    q() { sqlite3 "$db" "$1" 2>/dev/null; }
    # Spelled out rather than left blank: an empty field reads as "the tool
    # failed", which is the ambiguity this recipe exists to remove.
    printf '{{indent}}backend    %s\n' "$(q "select value from sync_meta where key = 'backend'" | grep . || echo 'none — no sync account on this device')"
    printf '{{indent}}cursor     %s\n' "$(q "select value from sync_meta where key = 'cursor'" | grep . || echo 'none — never pulled')"
    printf '{{indent}}activities %s\n' "$(q 'select count(*) from activities')"
    printf '{{indent}}changes    %s\n' "$(q 'select count(*) from activity_changes')"

[doc('flutter clean — wipe build/ and .dart_tool')]
clean:
    flutter clean
