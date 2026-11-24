// Loads a served web export in headless Chromium (Pixel 7 emulation) and fails on script errors.
// Called by scripts/ci/check-web-load.sh, which serves the build; run it through that script.
// Usage: node web-load-check.js <url> [watch-seconds]
// Needs: the `playwright` package resolvable (NODE_PATH) and a Chromium that chromium.launch() finds.
// Exit: 0 no script error in the console during the watch time
//       1 a console line matched ERROR_PATTERN, or the page threw an uncaught error
//       2 usage error
//       3 the browser or the page could not be started or loaded
'use strict';

// What Godot prints to the browser console when a script does not compile or load. "SCRIPT ERROR"
// covers runtime errors too. Plain "ERROR:" lines are not matched: engine errors that never touch a
// script (a missing optional resource) are not what this guard is for.
const ERROR_PATTERN = /SCRIPT ERROR|Parse Error|Compile Error|Failed to load script/;

async function main() {
  const url = process.argv[2];
  const watchSeconds = Number(process.argv[3] || 15);
  if (!url || !(watchSeconds > 0)) {
    console.error('usage: node web-load-check.js <url> [watch-seconds]');
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
  const hits = [];
  try {
    browser = await chromium.launch();
    const context = await browser.newContext({ ...devices['Pixel 7'] });
    const page = await context.newPage();
    page.on('console', (msg) => {
      if (ERROR_PATTERN.test(msg.text())) hits.push(msg.text().split('\n')[0]);
    });
    // Godot writes "at: ..." as the next console line; keep it, it names the file and line.
    page.on('console', (msg) => {
      if (/^\s+at: /.test(msg.text()) && hits.length > 0) hits.push(msg.text());
    });
    page.on('pageerror', (err) => hits.push('uncaught page error: ' + err.message));
    await page.goto(url, { waitUntil: 'load', timeout: 60000 });
    await page.waitForTimeout(watchSeconds * 1000);
  } catch (e) {
    console.error('web-load-check: could not load ' + url + ': ' + e.message);
    return 3;
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
  if (hits.length > 0) {
    console.error('web-load-check: FAIL, the web build logged script errors within ' + watchSeconds + ' s:');
    for (const line of hits.slice(0, 40)) console.error('  ' + line);
    return 1;
  }
  console.log('web-load-check: OK, no script error within ' + watchSeconds + ' s');
  return 0;
}

main().then(
  (code) => process.exit(code),
  (e) => {
    console.error('web-load-check: ' + e.message);
    process.exit(3);
  },
);
