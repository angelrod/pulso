// Captures a page with its first .proc row hovered, and prints layout metrics measured
// before and after the hover. Called by preview-panel.mjs.
const { app, BrowserWindow, nativeTheme } = require("electron");
const fs = require("node:fs");

// Row heights, panel height and the pointer/selection style of the elements users touch.
const MEASURE = `(() => {
  const style = (sel) => {
    const el = document.querySelector(sel);
    if (!el) return null;
    const s = getComputedStyle(el);
    return { cursor: s.cursor, userSelect: s.userSelect };
  };
  return {
    rows: [...document.querySelectorAll('.proc')].map((r) => Math.round(r.getBoundingClientRect().height * 100) / 100),
    panel: Math.round(document.querySelector('.panel').getBoundingClientRect().height * 100) / 100,
    styles: {
      processRow: style('.proc'),
      processName: style('.proc .name'),
      action: style('[data-action]:not(.quit-btn)'),
      tileValue: style('.tile .value'),
      footer: style('.foot'),
    },
  };
})()`;

app.dock?.hide();
app.whenReady().then(async () => {
  const [theme, file, out] = process.argv.slice(-3);
  nativeTheme.themeSource = theme;
  const win = new BrowserWindow({ width: 420, height: 1000, show: false, transparent: true, frame: false, webPreferences: { offscreen: true } });
  await win.loadFile(file);
  await new Promise((r) => setTimeout(r, 400));
  const before = await win.webContents.executeJavaScript(MEASURE);
  // Hover the first process row so the Quit button and highlight show.
  const pt = await win.webContents.executeJavaScript(
    "(() => { const r = document.querySelector('.proc')?.getBoundingClientRect(); return r ? { x: Math.round(r.left + 40), y: Math.round(r.top + r.height / 2) } : null; })()");
  if (pt) win.webContents.sendInputEvent({ type: "mouseMove", x: pt.x, y: pt.y });
  await new Promise((r) => setTimeout(r, 300));
  const after = await win.webContents.executeJavaScript(MEASURE);
  const rect = await win.webContents.executeJavaScript(
    "(() => { const r = document.getElementById('frame').getBoundingClientRect(); return { x: 0, y: 0, width: Math.ceil(r.right + 14), height: Math.ceil(r.bottom + 14) }; })()");
  fs.writeFileSync(out, (await win.webContents.capturePage(rect)).toPNG());
  console.log(`PANEL_METRICS ${JSON.stringify({ before, afterHoveringFirstRow: after })}`);
  app.quit();
}).catch((e) => { console.error(e); app.exit(1); });
