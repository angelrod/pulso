import type { Memory, Pressure, Process } from "./metrics";
import { formatBytes } from "./metrics";

/** A full reading the menu consumes. */
export interface Snapshot {
  takenAt: Date;
  memory: Memory;
  cpuPercent: number;
  processes: Process[];
  pressure: Pressure;
  swapUsedBytes: number;
}

/** The bar title: "RAM N%"; pressure now colours the icon instead of adding a glyph. */
export function trayTitle(snapshot: Snapshot): string {
  return `RAM ${Math.round(snapshot.memory.usedPercent)}%`;
}

/** The icon name by pressure alone, matching resources/: percent used plays no part. */
export function trayIconName(snapshot: Snapshot): "trayTemplate" | "trayWarning" | "trayCritical" {
  return snapshot.pressure === "normal"
    ? "trayTemplate"
    : snapshot.pressure === "warning"
      ? "trayWarning"
      : "trayCritical";
}

/** The hover line: memory, cpu and swap spelled out for a read at a glance. */
export function trayTooltip(snapshot: Snapshot): string {
  const mem = formatBytes(snapshot.memory.usedBytes);
  const total = formatBytes(snapshot.memory.totalBytes);
  const swap = formatBytes(snapshot.swapUsedBytes);
  return `Memory ${mem} of ${total} · CPU ${snapshot.cpuPercent.toFixed(1)}% · Swap ${swap}`;
}

/** The glossary shown by "What do these mean?"; the text lives here, index.ts only shows it. */
export function helpDialog(): { message: string; detail: string } {
  const detail = [
    "Memory used: How much of your Mac's memory is in use right now. A high number is normal: macOS keeps memory busy on purpose so apps open faster.",
    "",
    "Memory pressure: How hard your Mac is working to find free memory. This is the one to watch.",
    "• Normal: all good.",
    "• Warning: your Mac is starting to slow down. Closing a heavy app will help.",
    "• Critical: close an app now.",
    "",
    "Swap: Memory your Mac has moved to the disk because it ran out of room. A little is fine. Many GB means your Mac is short of memory, and things will feel slower.",
    "",
    "CPU: How busy the processor is right now.",
    "",
    "Using most memory: The apps taking the most memory. Click one to quit it.",
    "",
    "Icon colour: Plain means normal. Orange means warning. Red means critical.",
  ].join("\n");
  return { message: "What do these mean?", detail };
}
