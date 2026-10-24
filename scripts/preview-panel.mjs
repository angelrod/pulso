// Renders the panel with sample data and the first process row hovered, to a PNG the
// developer can open, to check CSS changes by eye.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { join } from "node:path";

const root = join(import.meta.dirname, "..");
const out = "/tmp/pulso-preview";
// --light renders macOS light mode; the default is dark.
const light = process.argv.includes("--light");
mkdirSync(out, { recursive: true });

// esbuild ships with vite; resolving it from there avoids a new dependency.
const esbuild = createRequire(createRequire(import.meta.url).resolve("vite"))("esbuild");

const entry = `
import { renderPanel } from "./src/renderer/render";
export const html = renderPanel({
  memory: { percent: "85%", detail: "27.2 GB of 32.0 GB",
    help: "How much memory is in use. A high number is normal on a Mac.", barPercent: 85.1 },
  tone: "warning",
  advice: "Your Mac is starting to slow down. Quitting a heavy app below will help.",
  tiles: [
    { label: "Pressure", value: "Warning", help: "How hard your Mac is working to find free memory." },
    { label: "Swap", value: "20.0 GB", help: "Memory moved to the disk when it ran out of room." },
    { label: "CPU", value: "22%", help: "How busy the processor is right now." },
  ],
  processes: [
    { pid: 1, name: "Google Chrome", memory: "5.7 GB", cpu: "23.1%", share: 1 },
    { pid: 2, name: "Cursor", memory: "3.0 GB", cpu: "15.4%", share: 0.53 },
    { pid: 3, name: "Slack", memory: "551.2 MB", cpu: "4.2%", share: 0.1 },
    { pid: 4, name: "node", memory: "363.2 MB", cpu: "0.3%", share: 0.06 },
    { pid: 5, name: "WindowServer", memory: "252.1 MB", cpu: "12.0%", share: 0.04 },
  ],
  updated: "Updated 00:42:00 · refreshes every 3 s",
  update: null,
});`;

const built = await esbuild.build({
  stdin: { contents: entry, resolveDir: root, loader: "ts" },
  bundle: true,
  format: "esm",
  platform: "node",
  write: false,
});
const { html } = await import(
  "data:text/javascript;base64," + Buffer.from(built.outputFiles[0].text).toString("base64")
);

const css = readFileSync(join(root, "src/renderer/panel.css"), "utf8");
// Stand-in for the macOS menu material the real window draws behind the panel.
const material = light
  ? "linear-gradient(180deg,rgba(246,246,246,.97),rgba(236,236,236,.97))"
  : "linear-gradient(180deg,rgba(58,58,62,.97),rgba(44,44,48,.97))";
const backdrop = `html{background:${light ? "#d9d9de" : "#1c1c1e"}}
#frame{display:inline-block;margin:14px;width:340px;border-radius:12px;overflow:hidden;
background:${material}}`;
const page = join(out, "panel.html");
writeFileSync(page, `<!doctype html><html><head><meta charset="utf-8"><style>${css}</style>
<style>${backdrop}</style></head><body><div id="frame">${html}</div></body></html>`);

const png = join(out, light ? "panel-light.png" : "panel.png");
const electron = join(root, "node_modules/electron/dist/Electron.app/Contents/MacOS/Electron");
const env = { ...process.env };
delete env.ELECTRON_RUN_AS_NODE;
execFileSync(electron, [join(root, "scripts/shot-panel.cjs"), light ? "light" : "dark", page, png], {
  env,
  stdio: "ignore",
});
console.log(`Preview written to ${png} (first process row hovered). Open it with Read.`);
