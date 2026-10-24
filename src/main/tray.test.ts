/**
 * Tests for the menu bar item.
 *
 * `tray.ts` decides what the menu bar item shows: title, icon colour and tooltip,
 * plus the glossary dialog. The dropdown is the panel (`panel.test.ts`).
 */
import { describe, expect, it } from "vitest";

import { helpDialog, trayIconName, trayTitle, trayTooltip, type Snapshot } from "./tray";

const snapshot: Snapshot = {
  takenAt: new Date(2026, 9, 23, 15, 30),
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
    { pid: 4812, cpu: 92.1, rssBytes: 1500000000, command: "/usr/bin/mediaanalysisd" },
    { pid: 901, cpu: 12.0, rssBytes: 800000000, command: "/Applications/Chrome.app/Chrome" },
    { pid: 77, cpu: 3.5, rssBytes: 120000000, command: "/usr/sbin/notifyd" },
  ],
};

describe("trayTitle", () => {
  it("fits the menu bar: a short summary of the state", () => {
    const title = trayTitle(snapshot);
    expect(title.length).toBeLessThanOrEqual(12);
    expect(title).toContain("70");
  });

  // A bare "70%" does not say what it measures.
  it("says what it measures", () => {
    expect(trayTitle(snapshot)).toBe("RAM 70%");
  });

  // A ⚠ made the title too long. Pressure colours the icon instead (see trayIconName),
  // and the title stays the bare number.
  it("stays the bare number whatever the pressure", () => {
    for (const pressure of ["normal", "warning", "critical"] as const) {
      const title = trayTitle({ ...snapshot, pressure, memory: { ...snapshot.memory, usedPercent: 100 } });
      expect(title).toBe("RAM 100%");
    }
  });
});

// Colour follows memory pressure, not percent used. A Mac at 85% is often fine;
// pressure says whether it is struggling. Names match resources/.
describe("trayIconName", () => {
  it("is the plain template when pressure is normal, however full memory is", () => {
    const full = { ...snapshot, memory: { ...snapshot.memory, usedPercent: 95 } };
    expect(trayIconName(full)).toBe("trayTemplate");
  });

  it("is orange on warning and red on critical", () => {
    expect(trayIconName({ ...snapshot, pressure: "warning" })).toBe("trayWarning");
    expect(trayIconName({ ...snapshot, pressure: "critical" })).toBe("trayCritical");
  });
});

describe("trayTooltip", () => {
  it("spells out memory, cpu and swap for a hover", () => {
    const tip = trayTooltip(snapshot);
    expect(tip).toContain("22.5 GB");
    expect(tip).toContain("32.0 GB");
    expect(tip).toContain("18.4%");
    expect(tip).toContain("Swap 1.0 GB");
  });
});

// The glossary shown by "What do these mean?".
describe("helpDialog", () => {
  it("has a title and explains every term the menu uses", () => {
    const { message, detail } = helpDialog();
    expect(message).toBe("What do these mean?");
    for (const term of ["Memory used", "Memory pressure", "Swap", "CPU", "Using most memory", "Icon colour"]) {
      expect(detail).toContain(term);
    }
  });

  it("says what to do, not just what things are", () => {
    const { detail } = helpDialog();
    expect(detail).toContain("Closing a heavy app will help");
    expect(detail).toContain("Click one to quit it");
    expect(detail).toContain("Orange means warning");
  });
});
