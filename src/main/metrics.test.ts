/**
 * Tests for the metrics layer: pure functions over real command output.
 *
 * The fixtures in test/fixtures/ are real `ps`, `vm_stat` and `sysctl` output captured
 * on an Apple Silicon Mac.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import {
  cpuPercent,
  formatBytes,
  parseMemory,
  parseProcesses,
  parseSysctl,
  shortName,
  topBy,
} from "./metrics";

const fixture = (name: string): string =>
  readFileSync(join(__dirname, "..", "..", "test", "fixtures", name), "utf8");

describe("parseProcesses", () => {
  const output = fixture("ps.txt");

  it("skips the header and returns one process per line", () => {
    const procs = parseProcesses(output);
    expect(procs.length).toBe(24);
    expect(procs.some((p) => p.command.includes("PID"))).toBe(false);
  });

  it("reads pid, cpu, memory and command from the first row", () => {
    const [first] = parseProcesses(output);
    expect(first).toEqual({
      pid: 1,
      cpu: 0.1,
      rssBytes: 18528 * 1024,
      command: "/sbin/launchd",
    });
  });

  it("keeps the command verbatim, full path included", () => {
    const procs = parseProcesses(output);
    expect(procs[0]!.command).toBe("/sbin/launchd");
  });

  it("survives blank lines and a row with no command", () => {
    expect(parseProcesses("")).toEqual([]);
    expect(parseProcesses("  PID  %CPU    RSS COMM\n")).toEqual([]);
    expect(() => parseProcesses("  PID %CPU RSS COMM\n  7 1.0 100\n")).not.toThrow();
  });
});

describe("parseMemory", () => {
  const vmStat = fixture("vm_stat.txt");
  const totalBytes = 34359738368; // from sysctl.txt, a 32 GB Mac

  it("derives free bytes from the reported page size", () => {
    const mem = parseMemory(vmStat, totalBytes);
    // 4208 free pages x 16384 bytes
    expect(mem.freeBytes).toBe(4208 * 16384);
  });

  // Not `total - free`: that reads ~99% on a live Mac, because macOS fills free memory
  // with reclaimable file cache. This is Activity Monitor's "Memory Used": app
  // (anonymous - purgeable) + wired + compressed (pages occupied by compressor).
  it("reports used bytes as app + wired + compressed, like Activity Monitor", () => {
    const mem = parseMemory(vmStat, totalBytes);
    // (682900 anonymous - 18 purgeable) + 293178 wired + 812963 occupied by compressor
    expect(mem.usedBytes).toBe((682900 - 18 + 293178 + 812963) * 16384);
    expect(mem.usedBytes).not.toBe(totalBytes - mem.freeBytes);
  });

  it("reports a used percentage between 0 and 100", () => {
    const mem = parseMemory(vmStat, totalBytes);
    expect(mem.usedPercent).toBeGreaterThan(0);
    expect(mem.usedPercent).toBeLessThanOrEqual(100);
    expect(mem.usedPercent).toBeCloseTo((mem.usedBytes / totalBytes) * 100, 5);
  });

  it("reads wired and compressed pages", () => {
    const mem = parseMemory(vmStat, totalBytes);
    expect(mem.wiredBytes).toBeGreaterThan(0);
    expect(mem.compressedBytes).toBeGreaterThanOrEqual(0);
  });

  it("fails loudly when the text is not vm_stat output", () => {
    expect(() => parseMemory("something else", totalBytes)).toThrow(/vm_stat/i);
  });
});

describe("shortName", () => {
  it("keeps the last segment of the path", () => {
    expect(shortName("/usr/libexec/mediaanalysisd")).toBe("mediaanalysisd");
    expect(shortName("/sbin/launchd")).toBe("launchd");
  });

  it("unwraps macOS bundles to the app name", () => {
    expect(shortName("/Applications/Chrome.app/Contents/MacOS/Chrome")).toBe("Chrome");
  });

  it("leaves an already short command alone", () => {
    expect(shortName("node")).toBe("node");
    expect(shortName("")).toBe("");
  });

  it("truncates very long names so they fit a menu row", () => {
    const long = "/usr/bin/" + "a".repeat(80);
    expect(shortName(long).length).toBeLessThanOrEqual(32);
  });
});

describe("formatBytes", () => {
  it("picks the largest unit that keeps the number readable", () => {
    expect(formatBytes(0)).toBe("0 B");
    expect(formatBytes(512)).toBe("512 B");
    expect(formatBytes(1024)).toBe("1.0 KB");
    expect(formatBytes(1536)).toBe("1.5 KB");
    expect(formatBytes(1024 ** 2)).toBe("1.0 MB");
    expect(formatBytes(1024 ** 3 * 2.5)).toBe("2.5 GB");
  });

  it("uses a period as the decimal separator (the UI is English)", () => {
    expect(formatBytes(1024 ** 3 * 1.5)).toBe("1.5 GB");
    expect(formatBytes(1024 ** 3 * 1.5)).not.toContain(",");
  });
});

// Memory pressure and swap say more than percent used: Activity Monitor colours
// pressure, and a busy Mac can run many GB into swap. One call,
// `sysctl -n hw.memsize kern.memorystatus_vm_pressure_level vm.swapusage`, one per line.
describe("parseSysctl", () => {
  const output = fixture("sysctl.txt");

  it("reads total memory from the first line", () => {
    expect(parseSysctl(output).totalBytes).toBe(34359738368);
  });

  it("maps the kernel pressure level to normal, warning or critical", () => {
    const at = (level: string) =>
      parseSysctl(`34359738368\n${level}\ntotal = 0.00M  used = 0.00M  free = 0.00M\n`).pressure;
    expect(at("1")).toBe("normal");
    expect(at("2")).toBe("warning");
    expect(at("4")).toBe("critical");
    expect(parseSysctl(output).pressure).toBe("warning");
  });

  it("reads swap used and total in bytes, from megabytes", () => {
    const sys = parseSysctl(output);
    expect(sys.swapUsedBytes).toBe(Math.round(20234.12 * 1024 ** 2));
    expect(sys.swapTotalBytes).toBe(Math.round(21504 * 1024 ** 2));
  });

  it("understands swap reported in gigabytes too", () => {
    const sys = parseSysctl("34359738368\n1\ntotal = 2.00G  used = 1.50G  free = 0.50G  (encrypted)\n");
    expect(sys.swapUsedBytes).toBe(Math.round(1.5 * 1024 ** 3));
    expect(sys.swapTotalBytes).toBe(2 * 1024 ** 3);
  });

  it("fails loudly, naming sysctl, on anything it cannot read", () => {
    expect(() => parseSysctl("")).toThrow(/\bsysctl\b/i);
    expect(() => parseSysctl("hw.memsize: unknown oid\n")).toThrow(/\bsysctl\b/i);
    expect(() => parseSysctl("34359738368\n3\ntotal = 0.00M  used = 0.00M  free = 0.00M\n")).toThrow(/\bsysctl\b/i);
    expect(() => parseSysctl("34359738368\n1\nno swap here\n")).toThrow(/\bsysctl\b/i);
  });
});

// Summing ps %CPU reads far below `top` (7.6 vs 21 in one measurement):
// ps gives a decaying per-process average and leaves out kernel time. CPU is now the
// change in each core's tick counters between two readings, the shape of os.cpus().
describe("cpuPercent", () => {
  const core = (user: number, nice: number, sys: number, irq: number, idle: number) => ({
    times: { user, nice, sys, irq, idle },
  });

  it("is busy time over total time, across every core, between two readings", () => {
    const prev = [core(100, 0, 50, 0, 1000), core(200, 0, 0, 0, 2000)];
    // Core 1: +20 user +10 sys +70 idle. Core 2: +10 user +90 idle. Busy 40 of 200.
    const next = [core(120, 0, 60, 0, 1070), core(210, 0, 0, 0, 2090)];
    expect(cpuPercent(prev, next)).toBeCloseTo(20, 10);
  });

  it("counts nice and irq time as busy", () => {
    const prev = [core(0, 0, 0, 0, 0)];
    const next = [core(0, 25, 0, 25, 50)];
    expect(cpuPercent(prev, next)).toBeCloseTo(50, 10);
  });

  it("reads 0 when no time has passed, rather than dividing by zero", () => {
    const same = [core(10, 0, 10, 0, 10)];
    expect(cpuPercent(same, same)).toBe(0);
  });

  it("stays between 0 and 100 even if a counter goes backwards", () => {
    const prev = [core(500, 0, 0, 0, 100)];
    const next = [core(100, 0, 0, 0, 200)];
    const pct = cpuPercent(prev, next);
    expect(pct).toBeGreaterThanOrEqual(0);
    expect(pct).toBeLessThanOrEqual(100);
  });

  it("refuses readings with different core counts", () => {
    expect(() => cpuPercent([core(0, 0, 0, 0, 0)], [])).toThrow(/core/i);
  });
});

describe("topBy", () => {
  const procs = [
    { pid: 1, cpu: 0.5, rssBytes: 300, command: "a" },
    { pid: 2, cpu: 9.0, rssBytes: 100, command: "b" },
    { pid: 3, cpu: 4.0, rssBytes: 900, command: "c" },
  ];

  it("sorts by cpu, highest first", () => {
    expect(topBy(procs, "cpu", 2).map((p) => p.pid)).toEqual([2, 3]);
  });

  it("sorts by memory, highest first", () => {
    expect(topBy(procs, "rssBytes", 2).map((p) => p.pid)).toEqual([3, 1]);
  });

  it("returns at most the requested count and never throws on overflow", () => {
    expect(topBy(procs, "cpu", 10).length).toBe(3);
    expect(topBy([], "cpu", 3)).toEqual([]);
  });

  it("does not mutate the array it was given", () => {
    const copy = [...procs];
    topBy(procs, "cpu", 2);
    expect(procs).toEqual(copy);
  });
});
