// Loads a served web export in headless Chromium (Pixel 7 emulation) and fails on script errors, in two phases.
// Called by scripts/ci/check-web-load.sh, which serves the build; run it through that script.
// Usage: node web-load-check.js <base-url> [watch-seconds] [boot-timeout-seconds]
//   base-url              where the export is served, e.g. http://127.0.0.1:8811
//   watch-seconds         how long each phase watches the console after its boot marker (default 5)
//   boot-timeout-seconds  how long each phase waits for the boot marker before giving up (default 90)
// Needs: the `playwright` package resolvable (NODE_PATH) and a Chromium that chromium.launch() finds.
//
// Phase 1, a fresh profile: boot, then watch. A script that does not compile is logged here, whatever the save.
// Phase 2, a non-empty save: a minimal valid save (rank XP 500, so the first-launch lesson is not offered and the
//   main menu shows) is written into the browser's IndexedDB, which Godot mounts as user:// on the web (an IDBFS
//   under /userfs, the file /userfs/godot/app_userdata/rts-mobile/save.cfg, format of game/meta/save_service.gd:
//   a "; sha256=<hex of the body>" line, then the ConfigFile text). The page is loaded again, booted, watched, and
//   the SKIRMISH button of the main menu is tapped: the screen must change (screenshots before and after).
//   A menu that did not come up, or does not answer, fails the check.
//
// The boot marker is the console line "boot_ms=<n>" that IntroPlayer prints once the intro has handed over the
// menu (game/view/intro/IntroPlayer.gd). The page's `load` event comes long before the wasm and the pack are
// fetched, so each watch window starts at the marker. The intro waits for the consent call, and the web preview
// answers it with FakeConsentForm (a "Test consent form" with Accept and Decline, drawn on the canvas, nothing
// in the DOM, and shown at every start, because consent is not saved): the script taps where Accept is, once a
// second, until the marker comes. The position is a fraction of the viewport (the form is centred, Accept is
// the first button), so it holds for Pixel 7 in portrait; change TAP_ACCEPT if FakeConsentForm's layout changes.
//
// Exit: 0 both phases booted, no script error, and the menu answered the tap
//       1 a console line matched ERROR_PATTERN, or the page threw an uncaught error (at once, also before the
//         marker)
//       2 usage error
//       3 no boot marker within the boot timeout (the engine did not start: no WebGL2, a 404, a failed wasm; the
//         last console lines and the page text are printed), the save could not be written, the browser could
//         not be started, or the page could not be loaded
//       4 the main menu did not answer: the screen did not change after the tap on SKIRMISH
'use strict';

// What Godot prints to the browser console when a script does not compile or load. "SCRIPT ERROR" covers runtime
// errors too. "boot_error:" is IntroPlayer's own line for a menu scene that did not load. Plain "ERROR:" lines are
// not matched: engine errors that never touch a script (a missing optional resource) are not what this guard is for.
const ERROR_PATTERN = /SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|^boot_error:/;
const BOOT_PATTERN = /^boot_ms=\d+/;
const TAIL_LINES = 15;
// Fractions of the viewport (x, y). Accept: FakeConsentForm, measured on a 412x839 viewport. SKIRMISH: the first
// button of the main menu.
const TAP_ACCEPT = [0.5, 0.469];
const TAP_SKIRMISH = [0.5, 0.2185];
const SAVE_DIR = '/userfs/godot/app_userdata/rts-mobile';
const SAVE_BODY = '[meta]\n\nversion=1\napp_version=""\n\n[progress]\n\nxp=500\n';

class Fail extends Error {
  constructor(code, lines) {
    super(lines[0]);
    this.code = code;
    this.lines = lines;
  }
}

// Opens `url` in a new page of `context`, taps Accept until the boot marker, then watches. Returns the page (open) and
// the marker line. Throws Fail.
async function boot(context, url, label, watchSeconds, bootTimeoutSeconds) {
  const hits = [];
  const tail = [];
  let booted = false;
  let bootText = '';
  let afterHit = false; // the previous console line was a hit: an "at:" line right after it belongs to it
  let failNow = false;
  const page = await context.newPage();
  page.on('console', (msg) => {
    const text = msg.text();
    const first = text.split('\n')[0];
    tail.push(first);
    if (tail.length > TAIL_LINES) tail.shift();
    if (ERROR_PATTERN.test(first)) {
      hits.push(first);
      afterHit = true;
      failNow = true;
      return;
    }
    // Godot writes "at: ..." as the next console line; keep it, it names the file and line.
    if (afterHit && /^\s+at: /.test(text)) {
      hits.push(text);
      return;
    }
    afterHit = false;
    if (!booted && BOOT_PATTERN.test(first)) {
      booted = true;
      bootText = first;
    }
  });
  page.on('pageerror', (err) => {
    hits.push('uncaught page error: ' + err.message);
    afterHit = false;
    failNow = true;
  });
  await page.goto(url, { waitUntil: 'load', timeout: 60000 });
  const started = Date.now();
  const deadline = started + bootTimeoutSeconds * 1000;
  let lastTap = 0;
  while (!booted && !failNow && Date.now() < deadline) {
    if (Date.now() - started > 1500 && Date.now() - lastTap >= 1000) {
      const vp = page.viewportSize();
      await page.touchscreen.tap(vp.width * TAP_ACCEPT[0], vp.height * TAP_ACCEPT[1]);
      lastTap = Date.now();
    }
    await page.waitForTimeout(250);
  }
  if (!booted && !failNow) {
    let dom = '';
    try {
      dom = await page.evaluate(() => {
        const el = document.querySelector('#status-notice') || document.body;
        return (el && el.innerText ? el.innerText : '').trim().slice(0, 500);
      });
    } catch (e) {
      dom = '(page text not readable: ' + e.message + ')';
    }
    const lines = [
      label + ': no boot marker (boot_ms=) within ' + bootTimeoutSeconds + ' s: the engine did not start.',
      '  page text: ' + (dom || '(none)'),
      '  last console lines:',
    ];
    for (const line of tail) lines.push('    ' + line);
    throw new Fail(3, lines);
  }
  // After the marker, or after a hit (for the "at:" lines that follow it), keep watching.
  await page.waitForTimeout(failNow ? 500 : watchSeconds * 1000);
  if (hits.length > 0) {
    const lines = [label + ': the web build logged script errors' + (booted ? '' : ' before it booted') + ':'];
    for (const line of hits.slice(0, 40)) lines.push('  ' + line);
    throw new Fail(1, lines);
  }
  return { page, bootText };
}

// Writes the save into the IDBFS database of the page's origin. `page` must be on that origin and must not run the
// engine (it would overwrite what it holds when it syncs).
async function seedSave(page) {
  await page.evaluate(
    async ({ body, dir }) => {
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(body));
      const hex = Array.from(new Uint8Array(digest)).map((x) => x.toString(16).padStart(2, '0')).join('');
      const text = '; sha256=' + hex + '\n' + body;
      // Emscripten's IDBFS: database "/userfs" at version 21, object store FILE_DATA with out-of-line keys (the
      // paths) and a "timestamp" index, an entry being {timestamp, mode, contents}. The engine's first run made it;
      // if it did not exist yet it is created the same way.
      const db = await new Promise((resolve, reject) => {
        const rq = indexedDB.open('/userfs', 21);
        rq.onupgradeneeded = () => {
          const store = rq.result.objectStoreNames.contains('FILE_DATA')
            ? rq.transaction.objectStore('FILE_DATA')
            : rq.result.createObjectStore('FILE_DATA');
          if (!store.indexNames.contains('timestamp')) store.createIndex('timestamp', 'timestamp', { unique: false });
        };
        rq.onsuccess = () => resolve(rq.result);
        rq.onerror = () => reject(rq.error);
      });
      const now = new Date();
      await new Promise((resolve, reject) => {
        const tx = db.transaction('FILE_DATA', 'readwrite');
        const store = tx.objectStore('FILE_DATA');
        let path = '';
        for (const part of dir.split('/').filter(Boolean)) {
          path += '/' + part;
          store.put({ timestamp: now, mode: 16895 }, path); // a directory, mode 040777
        }
        store.put({ timestamp: now, mode: 33206, contents: new TextEncoder().encode(text) }, dir + '/save.cfg');
        tx.oncomplete = resolve;
        tx.onerror = () => reject(tx.error);
      });
      db.close();
    },
    { body: SAVE_BODY, dir: SAVE_DIR },
  );
}

async function main() {
  const base = (process.argv[2] || '').replace(/\/+$/, '');
  const watchSeconds = Number(process.argv[3] || 5);
  const bootTimeoutSeconds = Number(process.argv[4] || 90);
  if (!base || !(watchSeconds > 0) || !(bootTimeoutSeconds > 0)) {
    console.error('usage: node web-load-check.js <base-url> [watch-seconds] [boot-timeout-seconds]');
    return 2;
  }
  let playwright;
  try {
    playwright = require('playwright');
  } catch (e) {
    console.error('web-load-check: cannot load the playwright package (set NODE_PATH): ' + e.message);
    return 3;
  }
  const { chromium, devices } = playwright;
  let browser;
  try {
    browser = await chromium.launch();
    const context = await browser.newContext({ ...devices['Pixel 7'] });

    // Phase 1: a fresh profile.
    const first = await boot(context, base + '/index.html', 'phase 1 (fresh save)', watchSeconds, bootTimeoutSeconds);
    await first.page.close();

    // Phase 2: a non-empty save. A 404 page of the same origin runs no engine, so the save is not overwritten.
    const seeder = await context.newPage();
    try {
      await seeder.goto(base + '/web-load-check-seed.404', { waitUntil: 'load', timeout: 30000 });
      await seedSave(seeder);
    } catch (e) {
      throw new Fail(3, ['phase 2: could not write the save into IndexedDB: ' + e.message]);
    }
    await seeder.close();
    const second = await boot(context, base + '/index.html', 'phase 2 (non-empty save)', watchSeconds, bootTimeoutSeconds);
    const page = second.page;
    const clip = () => {
      const vp = page.viewportSize();
      return { x: 0, y: 0, width: vp.width, height: Math.floor(vp.height * 0.55) }; // the buttons, not the ad banner
    };
    const before = await page.screenshot({ clip: clip() });
    const vp = page.viewportSize();
    await page.touchscreen.tap(vp.width * TAP_SKIRMISH[0], vp.height * TAP_SKIRMISH[1]);
    await page.waitForTimeout(2000);
    const after = await page.screenshot({ clip: clip() });
    if (before.equals(after)) {
      throw new Fail(4, [
        'phase 2 (non-empty save): the main menu did not answer: the screen did not change after a tap on SKIRMISH',
        '  (or the menu did not show: the page looked the same 2 s after the tap)',
      ]);
    }
    console.log(
      'web-load-check: OK, both phases booted (' + first.bootText + ' fresh, ' + second.bootText + ' with a save), ' +
        'no script error within ' + watchSeconds + ' s after each, and the menu answered the tap on SKIRMISH',
    );
    return 0;
  } catch (e) {
    if (e instanceof Fail) {
      console.error('web-load-check: FAIL, ' + e.lines[0]);
      for (const line of e.lines.slice(1)) console.error(line);
      return e.code;
    }
    console.error('web-load-check: could not run: ' + e.message);
    return 3;
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error('web-load-check: ' + e.message);
    process.exit(3);
  },
);
