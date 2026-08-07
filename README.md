# track

Offline-first time-activity tracker — phone, Wear OS, and a web PWA, sharing one
Flutter codebase and one local Drift database.

Time is stored as a **change-point event log**: each row in `activity_change` is
a boundary, and the blocks you see on the timeline are *derived* from consecutive
boundaries. Editing a block is therefore editing a boundary — which is why one
drag in the calendar retimes two blocks at once.

## Commands

```
just            # every recipe, with a one-line description
just <recipe>   # run one
```

The `Justfile` is the reference — each recipe carries its own description and,
where the reasoning is not obvious, the why. Nothing is duplicated here, so
there is nothing to fall out of date.

Start with `just test`, `just up` (build and serve the PWA), and `just deploy
device=<id>`.

One thing the listing cannot convey: `e2e` and `e2e-watch` are *different
suites*, not the same one on two screens. The watch has its own shell because the
phone layout does not fit a 227x227 round display.

## The web PWA

The web build is a real offline-first client, not a thin shell — it keeps its own
SQLite database in the browser via drift's wasm build, stored in **OPFS**.

Two host requirements come with that:

**Cross-origin isolation (optional).** `Cross-Origin-Opener-Policy: same-origin`
plus `Cross-Origin-Embedder-Policy: require-corp` enable `SharedArrayBuffer`,
which drift's fastest OPFS implementation uses. **The app does not need them** —
without isolation drift picks an implementation that does not want
`SharedArrayBuffer`, and everything works. Plain `flutter run -d web-server` is
fine for development.

`just up` builds and serves the real bundle rather than running a dev server,
because the dev build has no service worker — so offline behaviour and
installability, the two things most worth reviewing, are absent from it. The cost
is no hot reload: re-run `just up` to pick up changes.

**Storage persistence.** Browsers may evict an origin's storage under disk
pressure, which for this app means losing recorded time. The app calls
`navigator.storage.persist()` at startup and reports the answer on the Reports
screen (`LOCAL DB · opfs · persistent · isolated`). Browsers only *grant* it to
installed or sufficiently engaged origins, so a plain tab may legitimately read
`evictable`; installing the PWA is the reliable way to get `persistent`.

`just web-smoke` checks all of this in a real browser: the headers, the wasm MIME
type, cross-origin isolation, that drift's database really lands in OPFS, that it
survives a reload, and that the app still loads with the network cut.

### Hosting

**Serve it over HTTPS.** Service workers, OPFS and `storage.persist()` are all
gated on a secure context, so over plain HTTP the app loses its database, its
offline capability and its installability at once. The only exception is a
loopback origin — `127.0.0.1` or a `*.localhost` name — which browsers already
treat as trustworthy. That exception is why `just up` can serve plain HTTP and
why `just web-smoke` passes against `127.0.0.1`; it does not extend to a real
hostname, even on a private network.

Beyond that, any static host works, provided it sends the two isolation headers
and serves `.wasm` as `application/wasm`. For nginx:

```nginx
location / {
    root /srv/track;
    try_files $uri $uri/ /index.html;

    add_header Cross-Origin-Opener-Policy   same-origin   always;
    add_header Cross-Origin-Embedder-Policy require-corp  always;
    add_header Cross-Origin-Resource-Policy same-origin   always;
}

# The shell and the service worker must never be served stale, or a deploy stays
# invisible until caches expire.
location = /index.html                 { add_header Cache-Control "no-store" always; }
location = /flutter_service_worker.js  { add_header Cache-Control "no-store" always; }
```

`types { application/wasm wasm; }` is already in nginx's default mime.types on
recent versions — verify, because a wrong type breaks the streaming wasm compile.

## Layout

```
lib/
  data/        Drift schema, repositories, TrackerController, storage probe
  domain/      Pure logic: block derivation, reporting, calendar geometry, CSV
  phone/       The phone/web shell: screens + neobrutalist widget kit
  watch/       Wear OS shell (later phase)
  theme/       NeoTokens design tokens
test/          Unit + widget tests; support/ holds the shared flow harness
integration_test/  On-device end-to-end
tool/          serve_web.dart, web_smoke.mjs
```

Design decisions and their reasoning live in the commit messages; the code
comments carry the ones that need to be read alongside the code.
