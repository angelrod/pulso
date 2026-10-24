/**
 * Tests for the panel's view model.
 *
 * The panel replaces a native menu, which cannot show tiles or section headers.
 * `panel.ts` turns a snapshot into plain data: every text the panel shows is decided
 * here, so the renderer only lays it out.
 */
import { describe, expect, it } from "vitest";

import { buildPanelView, quitPrompt } from "./panel";
import type { Snapshot } from "./tray";

const snapshot: Snapshot = {
  takenAt: new Date(2026, 9, 23, 15, 30, 5),
  memory: {
    totalBytes: 34359738368,
    usedBytes: 24159191040,
    freeBytes: 10200547328,
    wiredBytes: 6442450944,
    compressedBytes: 1073741824,
    usedPercent: 70.3,
  },
  cpuPercent: 18.4,
  pressure: "normal",
  swapUsedBytes: 1073741824,
  processes: [
    { pid: 77, cpu: 3.5, rssBytes: 120000000, command: "/usr/sbin/notifyd" },
    { pid: 4812, cpu: 92.1, rssBytes: 1500000000, command: "/usr/bin/mediaanalysisd" },
    { pid: 901, cpu: 12.0, rssBytes: 750000000, command: "/Applications/Chrome.app/Contents/MacOS/Chrome" },
  ],
};

const view = (over: Partial<Snapshot> = {}) => buildPanelView({ ...snapshot, ...over }, 3);

describe("buildPanelView: memory", () => {
  it("leads with the whole percent and the amounts", () => {
    const { memory } = view();
    expect(memory.percent).toBe("70%");
    expect(memory.detail).toBe("22.5 GB of 32.0 GB");
    expect(memory.help).toBe("How much memory is in use. A high number is normal on a Mac.");
  });

  it("fills the bar to the exact percent, kept between 0 and 100", () => {
    expect(view().memory.barPercent).toBeCloseTo(70.3, 10);
    const over = view({ memory: { ...snapshot.memory, usedPercent: 104 } });
    expect(over.memory.barPercent).toBe(100);
  });
});

describe("buildPanelView: tone and advice", () => {
  it("takes its tone from memory pressure alone", () => {
    expect(view().tone).toBe("normal");
    expect(view({ pressure: "warning" }).tone).toBe("warning");
    expect(view({ pressure: "critical" }).tone).toBe("critical");
    const full = view({ memory: { ...snapshot.memory, usedPercent: 99 } });
    expect(full.tone).toBe("normal");
  });

  it("gives advice only when pressure is not normal", () => {
    expect(view().advice).toBeNull();
    expect(view({ pressure: "warning" }).advice).toBe(
      "Your Mac is starting to slow down. Quitting a heavy app below will help.",
    );
    expect(view({ pressure: "critical" }).advice).toBe(
      "Your Mac is short of memory. Quit an app below now.",
    );
  });
});

describe("buildPanelView: tiles", () => {
  it("shows pressure, swap and cpu in that order, each with its explanation", () => {
    expect(view({ pressure: "warning" }).tiles).toEqual([
      {
        label: "Pressure",
        value: "Warning",
        help: "How hard your Mac is working to find free memory. The one to watch.",
      },
      {
        label: "Swap",
        value: "1.0 GB",
        help: "Memory moved to the disk when it ran out of room. Many GB feels slower.",
      },
      { label: "CPU", value: "18%", help: "How busy the processor is right now." },
    ]);
  });
});

describe("buildPanelView: processes", () => {
  it("lists the heaviest by memory, by short name, with memory and cpu", () => {
    const { processes } = view();
    expect(processes.map((p) => p.pid)).toEqual([4812, 901, 77]);
    expect(processes[0]).toEqual({
      pid: 4812,
      name: "mediaanalysisd",
      memory: "1.4 GB",
      cpu: "92.1%",
      share: 1,
    });
    expect(processes[1]!.name).toBe("Chrome");
  });

  it("sizes each row's bar against the heaviest process", () => {
    const { processes } = view();
    expect(processes[1]!.share).toBeCloseTo(0.5, 10);
    expect(processes[2]!.share).toBeCloseTo(0.08, 10);
  });

  it("shows at most five", () => {
    const many = Array.from({ length: 9 }, (_, i) => ({
      pid: 100 + i,
      cpu: 0,
      rssBytes: (i + 1) * 1000,
      command: `/bin/p${i}`,
    }));
    expect(view({ processes: many }).processes.length).toBe(5);
  });

  it("copes with no processes and with all of them at zero bytes", () => {
    expect(view({ processes: [] }).processes).toEqual([]);
    const zero = view({ processes: [{ pid: 9, cpu: 0, rssBytes: 0, command: "/bin/z" }] });
    expect(zero.processes[0]!.share).toBe(0);
  });
});

describe("buildPanelView: footer", () => {
  it("says when the reading was taken and how often it refreshes", () => {
    expect(view().updated).toBe("Updated 15:30:05 · refreshes every 3 s");
    expect(buildPanelView(snapshot, 5).updated).toBe("Updated 15:30:05 · refreshes every 5 s");
  });

  it("does not change the snapshot it was given", () => {
    const before = snapshot.processes.map((p) => p.pid);
    view();
    expect(snapshot.processes.map((p) => p.pid)).toEqual(before);
  });
});

// One row per app. Chrome's helpers
// count towards Chrome, so the list says what to quit to free memory.
describe("buildPanelView: one row per app", () => {
  const app = "/Applications/Google Chrome.app";
  const grouped = (processes: Snapshot["processes"]) => buildPanelView({ ...snapshot, processes }, 3);

  it("sums an app's helpers into one row, keyed by the main process", () => {
    const { processes } = grouped([
      { pid: 760, cpu: 1, rssBytes: 800000000, command: `${app}/Contents/MacOS/Google Chrome` },
      { pid: 761, cpu: 2, rssBytes: 700000000, command: `${app}/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)` },
      { pid: 77, cpu: 3.5, rssBytes: 120000000, command: "/usr/sbin/notifyd" },
    ]);
    expect(processes.map((p) => p.name)).toEqual(["Google Chrome", "notifyd"]);
    expect(processes[0]).toMatchObject({ pid: 760, memory: "1.4 GB", cpu: "3.0%", share: 1 });
  });

  it("keys an app row by its first process when its main one is not running", () => {
    const { processes } = grouped([
      { pid: 761, cpu: 0, rssBytes: 700, command: `${app}/Contents/Frameworks/H.app/Contents/MacOS/H` },
      { pid: 762, cpu: 0, rssBytes: 100, command: `${app}/Contents/Frameworks/G.app/Contents/MacOS/G` },
    ]);
    expect(processes).toHaveLength(1);
    expect(processes[0]!.pid).toBe(761);
  });

  it("ranks apps by their total, not by their biggest process", () => {
    const { processes } = grouped([
      { pid: 1, cpu: 0, rssBytes: 500, command: "/bin/big" },
      { pid: 2, cpu: 0, rssBytes: 300, command: `${app}/Contents/MacOS/Google Chrome` },
      { pid: 3, cpu: 0, rssBytes: 300, command: `${app}/Contents/Frameworks/H.app/Contents/MacOS/H` },
    ]);
    expect(processes.map((p) => p.name)).toEqual(["Google Chrome", "big"]);
  });
});

describe("quitPrompt", () => {
  it("says an app quits as a whole, with its processes and memory", () => {
    const prompt = quitPrompt({
      name: "Google Chrome",
      bundlePath: "/Applications/Google Chrome.app",
      pids: [760, 761, 762],
      mainPid: 760,
      rssBytes: 1500000000,
      cpu: 3,
    });
    expect(prompt).toEqual({
      message: "Quit Google Chrome?",
      detail: "This closes all its windows (3 processes, 1.4 GB).",
      button: "Quit App",
    });
  });

  it("uses the singular for one process", () => {
    const prompt = quitPrompt({
      name: "Slack",
      bundlePath: "/Applications/Slack.app",
      pids: [900],
      mainPid: 900,
      rssBytes: 1024 ** 2,
      cpu: 0,
    });
    expect(prompt.detail).toBe("This closes all its windows (1 process, 1.0 MB).");
  });

  it("keeps today's wording for a process outside any app", () => {
    const prompt = quitPrompt({ name: "node", bundlePath: null, pids: [50], mainPid: 50, rssBytes: 280 * 1024 ** 2, cpu: 3 });
    expect(prompt).toEqual({
      message: 'Quit "node"?',
      detail: "PID 50 · using 280.0 MB. Anything unsaved in it will be lost.",
      button: "Quit Process",
    });
  });
});

// A newer release, when the daily check found one. The URL never reaches the renderer:
// the main process keeps it and opens it on "download-update".
describe("buildPanelView: update", () => {
  it("has no update line unless one is passed in", () => {
    expect(view().update).toBeNull();
  });

  it("names the new version", () => {
    const withUpdate = buildPanelView(snapshot, 3, {
      version: "0.2.0",
      url: "https://github.com/angelrod/pulso/releases/tag/v0.2.0",
    });
    expect(withUpdate.update).toEqual({ text: "Pulso 0.2.0 is available" });
    expect(JSON.stringify(withUpdate)).not.toContain("https://");
  });
});
