/**
 * Tests for the bridge between the panel (renderer) and the main process.
 *
 * Both sides import `bridge.ts`, so the channel names and the action shapes cannot
 * drift apart. Two pure functions carry the logic worth testing:
 * - `actionFrom` turns a clicked element's data attributes into an action;
 * - `parseAction` checks what arrives over IPC before the main process acts on it.
 *   The renderer is a web page: anything it sends is untrusted until parsed.
 */
import { describe, expect, it } from "vitest";

import { CHANNELS, actionFrom, parseAction } from "./bridge";

describe("CHANNELS", () => {
  it("names every channel under the pulso: prefix", () => {
    expect(CHANNELS).toEqual({ view: "pulso:view", act: "pulso:act", resize: "pulso:resize" });
  });
});

describe("actionFrom", () => {
  it("maps each panel button to its action", () => {
    expect(actionFrom({ action: "refresh" })).toEqual({ type: "refresh" });
    expect(actionFrom({ action: "activity-monitor" })).toEqual({ type: "activity-monitor" });
    expect(actionFrom({ action: "help" })).toEqual({ type: "help" });
    expect(actionFrom({ action: "about" })).toEqual({ type: "about" });
    expect(actionFrom({ action: "quit-app" })).toEqual({ type: "quit-app" });
    expect(actionFrom({ action: "close" })).toEqual({ type: "close" });
  });

  it("reads the pid of the row for quit-process", () => {
    expect(actionFrom({ action: "quit-process", pid: "4812" })).toEqual({ type: "quit-process", pid: 4812 });
  });

  it("ignores clicks that are not actions, or a quit-process with no valid pid", () => {
    expect(actionFrom({})).toBeNull();
    expect(actionFrom({ action: "launch-missiles" })).toBeNull();
    expect(actionFrom({ action: "quit-process" })).toBeNull();
    expect(actionFrom({ action: "quit-process", pid: "abc" })).toBeNull();
    expect(actionFrom({ action: "quit-process", pid: "12.5" })).toBeNull();
  });
});

describe("parseAction", () => {
  it("accepts every well-formed action", () => {
    for (const type of ["refresh", "activity-monitor", "help", "about", "quit-app", "close"]) {
      expect(parseAction({ type })).toEqual({ type });
    }
    expect(parseAction({ type: "quit-process", pid: 4812 })).toEqual({ type: "quit-process", pid: 4812 });
  });

  it("rejects anything else, without throwing", () => {
    const bad: unknown[] = [
      null,
      undefined,
      "refresh",
      42,
      {},
      { type: "rm -rf" },
      { type: "quit-process" },
      { type: "quit-process", pid: "4812" },
      { type: "quit-process", pid: 1.5 },
      { type: "quit-process", pid: -3 },
      { type: "quit-process", pid: Number.NaN },
    ];
    for (const raw of bad) expect(parseAction(raw)).toBeNull();
  });

  it("drops extra fields, so nothing unexpected reaches the main process", () => {
    expect(parseAction({ type: "refresh", extra: "x" })).toEqual({ type: "refresh" });
    expect(parseAction({ type: "quit-process", pid: 7, shell: "rm" })).toEqual({ type: "quit-process", pid: 7 });
  });
});

describe("download-update", () => {
  it("is an action, carrying no URL", () => {
    expect(actionFrom({ action: "download-update" })).toEqual({ type: "download-update" });
    expect(parseAction({ type: "download-update", url: "https://evil.example" })).toEqual({
      type: "download-update",
    });
  });
});
