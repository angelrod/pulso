/** Per-core tick counters as `os.cpus()` reports them. */
export interface CpuTimes {
  user: number;
  nice: number;
  sys: number;
  irq: number;
  idle: number;
}

/** The shape `os.cpus()` returns: one entry per core. */
export type CpuSample = ReadonlyArray<{ times: CpuTimes }>;

/** A single process, as parsed from `ps -axo pid,pcpu,rss,comm` output. */
export interface Process {
  pid: number;
  cpu: number;
  rssBytes: number;
  command: string;
}

/** `ps` reports RSS in kilobytes; this turns it into bytes. */
const KB = 1024;

/** The page size, read from the vm_stat header rather than assumed. */
const PAGE_SIZE = /\(page size of (\d+) bytes\)/;

// pid, cpu, rss are numeric fields; COMM is everything after RSS, spaces included.
const ROW = /^(\d+)\s+([\d.]+)\s+(\d+)\s+(.*)$/;

/** Skips blank lines and header without throwing; keeps the command verbatim, spaces included. */
export function parseProcesses(output: string): Process[] {
  const procs: Process[] = [];
  for (const line of output.split("\n")) {
    const m = ROW.exec(line.trim());
    if (!m) continue;
    const [, pid, cpu, rss] = m;
    const command = m[4] ?? "";
    procs.push({ pid: Number(pid), cpu: Number(cpu), rssBytes: Number(rss) * KB, command });
  }
  return procs;
}

/** A snapshot of virtual memory, in bytes, derived from `vm_stat` output. */
export interface Memory {
  totalBytes: number;
  usedBytes: number;
  freeBytes: number;
  wiredBytes: number;
  compressedBytes: number;
  usedPercent: number;
}

/** `vm_stat` reports every quantity in pages; this turns a page count into bytes. */
function pageBytes(pages: number, pageSize: number): number {
  return pages * pageSize;
}

/** Returns the integer or `null` if absent; strips the fixture's trailing `.` before parsing. */
function line(output: string, label: string): number | null {
  // Escape regex metacharacters in the label.
  const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  for (const l of output.split("\n")) {
    const m = new RegExp(`^${escaped}:\\s*(\\d+)\\.?$`).exec(l.trim());
    if (m) return Number(m[1]);
  }
  return null;
}

/** Used is app + wired + compressed, as Activity Monitor; total - free reads ~99%. */
export function parseMemory(output: string, totalBytes: number): Memory {
  if (!/Virtual Memory Statistics/i.test(output)) {
    throw new Error("not vm_stat output");
  }

  const sizeMatch = PAGE_SIZE.exec(output);
  if (!sizeMatch) {
    throw new Error("vm_stat output missing the page size");
  }
  const pageSize = Number(sizeMatch[1]);

  const free = line(output, "Pages free");
  const wired = line(output, "Pages wired down");
  const compressed = line(output, "Pages occupied by compressor");
  const anonymous = line(output, "Anonymous pages");
  const purgeable = line(output, "Pages purgeable");

  if (free === null || wired === null || compressed === null) {
    throw new Error("vm_stat output missing a required line");
  }
  if (anonymous === null || purgeable === null) {
    throw new Error("vm_stat output missing anonymous or purgeable pages");
  }

  const freeBytes = pageBytes(free, pageSize);
  const wiredBytes = pageBytes(wired, pageSize);
  const compressedBytes = pageBytes(compressed, pageSize);
  const usedBytes =
    pageBytes(anonymous - purgeable, pageSize) + wiredBytes + compressedBytes;
  const usedPercent = usedBytes / totalBytes * 100;

  return { totalBytes, usedBytes, freeBytes, wiredBytes, compressedBytes, usedPercent };
}

const UNITS = ["B", "KB", "MB", "GB", "TB"];
const WHOLE = new Intl.NumberFormat("en-US", {
  maximumFractionDigits: 0,
  useGrouping: false,
});

/** Steps up a unit before rounding would otherwise display 1024.0. */
export function formatBytes(bytes: number): string {
  let unit = 0;
  let value = bytes;
  while (unit < UNITS.length - 1 && value >= 1024) {
    value /= 1024;
    unit += 1;
  }
  if (unit < UNITS.length - 1 && Number(value.toFixed(1)) >= 1024) {
    value /= 1024;
    unit += 1;
  }
  const text = unit === 0 ? WHOLE.format(value) : value.toFixed(1);
  return `${text} ${UNITS[unit]}`;
}

// A short name fits the menu's row width; the ellipsis counts toward the limit.
const NAME_MAX = 32;

function trimName(name: string): string {
  return name.length > NAME_MAX ? `${name.slice(0, NAME_MAX - 1)}…` : name;
}

/** Unpacks only a path (anything starting with `/`), keeping everything else verbatim. */
export function shortName(command: string): string {
  if (!command.startsWith("/")) return trimName(command);

  // For nested bundles the executable name differs from the last app; resolve via Contents/MacOS.
  const match = /.*\.app\/Contents\/MacOS\//.exec(command);
  let name: string;
  if (match) {
    const before = match[0].replace(/\.app\/Contents\/MacOS\//, "");
    name = before.slice(before.lastIndexOf("/") + 1);
  } else {
    name = command.split("/").pop() ?? "";
  }

  return trimName(name);
}

export interface AppGroup {
  name: string;              // the outermost bundle's folder name without ".app"
  bundlePath: string | null; // up to and including the outermost ".app", or null
  pids: number[];
  mainPid: number | null;
  rssBytes: number;          // sum over pids
  cpu: number;               // sum over pids
}

// The first .app path segment from the left names the app; the slice drops the trailing slash.
function bundlePathOf(command: string): string | null {
  if (!command.startsWith("/")) return null;
  const m = /[^/]*\.app\//.exec(command);
  if (!m) return null;
  return command.slice(0, m.index + m[0].length - 1);
}

// Strips the `.app` suffix, leaving the bundle's folder name.
function appName(bundlePath: string): string {
  return bundlePath.slice(bundlePath.lastIndexOf("/") + 1, -4);
}

// A main process runs directly in <bundle>/Contents/MacOS with nothing after it.
function isMain(command: string, bundlePath: string): boolean {
  const escaped = bundlePath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^${escaped}/Contents/MacOS/[^/]+$`).exec(command) !== null;
}

// Groups processes by app; each non-bundle process becomes its own row and never merges.
export function groupByApp(processes: Process[]): AppGroup[] {
  const groups: AppGroup[] = [];
  const byBundle = new Map<string, AppGroup>();

  for (const p of processes) {
    const bundlePath = bundlePathOf(p.command);
    if (bundlePath === null) {
      groups.push({ name: shortName(p.command), bundlePath: null, pids: [p.pid], mainPid: p.pid, rssBytes: p.rssBytes, cpu: p.cpu });
      continue;
    }

    let g = byBundle.get(bundlePath);
    if (!g) {
      g = { name: appName(bundlePath), bundlePath, pids: [], mainPid: null, rssBytes: 0, cpu: 0 };
      byBundle.set(bundlePath, g);
      groups.push(g);
    }
    g.pids.push(p.pid);
    g.rssBytes += p.rssBytes;
    g.cpu += p.cpu;
    if (g.mainPid === null && isMain(p.command, bundlePath)) g.mainPid = p.pid;
  }
  return groups;
}

/** Heaviest by either metric: sorts a copy so the caller's array is never mutated. */
export function topBy<T extends Process>(
  procs: T[],
  key: "cpu" | "rssBytes",
  count: number,
): T[] {
  return count <= 0 ? [] : [...procs].sort((a, b) => b[key] - a[key]).slice(0, count);
}

/** The two readings must come from the same machine: a mismatched core count is an error. */
export function cpuPercent(prev: CpuSample, next: CpuSample): number {
  if (prev.length !== next.length) {
    throw new Error(`cpu readings have different core counts: ${prev.length} and ${next.length}`);
  }

  let busy = 0;
  let total = 0;
  for (let i = 0; i < prev.length; i += 1) {
    const p = prev[i]!.times;
    const n = next[i]!.times;
    const prevTotal = busyTime(p) + p.idle;
    const nextTotal = busyTime(n) + n.idle;
    busy += busyTime(n) - busyTime(p);
    total += nextTotal - prevTotal;
  }

  if (total <= 0) return 0;
  return Math.min(100, Math.max(0, (busy / total) * 100));
}

/** The time a core spent doing something rather than idle. */
function busyTime(times: CpuTimes): number {
  return times.user + times.nice + times.sys + times.irq;
}

/** macOS maps memory pressure to a kernel code: 1 normal, 2 warning, 4 critical. */
export type Pressure = "normal" | "warning" | "critical";

/** A memory snapshot plus pressure and swap, from one `sysctl` call. */
export interface SystemInfo {
  totalBytes: number;
  pressure: Pressure;
  swapUsedBytes: number;
  swapTotalBytes: number;
}

// A level maps to a name; anything else is a failure the caller cannot recover from.
const PRESSURE: Record<string, Pressure> = { 1: "normal", 2: "warning", 4: "critical" };

/** Turns a swap figure into bytes by its own unit (M or G), reading the value by label. */
function swapBytes(label: string, swap: string): number | null {
  const m = new RegExp(`${label}\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)\\s*([MG])`).exec(swap);
  if (!m) return null;
  const bytesPerUnit = m[2] === "G" ? 1024 ** 3 : 1024 ** 2;
  return Math.round(Number(m[1]) * bytesPerUnit);
}

/** Reads memsize, pressure and swapusage off three lines; every failure names sysctl. */
export function parseSysctl(output: string): SystemInfo {
  const lines = output.split("\n").map((line) => line.trim()).filter(Boolean);
  if (lines.length < 3) {
    throw new Error("sysctl needs three lines: hw.memsize, pressure and vm.swapusage");
  }

  if (!/^\d+$/.test(lines[0]!)) {
    throw new Error("sysctl hw.memsize line is missing or not a byte count");
  }

  const pressure = PRESSURE[lines[1]!];
  if (!pressure) {
    throw new Error(`sysctl pressure level ${lines[1]} is not 1, 2 or 4`);
  }

  const swapTotalBytes = swapBytes("total", lines[2]!);
  const swapUsedBytes = swapBytes("used", lines[2]!);
  // null means unreadable; a genuine 0 is a valid reading, so keep it.
  if (swapTotalBytes === null || swapUsedBytes === null) {
    throw new Error("sysctl vm.swapusage line is missing or unreadable");
  }

  return { totalBytes: Number(lines[0]), pressure, swapUsedBytes, swapTotalBytes };
}
