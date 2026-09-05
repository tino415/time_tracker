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
  // Set while the *script* has the network cut on purpose. Failed loads are the
  // expected result there, not a defect — and whether any escape the service
  // worker's cache is timing, so counting them makes `no page errors` flaky in
  // proportion to how long the rest of the run takes.
  let networkCut = false;
  page.on('pageerror', (e) => errors.push(e.message.split('\n')[0]));
  page.on('console', (m) => {
    if (m.type() !== 'error') return;
    const text = m.text().slice(0, 200);
    if (networkCut && /ERR_INTERNET_DISCONNECTED|Failed to load resource/i.test(text)) return;
    errors.push(text);
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
  networkCut = true;
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
  // Console errors from the cut arrive slightly after the socket is back.
  await sleep(500);
  networkCut = false;

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

  // --- the keyboard survives a tap on a non-text control --------------------
  // Web-only, and invisible to the widget suite: typing goes through a hidden
  // DOM input, so a tap that blurs it in the *browser* while Flutter still
  // thinks the field is focused leaves the form looking fine and silently
  // eating every keystroke. Reproduced by clicking a colour swatch first and
  // typing second — which is why this types on the real keyboard rather than
  // using locator.fill(), which writes to the DOM element directly and would
  // pass even with the bug present.
  let keyboardSurvives = false;
  let keyboardDetail = 'not reached';
  let step = 'open Activities';
  try {
    // Via the Activities tab: by now a block is running, so the Now screen's
    // first-run "+ NEW ACTIVITY" is gone.
    await label('ACTIVITIES').click({ timeout: 10000 });
    await sleep(1200);

    step = 'open the editor';
    await label('+ NEW ACTIVITY').click({ timeout: 10000 });
    await sleep(1500);

    // Discovered rather than hardcoded, so changing the palette does not break
    // this. The anchored regex is what isolates a swatch's own node: an ancestor
    // node's text is every descendant's concatenated, so only the leaf matches.
    step = 'find the colour swatches';
    const swatchLabels = await page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')]
        .map((n) => n.getAttribute('aria-label') || n.textContent?.trim() || '')
        .filter((s) => /^colour #[0-9a-f]{6}$/i.test(s)),
    );
    if (swatchLabels.length < 2) {
      throw new Error(`expected labelled swatches, found ${swatchLabels.length}`);
    }

    // Not the first: that is the default, and tapping it would change nothing.
    step = `click swatch ${swatchLabels[1]}`;
    await label(swatchLabels[1]).click({ timeout: 10000 });
    await sleep(600);

    step = 'type into the name field';

    await page.keyboard.type('Typed after the swatch');
    await sleep(600);

    const typed = await page.evaluate(
      () => [...document.querySelectorAll('input, textarea')].map((e) => e.value).join('|'),
    );
    keyboardSurvives = typed.includes('Typed after the swatch');
    keyboardDetail = keyboardSurvives ? 'keystrokes landed' : `field held "${typed}"`;
  } catch (e) {
    keyboardDetail = `at "${step}": ${(e.message ?? String(e)).split('\n')[0]}`;
  }
  check('typing still works after tapping a colour swatch', keyboardSurvives, keyboardDetail);

  // --- keyboard shortcuts, on a real keyboard -------------------------------
  // The widget suite drives these through simulated key events, which prove the
  // bindings and the layout-independent matching. What only a browser can show
  // is that the events survive the round trip through the DOM and the Flutter
  // web engine's own key handling at all.
  //
  // Escape leads, because the swatch step above left the editor sheet open and
  // the bindings are deliberately deaf while a modal route holds focus. That
  // makes it both the setup for the rest and the check itself: Escape is
  // Flutter's own, and this is the evidence for not binding a second handler.
  const sheetOpen = () =>
    page.evaluate(() =>
      [...document.querySelectorAll('flt-semantics')].some((n) =>
        /CREATE & SWITCH/i.test(n.textContent ?? ''),
      ),
    );
  const seesText = (re) =>
    page.evaluate(
      (source) =>
        [...document.querySelectorAll('flt-semantics')].some((n) =>
          new RegExp(source, 'i').test(n.textContent ?? ''),
        ),
      re.source,
    );
  /** A key by *position* — Playwright sends a `code`, the same path a non-US
   * layout takes, which is the whole reason the bindings are physical. */
  const key = async (code, { shift = false } = {}) => {
    await page.keyboard.press(shift ? `Shift+${code}` : code);
    await sleep(1000);
  };

  let escClosed = false;
  let shortcutsWork = false;
  let helpListed = false;
  let keysDetail = 'not reached';
  try {
    await page.keyboard.press('Escape');
    await sleep(1200);
    escClosed = !(await sheetOpen());

    // `g` then `r`. Bare keys are the point: the modifier scheme this replaced
    // was eaten by the browser, and only a browser can show that these are not.
    await key('KeyG');
    await key('KeyR');
    shortcutsWork = await seesText(/PER CATEGORY/);

    await key('Slash', { shift: true });
    helpListed = (await seesText(/Keyboard/)) && (await seesText(/Previous period/));
    keysDetail = `esc=${escClosed} reports=${shortcutsWork} help=${helpListed}`;
  } catch (e) {
    keysDetail = (e.message ?? String(e)).split('\n')[0];
  }
  check('Escape closes an open sheet', escClosed, keysDetail);
  check('g r reaches the Reports tab', shortcutsWork, keysDetail);
  check('? lists the bindings', helpListed, keysDetail);

  // --- the cheatsheet has a control you can see ------------------------------
  // Only checkable here: the button is gated on kIsWeb, which is false in the
  // widget suite. And it exists because the keystroke is not enough — Safari
  // takes Cmd+/ for its status bar, so there the list had no keyboard route at
  // all, and a shortcut for discovering shortcuts is a poor sole route anyway.
  //
  // Two clicks now: at this width the app controls live behind the tab bar's
  // ••• cell, so this covers the sheet opening as well as what is in it.
  let keysButton = false;
  let buttonDetail = 'not reached';
  try {
    await page.keyboard.press('Escape'); // close the dialog the chord opened
    await sleep(1000);
    await label('•••').click({ timeout: 10000 });
    await sleep(1200);
    await label('⌨ KEYS').click({ timeout: 10000 });
    await sleep(1500);
    keysButton = (await seesText(/Keyboard/)) && (await seesText(/Previous period/));
    buttonDetail = keysButton ? 'opened the list' : 'click had no effect';
  } catch (e) {
    buttonDetail = (e.message ?? String(e)).split('\n')[0];
  }
  check('the controls sheet opens the cheatsheet', keysButton, buttonDetail);

  // Two routes deep now — the cheatsheet, and the sheet it was opened from —
  // and everything after this clicks the app itself. Unconditional, because a
  // check that failed halfway leaves one of them up just as surely.
  for (let i = 0; i < 2; i++) {
    await page.keyboard.press('Escape');
    await sleep(800);
  }

  // --- Tab reaches the controls ---------------------------------------------
  // The widget suite can prove Flutter's own focus tree moves. Whether the
  // *browser* agrees is a separate question and the one that matters: the app
  // paints into a canvas, so a control is only reachable by keyboard if the
  // engine gives it a real DOM node to focus. That is what ensureSemantics()
  // buys, and this is the check that it is still buying it.
  let tabFocuses = false;
  let tabDetail = 'not reached';
  try {
    await page.keyboard.press('Escape'); // leave the cheatsheet
    await sleep(1000);
    const landed = [];
    for (let i = 0; i < 12; i++) {
      await page.keyboard.press('Tab');
      await sleep(250);
      const on = await page.evaluate(() => {
        const el = document.activeElement;
        if (!el || el === document.body) return null;
        return (el.getAttribute('aria-label') ?? el.textContent ?? '').trim().slice(0, 40);
      });
      if (on) landed.push(on);
    }
    tabFocuses = landed.length > 0;
    tabDetail = landed.slice(0, 3).join(' | ') || 'focus never left the document body';
  } catch (e) {
    tabDetail = (e.message ?? String(e)).split('\n')[0];
  }
  check('Tab moves focus onto the controls', tabFocuses, tabDetail);

  // --- the window gets wider --------------------------------------------------
  // Resizing the page we already have rather than opening a second context: it
  // costs no extra boot, and it tests the better thing. A desktop window is
  // resized while the app is running, and re-laying-out on that is what no
  // widget test can convincingly cover — they each pick a size and stay there.
  //
  // This used to also assert that a wide window drew Now and the timeline side
  // by side. It does not any more, and deliberately: 716271c made every width
  // show one screen at a time, and `at the widest viewport, selecting Timeline
  // shows Timeline and not Now` in test/shell_layout_test.dart pins the
  // opposite. The check had been failing ever since, asserting a layout the app
  // had given up.
  let widened = false;
  let wideDetail = 'not reached';
  try {
    await page.setViewportSize({ width: 1280, height: 900 });
    await sleep(2000);

    // The run left us on Reports, which is a single column at any width.
    // Clicked rather than keyed: the Tab loop above left focus on whatever it
    // stopped on, and if that is a field the bare keys are deliberately deaf.
    await label('NOW').click({ timeout: 10000 });
    await sleep(1500);

    // Measured, not looked up. An IndexedStack keeps the tabs you cannot see in
    // the semantics tree, so asking whether a label is *present* answers yes at
    // any width; where it is drawn is the question. Leaves only — the ancestor
    // nodes carry the whole page's text and span the whole window.
    const geometry = await page.evaluate((sidebar) => {
      const leaves = [...document.querySelectorAll('flt-semantics')]
        .filter((n) => !n.querySelector('flt-semantics'))
        .map((n) => ({
          text: (n.getAttribute('aria-label') || n.textContent || '').replace(/\s+/g, ' '),
          box: n.getBoundingClientRect(),
        }));
      return {
        navInSidebar: ['NOW', 'TIMELINE', 'REPORTS', 'ACTIVITIES'].filter((l) =>
          leaves.some((n) => n.text.trim() === l && n.box.right <= sidebar + 4),
        ).length,
      };
    }, 180);

    widened = geometry.navInSidebar === 4;
    wideDetail = `${geometry.navInSidebar}/4 destinations in the sidebar`;
  } catch (e) {
    wideDetail = (e.message ?? String(e)).split('\n')[0];
  }
  check('the navigation survives a resize', widened, wideDetail);

  const fatal = errors.filter((e) => !/favicon/i.test(e));
  check('no page errors', fatal.length === 0, fatal.slice(0, 3).join(' | '));
} finally {
  if (browser) await browser.close();
  server.kill('SIGTERM');
}

const failed = checks.filter((c) => !c.ok);
console.log(`\n${checks.length - failed.length}/${checks.length} checks passed`);
process.exit(failed.length === 0 ? 0 : 1);
