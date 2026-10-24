// Captures a page with its first .proc row hovered. Called by preview-panel.mjs.
const { app, BrowserWindow, nativeTheme } = require("electron");
const fs = require("node:fs");
app.dock?.hide();
app.whenReady().then(async () => {
  const [theme, file, out] = process.argv.slice(-3);
  nativeTheme.themeSource = theme;
  const win = new BrowserWindow({ width: 420, height: 1000, show: false, transparent: true, frame: false, webPreferences: { offscreen: true } });
  await win.loadFile(file);
  await new Promise((r) => setTimeout(r, 400));
  // Hover the first process row so the Quit button and highlight show.
  const pt = await win.webContents.executeJavaScript(
    "(() => { const r = document.querySelector('.proc')?.getBoundingClientRect(); return r ? { x: Math.round(r.left + 40), y: Math.round(r.top + r.height / 2) } : null; })()");
  if (pt) win.webContents.sendInputEvent({ type: "mouseMove", x: pt.x, y: pt.y });
  await new Promise((r) => setTimeout(r, 300));
  const rect = await win.webContents.executeJavaScript(
    "(() => { const r = document.getElementById('frame').getBoundingClientRect(); return { x: 0, y: 0, width: Math.ceil(r.right + 14), height: Math.ceil(r.bottom + 14) }; })()");
  fs.writeFileSync(out, (await win.webContents.capturePage(rect)).toPNG());
  console.log("saved", out);
  app.quit();
}).catch((e) => { console.error(e); app.exit(1); });
