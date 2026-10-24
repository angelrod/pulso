/**
 * Tests for the collection layer.
 *
 * `collect.ts` runs the system commands and hands their output to the parsers in
 * `metrics.ts`. The command runner, the CPU counters and the clock are injected, so
 * these tests feed it the real captures in test/fixtures/ instead of touching the
 * machine. Only `runCommand`, the default runner, is exercised for real, with harmless
 * commands.
 *
 * CPU is the change in os.cpus() counters between readings (summing ps %CPU reads far
 * too low), so the collector remembers the last reading.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { createCollector, runCommand, type CpuReader, type Run } from "./collect";

const fixture = (name: string): string =>
  readFileSync(join(__dirname, "..", "..", "test", "fixtures", name), "utf8");

const outputs: Record<string, string> = {
  ps: fixture("ps.txt"),
  vm_stat: fixture("vm_stat.txt"),
  // `sysctl -n hw.memsize kern.memorystatus_vm_pressure_level vm.swapusage`.
  sysctl: fixture("sysctl.txt"),
};

/** A fake runner answering from fixtures and recording what it was asked to run. */
function fakeRun(overrides: Record<string, string> = {}) {
  const calls: Array<[string, string[]]> = [];
  const run: Run = async (command, args) => {
    calls.push([command, args]);
    const name = command.split("/").pop()!;
    const out = overrides[name] ?? outputs[name];
    if (out === undefined) throw new Error(`unexpected command ${command}`);
    return out;
  };
  return { run, calls };
}

/** One core whose busy and idle tick counters are given; nice and irq stay at zero. */
const core = (busy: number, idle: number) => ({
  times: { user: busy, nice: 0, sys: 0, irq: 0, idle },
});

/** A fake os.cpus() that returns the given readings in order, one per call. */
function fakeCpus(...readings: Array<ReturnType<typeof core>[]>) {
  let i = 0;
  const cpus: CpuReader = () => {
    const r = readings[Math.min(i, readings.length - 1)]!;
    i += 1;
    return r;
  };
  return { cpus, count: () => i };
}

const at = new Date(2026, 9, 23, 15, 30, 0);

describe("createCollector", () => {
  it("runs exactly ps, vm_stat and sysctl, by absolute path, with the arguments the parsers expect", async () => {
    const { run, calls } = fakeRun();
    await createCollector({ run, cpus: fakeCpus([core(0, 0)]).cpus, now: () => at })();
    const byName = Object.fromEntries(calls.map(([c, a]) => [c.split("/").pop(), a]));
    expect(Object.keys(byName).sort()).toEqual(["ps", "sysctl", "vm_stat"]);
    expect(calls.every(([c]) => c.startsWith("/"))).toBe(true);
    expect(byName.ps).toEqual(["-axo", "pid,pcpu,rss,comm"]);
    expect(byName.vm_stat).toEqual([]);
    expect(byName.sysctl).toEqual([
      "-n",
      "hw.memsize",
      "kern.memorystatus_vm_pressure_level",
      "vm.swapusage",
    ]);
  });

  it("builds the snapshot the menu consumes from the command output", async () => {
    const { run } = fakeRun();
    const snap = await createCollector({ run, cpus: fakeCpus([core(0, 0)]).cpus, now: () => at })();
    expect(snap.takenAt).toBe(at);
    expect(snap.processes.length).toBe(24);
    expect(snap.memory.totalBytes).toBe(34359738368);
    expect(snap.memory.freeBytes).toBe(4208 * 16384);
  });

  it("carries memory pressure and swap from sysctl into the snapshot", async () => {
    const { run } = fakeRun();
    const snap = await createCollector({ run, cpus: fakeCpus([core(0, 0)]).cpus, now: () => at })();
    expect(snap.pressure).toBe("warning");
    expect(snap.swapUsedBytes).toBe(Math.round(20234.12 * 1024 ** 2));
  });

  it("measures the first reading's cpu from when the collector was created", async () => {
    const { run } = fakeRun();
    const { cpus, count } = fakeCpus([core(0, 0)], [core(30, 70)]);
    const collect = createCollector({ run, cpus, now: () => at });
    expect(count()).toBe(1);
    const snap = await collect();
    expect(snap.cpuPercent).toBeCloseTo(30, 10);
  });

  it("measures each later reading from the previous one, not from the start", async () => {
    const { run } = fakeRun();
    const { cpus } = fakeCpus([core(0, 0)], [core(30, 70)], [core(40, 160)]);
    const collect = createCollector({ run, cpus, now: () => at });
    await collect();
    const second = await collect();
    // Since the previous reading: +10 busy, +90 idle.
    expect(second.cpuPercent).toBeCloseTo(10, 10);
  });

  it("fails loudly when sysctl does not answer with a number", async () => {
    const { run } = fakeRun({ sysctl: "hw.memsize: unknown oid\n" });
    const collect = createCollector({ run, cpus: fakeCpus([core(0, 0)]).cpus, now: () => at });
    await expect(collect()).rejects.toThrow(/sysctl/i);
  });

  it("uses the current time when no clock is given", async () => {
    const { run } = fakeRun();
    const before = Date.now();
    const snap = await createCollector({ run, cpus: fakeCpus([core(0, 0)]).cpus })();
    expect(snap.takenAt.getTime()).toBeGreaterThanOrEqual(before);
    expect(snap.takenAt.getTime()).toBeLessThanOrEqual(Date.now());
  });
});

describe("runCommand", () => {
  it("resolves with the command's standard output", async () => {
    await expect(runCommand("/bin/echo", ["pulso"])).resolves.toBe("pulso\n");
  });

  it("runs under the C locale, so ps prints 0.8 and not 0,8", async () => {
    const out = await runCommand("/bin/sh", ["-c", 'printf %s "$LC_ALL"']);
    expect(out).toBe("C");
  });

  it("rejects when the command fails", async () => {
    await expect(runCommand("/usr/bin/false", [])).rejects.toThrow();
  });
});
