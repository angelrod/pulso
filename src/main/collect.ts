import { execFile } from "node:child_process";
import { cpus as osCpus } from "node:os";

import type { Snapshot } from "./tray";
import {
  cpuPercent,
  parseMemory,
  parseProcesses,
  parseSysctl,
  type CpuSample,
} from "./metrics";

/** Running a command and resolving with its standard output, for injection in tests. */
export type Run = (command: string, args: string[]) => Promise<string>;

/** Reads a `os.cpus()` sample, injected in tests so CPU counters need no real reading. */
export type CpuReader = () => CpuSample;

/** The default runner: `execFile`, never a shell, under the C locale. */
export function runCommand(command: string, args: string[]): Promise<string> {
  // A shell would expand the arguments; execFile passes them straight through.
  const env = { ...process.env, LC_ALL: "C" };
  return new Promise((resolve, reject) => {
    execFile(command, args, { env }, (error, stdout) =>
      error ? reject(error) : resolve(stdout),
    );
  });
}

const COMMANDS = {
  ps: "/bin/ps",
  vmStat: "/usr/bin/vm_stat",
  sysctl: "/usr/sbin/sysctl",
};

/** The sysctl flags and oids, one line of output expected per oid. */
const SYSCTL_ARGS = ["-n", "hw.memsize", "kern.memorystatus_vm_pressure_level", "vm.swapusage"];

/** What a returned collector function needs, injected in tests. */
export type CollectorDeps = {
  run?: Run;
  cpus?: CpuReader;
  now?: () => Date;
};

/** The first call measures from this reading, which is taken here when the collector is created. */
export function createCollector(
  deps: CollectorDeps = {},
): () => Promise<Snapshot> {
  const { run = runCommand, cpus = () => osCpus(), now = () => new Date() } = deps;
  let prev: CpuSample = cpus();

  return () =>
    Promise.all([
      run(COMMANDS.ps, ["-axo", "pid,pcpu,rss,comm"]),
      run(COMMANDS.vmStat, []),
      run(COMMANDS.sysctl, SYSCTL_ARGS),
    ]).then(([psOutput, vmStatOutput, sysctlOutput]) => {
      const info = parseSysctl(sysctlOutput);
      const current = cpus();
      const processes = parseProcesses(psOutput);
      const memory = parseMemory(vmStatOutput, info.totalBytes);
      const cpu = cpuPercent(prev, current);
      prev = current;
      return {
        takenAt: now(),
        memory,
        cpuPercent: cpu,
        processes,
        pressure: info.pressure,
        swapUsedBytes: info.swapUsedBytes,
      };
    });
}
