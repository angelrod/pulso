import type { Snapshot } from "./tray";
import { formatBytes, groupByApp, type AppGroup, type Pressure } from "./metrics";
import type { AvailableUpdate } from "./update";

/** A tone the panel colours by: the snapshot's pressure alone, never the percent used. */
export type Tone = "normal" | "warning" | "critical";

/** The plain data a panel renders: the memory header, tone, tiles, processes and footer. */
export interface PanelView {
  memory: { percent: string; detail: string; help: string; barPercent: number };
  tone: Tone;
  advice: string | null;
  tiles: Array<{ label: string; value: string; help: string }>;
  processes: Array<{ pid: number; name: string; memory: string; cpu: string; share: number }>;
  updated: string;
  update: { text: string } | null;
}

/** Advice shown only when pressure is not normal: the two non-normal levels each map to a line. */
const adviceByPressure: Record<Exclude<Pressure, "normal">, string> = {
  warning: "Your Mac is starting to slow down. Quitting a heavy app below will help.",
  critical: "Your Mac is short of memory. Quit an app below now.",
};

/** Advice by pressure alone: none when normal, otherwise a line near the top of the panel. */
function adviceFor(pressure: Pressure): string | null {
  return pressure === "normal" ? null : adviceByPressure[pressure];
}

/** "HH:mm:ss" in local 24-hour time with zero-padded minutes and seconds, matching the menu. */
function formatTime(date: Date): string {
  const parts = [date.getHours(), date.getMinutes(), date.getSeconds()];
  return parts.map((p) => String(p).padStart(2, "0")).join(":");
}

/** Builds the panel's plain data from a snapshot, leaving the snapshot it was given untouched. */
export function buildPanelView(
  snapshot: Snapshot,
  refreshSeconds: number,
  update: AvailableUpdate | null = null,
): PanelView {
  const memory = {
    percent: `${Math.round(snapshot.memory.usedPercent)}%`,
    detail: `${formatBytes(snapshot.memory.usedBytes)} of ${formatBytes(snapshot.memory.totalBytes)}`,
    help: "How much memory is in use. A high number is normal on a Mac.",
    barPercent: Math.min(100, Math.max(0, snapshot.memory.usedPercent)),
  };

  const pressure = snapshot.pressure;
  const advice = adviceFor(pressure);

  const groups = groupByApp(snapshot.processes)
    .sort((a, b) => b.rssBytes - a.rssBytes)
    .slice(0, 5);
  const [first] = groups;
  const heaviest = first?.rssBytes ?? 0;
  const processes = groups.map((group) => ({
    pid: group.mainPid ?? group.pids[0]!,
    name: group.name,
    memory: formatBytes(group.rssBytes),
    cpu: `${group.cpu.toFixed(1)}%`,
    share: heaviest === 0 ? 0 : group.rssBytes / heaviest,
  }));

  const tiles = [
    {
      label: "Pressure",
      value: pressure.charAt(0).toUpperCase() + pressure.slice(1),
      help: "How hard your Mac is working to find free memory. The one to watch.",
    },
    {
      label: "Swap",
      value: formatBytes(snapshot.swapUsedBytes),
      help: "Memory moved to the disk when it ran out of room. Many GB feels slower.",
    },
    { label: "CPU", value: `${Math.round(snapshot.cpuPercent)}%`, help: "How busy the processor is right now." },
  ];

  return {
    memory,
    tone: pressure,
    advice,
    tiles,
    processes,
    updated: `Updated ${formatTime(snapshot.takenAt)} · refreshes every ${refreshSeconds} s`,
    update: update ? { text: `Pulso ${update.version} is available` } : null,
  };
}

/** The wording a quit confirmation shows, chosen by whether the group is an app. */
export function quitPrompt(group: AppGroup): { message: string; detail: string; button: string } {
  if (group.bundlePath) {
    const count = group.pids.length;
    return {
      message: `Quit ${group.name}?`,
      detail: `This closes all its windows (${count} ${count === 1 ? "process" : "processes"}, ${formatBytes(group.rssBytes)}).`,
      button: "Quit App",
    };
  }
  return {
    message: `Quit "${group.name}"?`,
    detail: `PID ${group.pids[0]} · using ${formatBytes(group.rssBytes)}. Anything unsaved in it will be lost.`,
    button: "Quit Process",
  };
}
