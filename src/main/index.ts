import { app, BrowserWindow, dialog, ipcMain, nativeImage, screen, shell, Tray } from "electron";
import type { IpcMainEvent } from "electron";

import { join } from "node:path";

import { mkdirSync, writeFileSync } from "node:fs";

import { createCollector } from "./collect";
import { quitAppBundle } from "./quit";
import { buildPanelView, quitPrompt, type PanelView } from "./panel";
import {
  helpDialog,
  trayIconName,
  trayTitle,
  trayTooltip,
} from "./tray";
import type { Snapshot } from "./tray";
import { CHANNELS, parseAction } from "../shared/bridge";
import { groupByApp, type AppGroup } from "./metrics";
import { RELEASES_API, isNewer, parseLatestRelease, type AvailableUpdate } from "./update";

// A Tray held only by a local variable is garbage-collected and vanishes from the bar.
let tray: Tray | null = null;
// Only one Pulso may live in the bar; a second instance must quit.
const primary = app.requestSingleInstanceLock();
if (!primary) app.quit();
// The one collector, shared by the timer, the actions and the panel.
const collect = createCollector();
// The last good snapshot, so a killed process is named from its captured command.
let last: Snapshot | null = null;
let timer: NodeJS.Timeout | null = null;
// The in-flight collection; callers during it await the same one instead of stacking.
let inFlight: Promise<Snapshot | null> | null = null;
// The panel window, held at module scope like the tray so it is not garbage-collected.
let panel: BrowserWindow | null = null;
// Resolves once the page has loaded, so the first view is not lost before the page subscribes.
let panelReady: Promise<void> | null = null;
// Blur hides the panel; record when, so a tray click right after it closes rather than reopens.
let lastBlurHide = 0;
// The last available update the check found, null when there is none.
let offer: AvailableUpdate | null = null;

// In dev resources/ sits in the app dir; in the bundle it lives under process.resourcesPath.
const resources = app.isPackaged
  ? join(process.resourcesPath, "resources")
  : join(app.getAppPath(), "resources");
const icon = nativeImage.createFromPath(join(resources, "icon.png"));

// What the macOS About panel shows; icon and version come from these live values.
app.setAboutPanelOptions({
  applicationName: "Pulso",
  applicationVersion: app.getVersion(),
  iconPath: join(resources, "icon.png"),
  credits: "Memory and CPU at a glance, in the menu bar.",
});

// Three tray images loaded once; only the plain template gets recoloured by macOS.
const trayImages = {
  trayTemplate: templateImage("trayTemplate"),
  trayWarning: nativeImage.createFromPath(join(resources, "trayWarning.png")),
  trayCritical: nativeImage.createFromPath(join(resources, "trayCritical.png")),
};

// A template image is recoloured black/white by macOS; the orange and red keep theirs.
function templateImage(name: string): Electron.NativeImage {
  const image = nativeImage.createFromPath(join(resources, `${name}.png`));
  image.setTemplateImage(true);
  return image;
}

/** Collects once even when callers arrive together, reusing the last read on failure. */
function collectFresh(): Promise<Snapshot | null> {
  if (inFlight) return inFlight;
  inFlight = collect()
    .then((snapshot) => {
      last = snapshot;
      // Every successful collection refreshes the bar, wherever it was started from.
      if (tray) {
        tray.setTitle(trayTitle(snapshot));
        tray.setToolTip(trayTooltip(snapshot));
        // The colour follows pressure; only the plain template is recoloured by macOS.
        tray.setImage(trayImages[trayIconName(snapshot)]);
      }
      // While the panel is visible, a successful collection pushes the new view live.
      if (panel) sendView(buildPanelView(snapshot, 3, offer));
      return snapshot;
    })
    .catch((err) => {
      console.error("Collection failed:", err);
      return last;
    })
    .finally(() => {
      inFlight = null;
    });
  return inFlight;
}

/** Sends the built view to the renderer, skipping it if the page is not ready yet. */
function sendView(view: PanelView): void {
  if (panel?.webContents.isDestroyed() === false) panel.webContents.send(CHANNELS.view, view);
}

/** Asks an app to quit (⌘Q) or signals a lone process, after a confirm dialog. */
async function quitProcess(pid: number): Promise<void> {
  // A row whose group is missing, or no snapshot yet, falls back to a one-process group.
  const found = last?.processes && pid > 0 ? groupByApp(last.processes).find((g) => g.pids.includes(pid)) : undefined;
  const group = found ?? oneProcessGroup(pid);

  // Refuse without asking to quit this app (via any of its pids) or a core process.
  if (group.pids.includes(process.pid) || pid < 2) {
    void dialog.showMessageBox({
      icon,
      type: "error",
      title: "Cannot quit",
      message: `PID ${pid} is this app or a core system process you cannot quit.`,
    });
    void collectFresh();
    return;
  }

  const { message, detail, button } = quitPrompt(group);
  const { response } = await dialog.showMessageBox({
    icon,
    type: "question",
    message,
    detail,
    buttons: ["Cancel", button],
    defaultId: 0,
    cancelId: 0,
  });
  if (response !== 1) {
    void collectFresh();
    return;
  }

  await runQuit(group).catch((err: Error) => {
    // The user hears why the quit failed before the refresh brings the bar back.
    void dialog.showMessageBox({ icon, type: "error", message: err.message });
  }).finally(() => {
    void collectFresh();
  });
}

/** A one-process group for a row outside any app, so today's SIGTERM flow still applies. */
function oneProcessGroup(pid: number): AppGroup {
  return { name: String(pid), bundlePath: null, pids: [pid], mainPid: pid, rssBytes: 0, cpu: 0 };
}

/** Asks an app to quit via Apple Events, else signals the process; EPERM/ESRCH stays specific. */
async function runQuit(group: AppGroup): Promise<void> {
  if (group.bundlePath) {
    await quitAppBundle(group.bundlePath);
    return;
  }
  try {
    await process.kill(group.pids[0]!, "SIGTERM");
  } catch (err) {
    const e = err as NodeJS.ErrnoException;
    const code = e.code;
    const reason =
      code === "EPERM"
        ? "You do not have permission to quit it; it belongs to another user or the system."
        : code === "ESRCH"
          ? "It has already exited."
          : `It could not be quit: ${code ?? e.message}`;
    throw new Error(reason);
  }
}

/** Shows the glossary dialog, focusing the app and hiding the panel so it is seen. */
function showHelp(): void {
  // The dialog opens behind the app without this, same reason showAbout needs it.
  app.focus({ steal: true });
  const { message, detail } = helpDialog();
  hidePanel();
  void dialog.showMessageBox({ icon, message, detail, buttons: ["OK"] });
}

/** Hides the panel before any blocking UI, so a dialog cannot show behind it. */
function hidePanel(): void {
  panel?.hide();
}

/** Quit the app cleanly, stopping the timer and releasing the panel reference. */
function quitApp(): void {
  if (timer) clearInterval(timer);
  panel = null;
  app.quit();
}

// Open the panel as a click would: reuse a sub-second read, else collect, else the last one.
async function open(): Promise<void> {
  // Blur closed it <300 ms ago: this click is the toggle-back, so ignore it.
  if (Date.now() - lastBlurHide < 300) return;
  let snapshot: Snapshot | null;
  if (last && Date.now() - last.takenAt.getTime() < 1000) {
    snapshot = last;
  } else {
    snapshot = await collectFresh();
  }
  if (!snapshot) {
    // Nothing good to show; the bar already holds the stale one, so stay closed.
    console.error("The panel could not open without a snapshot.");
    return;
  }
  // Await the page loading first, so this first view is not dropped before it subscribes.
  await panelReady;
  // Send the view first so showing it later does not flash the old content.
  sendView(buildPanelView(snapshot, 3, offer));
  positionPanel();
  app.focus({ steal: true });
  panel!.show();
  panel!.focus();
}

// Centres the panel under the icon, 4 px below it, clamped to the display work area.
function positionPanel(): void {
  const trayBounds = tray!.getBounds();
  const panelWidth = 340;
  const panelHeight = panel!.getSize()[1] ?? 520;
  const x = Math.round(trayBounds.x + (trayBounds.width - panelWidth) / 2);
  const y = Math.round(trayBounds.y + trayBounds.height + 4);
  const display = screen.getDisplayNearestPoint({ x: x + 1, y: y + 1 });
  const area = display.workArea;
  const clampedX = Math.min(Math.max(x, area.x), area.x + area.width - panelWidth);
  const clampedY = Math.min(Math.max(y, area.y), area.y + area.height - panelHeight);
  panel!.setPosition(clampedX, clampedY, true);
}

/** Handles an incoming action: only from the panel, only a well-formed one. */
function handleAct(event: IpcMainEvent, raw: unknown): void {
  if (panel === null || event.sender !== panel.webContents) return;
  const action = parseAction(raw);
  if (action === null) return;
  switch (action.type) {
    case "refresh":
      void collectFresh();
      break;
    case "close":
      hidePanel();
      break;
    case "quit-app":
      quitApp();
      break;
    case "activity-monitor":
      hidePanel();
      void shell.openPath("/System/Applications/Utilities/Activity Monitor.app").then((err) => {
        if (err) console.error("Opening Activity Monitor failed:", err);
      });
      break;
    case "about":
      hidePanel();
      app.showAboutPanel();
      break;
    case "quit-process":
      void quitProcess(action.pid);
      break;
    case "help":
      showHelp();
      break;
    case "download-update":
      downloadUpdate();
      break;
  }
}

/** Accepts a finite resize height, clamped, and sizes the panel to it. */
function handleResize(event: IpcMainEvent, height: number): void {
  if (panel === null || event.sender !== panel.webContents || !Number.isFinite(height)) return;
  panel.setSize(340, Math.round(Math.min(900, Math.max(200, height))));
}

/** Asks GitHub for the latest release and keeps the offer only when it is newer, never throwing. */
function checkForUpdate(): void {
  fetch(RELEASES_API, {
    headers: { Accept: "application/vnd.github+json", "User-Agent": `Pulso/${app.getVersion()}` },
    signal: AbortSignal.timeout(10_000),
  })
    .then(async (res) => {
      if (!res.ok) throw new Error(`GitHub responded with ${res.status}`);
      const release = parseLatestRelease(await res.json());
      // Keep the parsed release only if it is newer, else clear it so no row is offered.
      offer = isNewer(release?.version ?? "", app.getVersion()) ? release : null;
    })
    .catch((err: Error) => {
      // A network error, timeout or bad JSON keeps the previous offer.
      console.error("The update check failed:", err);
    });
}

/** Opens the release page: the URL comes only from the stored, already-checked offer. */
function downloadUpdate(): void {
  if (!offer) return;
  hidePanel();
  void shell.openExternal(offer.url);
}

app.dock?.hide();

app.whenReady().then(() => {
  if (!primary) return;
  tray = new Tray(trayImages.trayTemplate);
  tray.setToolTip("Pulso");
  tray.on("click", open);
  tray.on("right-click", open);
  panel = new BrowserWindow({
    width: 340,
    height: 520,
    show: false,
    frame: false,
    resizable: false,
    movable: false,
    minimizable: false,
    maximizable: false,
    fullscreenable: false,
    skipTaskbar: true,
    transparent: true,
    vibrancy: "menu",
    visualEffectState: "active",
    roundedCorners: true,
    hasShadow: true,
    webPreferences: {
      preload: join(__dirname, "../preload/index.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  // The first view is sent after open() awaits this, so it lands once the page can receive it.
  panelReady = new Promise<void>((resolve) => {
    panel!.webContents.once("did-finish-load", () => {
      panelReady = null;
      resolve();
    });
  });
  // Load the renderer: the dev server URL in dev, the built file otherwise.
  if (process.env.ELECTRON_RENDERER_URL) {
    void panel.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    void panel.loadFile(join(__dirname, "../renderer/index.html"));
  }
  // Without this it can open on another Space, not the current one, or under a full-screen app.
  panel.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true });
  panel.on("blur", () => {
    // Blur closes the panel as a menu does; record the moment so the next click can toggle it.
    if (panel!.isVisible()) lastBlurHide = Date.now();
    hidePanel();
  });
  // The panel sends actions and heights; both are ignored unless they come from it.
  ipcMain.on(CHANNELS.act, handleAct);
  ipcMain.on(CHANNELS.resize, handleResize);
  timer = setInterval(() => {
    // A failed tick keeps the timer running; the title updates on success in collectFresh.
    void collectFresh();
  }, 3000);
  void collectFresh();

  // GitHub check 10s after startup, then every 24 hours. The debug hook pins the offer.
  if (!app.isPackaged && process.env.PULSO_DEBUG_UPDATE === "1") {
    offer = parseLatestRelease({
      tag_name: "v9.9.9",
      html_url: "https://github.com/angelrod/pulso/releases/tag/v9.9.9",
      draft: false,
      prerelease: false,
    });
  } else {
    setTimeout(checkForUpdate, 10_000);
    setInterval(checkForUpdate, 24 * 60 * 60 * 1000);
  }

  // When PULSO_DEBUG_PANEL=1, open the panel two seconds after ready, then log and snapshot it.
  if (process.env.PULSO_DEBUG_PANEL === "1") {
    setTimeout(() => {
      void open().then(() => setTimeout(debugSnapshot, 500));
    }, 2000);
  }
});

/** Logs the debug line and saves the panel window as a PNG for manual review. */
async function debugSnapshot(): Promise<void> {
  const bounds = panel!.getBounds();
  console.log(
    `PULSO_DEBUG {"tray":${JSON.stringify(tray!.getBounds())},"panel":${JSON.stringify(bounds)},"visible":${panel!.isVisible()}}`,
  );
  mkdirSync("/tmp/pulso-preview", { recursive: true });
  const png = await panel!.webContents.capturePage();
  writeFileSync("/tmp/pulso-preview/window.png", png.toPNG());
}
