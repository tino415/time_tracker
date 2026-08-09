// Smoke-tests the built PWA in a real browser: cross-origin isolation, OPFS,
// storage persistence, data surviving a reload, and a reload with the network
// cut. Run via `just web-smoke`.
//
// Why a browser script rather than an integration_test: this checks *host*
// guarantees (headers, storage buckets, service-worker caching), none of which
// exist inside the Flutter test harness. Everything asserted here is read from
// the page's own JS context, which is exact.
//
// The UI is reachable too. Flutter web paints into a canvas, but main() calls
// ensureSemantics() on web, so the engine emits a real DOM accessibility tree —
// <flt-semantics> elements carrying the labels — which can be selected and
// clicked like any other page. No coordinate guessing.
//
// Chromium must run headed (under Xvfb): headless swiftshader paints blank
// CanvasKit frames.

import { spawn } from 'node:child_process';
import { chromium } from 'playwright-core';

const PORT = process.argv[2] ?? '4242';
const ORIGIN = `http://127.0.0.1:${PORT}`;
const BOOT_MS = 20000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const checks = [];
function check(name, ok, detail = '') {
  checks.push({ name, ok, detail });
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name}${detail ? `  — ${detail}` : ''}`);
}

/// Reported but not gated — things the browser decides, which we cannot assert.
function info(name, detail) {
  console.log(`info  ${name}  — ${detail}`);
}

/// Names in the origin's OPFS root.
const opfsEntries = (page) =>
  page.evaluate(async () => {
    const names = [];
    try {
      const root = await navigator.storage.getDirectory();
      for await (const n of root.keys()) names.push(n);
    } catch {}
    return names;
  });

/// Drift creates its OPFS files lazily, so a single sample races the app's
/// startup — poll instead of guessing how long it takes.
async function waitForOpfs(page, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  let names = [];
  while (Date.now() < deadline) {
    names = await opfsEntries(page);
    if (names.length > 0) return names;
    await sleep(250);
  }
  return names;
}

/** Wait until the Flutter app has actually booted, not just until load fires. */
async function waitForApp(page) {
  const deadline = Date.now() + BOOT_MS;
  while (Date.now() < deadline) {
    const ready = await page.evaluate(() => !!document.querySelector('flt-glass-pane, flutter-view, canvas'));
    if (ready) return true;
    await sleep(500);
  }
  return false;
}

const server = spawn('dart', ['tool/serve_web.dart', 'build/web', PORT], {
  stdio: ['ignore', 'pipe', 'inherit'],
});
server.stdout.on('data', (d) => process.stdout.write(`[server] ${d}`));

let browser;
try {
  // Give the server a moment to bind.
  for (let i = 0; i < 20; i++) {
    try {
      const res = await fetch(`${ORIGIN}/index.html`);
      if (res.ok) break;
    } catch {}
    await sleep(250);
  }

  // --- headers, straight off the wire --------------------------------------
  const head = await fetch(`${ORIGIN}/index.html`);
  check(
    'COOP header',
    head.headers.get('cross-origin-opener-policy') === 'same-origin',
    head.headers.get('cross-origin-opener-policy') ?? 'missing',
  );
  check(
    'COEP header',
    head.headers.get('cross-origin-embedder-policy') === 'require-corp',
    head.headers.get('cross-origin-embedder-policy') ?? 'missing',
  );
  const wasm = await fetch(`${ORIGIN}/sqlite3.wasm`);
  check(
    'sqlite3.wasm served as application/wasm',
    wasm.headers.get('content-type') === 'application/wasm',
    wasm.headers.get('content-type') ?? 'missing',
  );

  browser = await chromium.launch({ headless: false });
  const context = await browser.newContext({ viewport: { width: 420, height: 900 } });
  const page = await context.newPage();

  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message.split('\n')[0]));
  page.on('console', (m) => {
    if (m.type() === 'error') errors.push(m.text().slice(0, 200));
  });

  await page.goto(ORIGIN, { waitUntil: 'load', timeout: 60000 });
  check('app boots', await waitForApp(page));

  // --- what the page got ----------------------------------------------------
  const env = await page.evaluate(async () => {
    const out = {
      isolated: crossOriginIsolated,
      sharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
      persistApi: typeof navigator.storage?.persist === 'function',
      persistCallable: false,
      persisted: false,
      serviceWorker: false,
    };
    try {
      // The app already called persist() at startup; this reads back the
      // outcome without asking a second time.
      out.persisted = await navigator.storage.persisted();
      out.persistCallable = typeof out.persisted === 'boolean';
    } catch (e) {
      out.persistError = String(e);
    }
    try {
      const regs = await navigator.serviceWorker.getRegistrations();
      out.serviceWorker = regs.length > 0;
    } catch {}
    return out;
  });

  check('cross-origin isolated', env.isolated);
  check('SharedArrayBuffer available', env.sharedArrayBuffer);
  check(
    'storage persistence API reachable',
    env.persistApi && env.persistCallable,
    env.persistError ?? '',
  );
  // Whether the grant is given is the browser's call, driven by installation or
  // engagement. A fresh automation profile has neither, so a denial here says
  // nothing about the app and must not gate the run. What matters is that the
  // request is made and the answer surfaced, which the UI's "local db" line
  // does — and that the grant has been confirmed by hand on an installed PWA.
  info('persistence granted', env.persisted ? 'yes' : 'no (uninstalled profile; granted on install)');

  const entries = await waitForOpfs(page);
  check('drift database in OPFS', entries.length > 0, entries.join(', ') || 'no OPFS entries');
  check('service worker registered', env.serviceWorker);

  // --- data survives a reload ----------------------------------------------
  // Checked at the storage layer rather than through the UI: the canvas gives
  // no reliable way to drive the app, and what is under test here is that the
  // bucket outlives the page.
  await page.reload({ waitUntil: 'load' });
  await waitForApp(page);
  const after = await waitForOpfs(page);
  check(
    'OPFS survives a reload',
    after.length >= entries.length && after.length > 0,
    after.join(', '),
  );

  // --- offline -------------------------------------------------------------
  await context.setOffline(true);
  let offlineOk = false;
  try {
    await page.reload({ waitUntil: 'load', timeout: 30000 });
    offlineOk = await waitForApp(page);
  } catch (e) {
    offlineOk = false;
  }
  check('reloads with the network cut', offlineOk);
  await context.setOffline(false);

  // --- semantics: is the web build actually drivable? -----------------------
  // main() calls ensureSemantics() on web, so the engine should emit a DOM
  // accessibility tree. If these pass, a browser test can select real elements
  // by label instead of clicking canvas coordinates.
  const semantics = await page.evaluate(() => {
    const nodes = [...document.querySelectorAll('flt-semantics')];
    return {
      count: nodes.length,
      labels: nodes
        .map((n) => n.getAttribute('aria-label') || n.textContent?.trim())
        .filter(Boolean)
        .slice(0, 40),
    };
  });
  check('semantics tree present', semantics.count > 0, `${semantics.count} nodes`);
  check(
    'tab labels reachable by selector',
    ['NOW', 'TIMELINE', 'REPORTS', 'ACTIVITIES'].every((l) =>
      semantics.labels.some((s) => s.toUpperCase().includes(l)),
    ),
    semantics.labels.filter((s) => s.length < 30).slice(0, 8).join(' | '),
  );

  // Reading labels is not the same as being able to act on them: the semantics
  // nodes have to forward the click into the canvas. Driving one real
  // interaction is what makes the web build testable.
  const label = (text) => page.locator(`flt-semantics:text-is("${text}")`).first();
  let drivable = false;
  try {
    await label('+ NEW ACTIVITY').click({ timeout: 10000 });
    await sleep(1500);
    // The editor sheet is open once its own controls exist.
    drivable = await page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')].some((n) =>
        /CREATE & SWITCH/i.test(n.textContent ?? ''),
      ),
    );
  } catch (e) {
    drivable = false;
  }
  check('a semantics node drives the app', drivable, drivable ? 'editor opened' : 'click had no effect');

  // --- the Now hero's edits, on the web engine ------------------------------
  // The widget suite cannot cover this: test/support/flow_harness.dart opens a
  // NativeDatabase, which is sqlite3 FFI and will not compile to JS. So driving
  // it here is the only place retiming the running block meets drift-wasm/OPFS
  // and a real soft keyboard rather than the host's sqlite3.
  const sinceTime = () =>
    page.evaluate(() => {
      for (const n of document.querySelectorAll('flt-semantics')) {
        const m = (n.textContent ?? '').match(/since (\d{2}:\d{2})/);
        if (m) return m[1];
      }
      return null;
    });

  let retimed = false;
  let retimeDetail = 'not reached';
  if (drivable) {
    try {
      await page.locator('input, textarea').first().fill('Deep work');
      await sleep(400);
      await label('CREATE & SWITCH').click({ timeout: 10000 });
      await sleep(2500);

      const before = await sinceTime();
      if (!before) throw new Error('no "since HH:MM" node on the hero');

      // The row is a Row of two Texts under one GestureDetector, so the exact
      // node may be either the label itself or a merged parent.
      const sinceNode = page
        .locator('flt-semantics')
        .filter({ hasText: new RegExp(`since ${before}`) })
        .last();
      await sinceNode.click({ timeout: 10000 });
      await sleep(1500);

      await label('-15').click({ timeout: 10000 });
      await sleep(500);
      await label('SAVE').click({ timeout: 10000 });
      await sleep(2500);

      const after = await sinceTime();
      const mins = (s) => {
        const [h, m] = s.split(':').map(Number);
        return h * 60 + m;
      };
      retimed = !!after && (mins(before) - mins(after) + 1440) % 1440 === 15;
      retimeDetail = `${before} -> ${after}`;
    } catch (e) {
      retimeDetail = (e.message ?? String(e)).split('\n')[0];
    }
  }
  check('Now hero retimes the running block', retimed, retimeDetail);

  const fatal = errors.filter((e) => !/favicon/i.test(e));
  check('no page errors', fatal.length === 0, fatal.slice(0, 3).join(' | '));
} finally {
  if (browser) await browser.close();
  server.kill('SIGTERM');
}

const failed = checks.filter((c) => !c.ok);
console.log(`\n${checks.length - failed.length}/${checks.length} checks passed`);
process.exit(failed.length === 0 ? 0 : 1);
