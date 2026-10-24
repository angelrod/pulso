/**
 * Tests for grouping processes by app.
 *
 * Listing single processes misled: Chrome used 6.5 GB across 94 processes but showed
 * as one 580 MB row. Every process inside an `.app` bundle is summed under the
 * outermost bundle it lives in. Processes outside any bundle stay one row each: two
 * `node` processes must never be merged, or quitting the row would end both.
 */
import { describe, expect, it } from "vitest";

import { groupByApp, type Process } from "./metrics";

const chrome = "/Applications/Google Chrome.app";
const proc = (pid: number, command: string, rssBytes: number, cpu = 0): Process => ({
  pid,
  cpu,
  rssBytes,
  command,
});

const processes: Process[] = [
  proc(760, `${chrome}/Contents/MacOS/Google Chrome`, 400, 1.5),
  proc(761, `${chrome}/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)`, 300, 2),
  proc(762, `${chrome}/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)`, 200, 0.5),
  proc(900, "/Applications/Slack.app/Contents/MacOS/Slack", 100),
  proc(901, "/Applications/Slack.app/Contents/Frameworks/Slack Helper (Renderer).app/Contents/MacOS/Slack Helper (Renderer)", 250),
  proc(50, "/usr/local/bin/node", 280, 3),
  proc(51, "/usr/local/bin/node", 270, 4),
  proc(1, "/sbin/launchd", 18),
  proc(70, "-zsh", 5),
];

const byName = (name: string) => groupByApp(processes).filter((g) => g.name === name);

describe("groupByApp: apps", () => {
  it("sums every process of an app under the outermost bundle's name", () => {
    const [g] = byName("Google Chrome");
    expect(g).toBeDefined();
    expect(g!.rssBytes).toBe(900);
    expect(g!.cpu).toBeCloseTo(4, 10);
    expect(g!.pids.slice().sort((a, b) => a - b)).toEqual([760, 761, 762]);
    expect(g!.bundlePath).toBe(chrome);
  });

  it("never lists a helper bundle as its own app", () => {
    const names = groupByApp(processes).map((g) => g.name);
    expect(names.some((n) => n.includes("Helper"))).toBe(false);
    expect(byName("Slack")[0]!.rssBytes).toBe(350);
  });

  it("knows the app's main process: the executable directly in its Contents/MacOS", () => {
    expect(byName("Google Chrome")[0]!.mainPid).toBe(760);
    expect(byName("Slack")[0]!.mainPid).toBe(900);
  });

  it("has no main process when only helpers are running", () => {
    const helpersOnly = groupByApp([processes[1]!, processes[2]!]);
    expect(helpersOnly).toHaveLength(1);
    expect(helpersOnly[0]!.mainPid).toBeNull();
  });
});

describe("groupByApp: everything else", () => {
  it("keeps each process outside a bundle as its own row, never merged by name", () => {
    const node = byName("node");
    expect(node).toHaveLength(2);
    expect(node.map((g) => g.pids)).toEqual([[50], [51]]);
    for (const g of node) {
      expect(g.bundlePath).toBeNull();
      expect(g.mainPid).toBe(g.pids[0]);
    }
  });

  it("carries each one's own memory and cpu", () => {
    const [first] = byName("node");
    expect(first!.rssBytes).toBe(280);
    expect(first!.cpu).toBe(3);
    expect(byName("launchd")[0]!.rssBytes).toBe(18);
  });

  it("names them as shortName does, including commands that are not paths", () => {
    expect(byName("launchd")).toHaveLength(1);
    expect(byName("-zsh")).toHaveLength(1);
  });
});

describe("groupByApp: shape", () => {
  it("accounts for every process exactly once", () => {
    const pids = groupByApp(processes).flatMap((g) => g.pids);
    expect(pids.slice().sort((a, b) => a - b)).toEqual(processes.map((p) => p.pid).sort((a, b) => a - b));
  });

  it("does not change the list it was given", () => {
    const before = JSON.stringify(processes);
    groupByApp(processes);
    expect(JSON.stringify(processes)).toBe(before);
  });

  it("returns nothing for nothing", () => {
    expect(groupByApp([])).toEqual([]);
  });
});
