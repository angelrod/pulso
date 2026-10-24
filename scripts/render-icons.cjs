const { app, BrowserWindow } = require("electron");
const fs = require("node:fs");
const path = require("node:path");

// Heartbeat line shared by both icons, on a 32x32 grid.
// Run: env -u ELECTRON_RUN_AS_NODE node_modules/electron/dist/Electron.app/Contents/MacOS/Electron scripts/render-icons.cjs resources
const PULSE = "M2 17 H9 L12 9 L16 25 L20 5 L23 17 H30";

const appIcon = (size) => `
<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1fb58a"/><stop offset="1" stop-color="#0b6b5a"/>
    </linearGradient>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
  <g transform="translate(192 192) scale(20)">
    <path d="${PULSE}" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>
  </g>
</svg>`;

// Black is a template macOS recolours; orange and red are the system colours for alerts.
const trayIcon = (colour = "#000") => `
<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 32 32">
  <path d="${PULSE}" fill="none" stroke="${colour}" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>
</svg>`;

const jobs = [
  ["icon.png", appIcon(512), 1024],
  ["trayTemplate.png", trayIcon(), 16],
  ["trayTemplate@2x.png", trayIcon(), 32],
  ["trayWarning.png", trayIcon("#FF9F0A"), 16],
  ["trayWarning@2x.png", trayIcon("#FF9F0A"), 32],
  ["trayCritical.png", trayIcon("#FF453A"), 16],
  ["trayCritical@2x.png", trayIcon("#FF453A"), 32],
];

app.dock?.hide();
app.whenReady().then(async () => {
  const out = process.argv[process.argv.length - 1];
  const win = new BrowserWindow({
    width: 512, height: 512, show: false, transparent: true, frame: false,
    useContentSize: true, webPreferences: { offscreen: true },
  });
  for (const [name, svg, size] of jobs) {
    const file = path.join(out, `_${size}_${name}.html`);
    fs.writeFileSync(file, `<html><body style="margin:0;background:transparent">${svg}</body></html>`);
    await win.loadFile(file);
    await new Promise((r) => setTimeout(r, 300));
    const img = await win.webContents.capturePage({ x: 0, y: 0, width: 512, height: 512 });
    fs.writeFileSync(path.join(out, name), img.resize({ width: size, height: size, quality: "best" }).toPNG());
    fs.unlinkSync(file);
    console.log(name, size);
  }
  app.quit();
}).catch((e) => { console.error(e); app.exit(1); });
