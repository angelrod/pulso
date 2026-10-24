/**
 * Tests for quitting an app the way ⌘Q does.
 *
 * Signalling a process gives the app no chance to ask about unsaved work. Asking the
 * app to quit through Apple Events does, and Chrome then restores its tabs. The app is
 * addressed by its bundle identifier, read from its Info.plist, never by a name typed
 * into a script. The runner is injected, as in `collect.ts`.
 */
import { describe, expect, it } from "vitest";

import type { Run } from "./collect";
import { quitAppBundle } from "./quit";

function fakeRun(answers: Record<string, string | Error>) {
  const calls: Array<[string, string[]]> = [];
  const run: Run = async (command, args) => {
    calls.push([command, args]);
    const answer = answers[command];
    if (answer instanceof Error) throw answer;
    if (answer === undefined) throw new Error(`unexpected command ${command}`);
    return answer;
  };
  return { run, calls };
}

const chrome = "/Applications/Google Chrome.app";

describe("quitAppBundle", () => {
  it("reads the bundle id from Info.plist, then asks that app to quit", async () => {
    const { run, calls } = fakeRun({
      "/usr/libexec/PlistBuddy": "com.google.Chrome\n",
      "/usr/bin/osascript": "",
    });
    await quitAppBundle(chrome, run);
    expect(calls).toEqual([
      ["/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleIdentifier", `${chrome}/Contents/Info.plist`]],
      ["/usr/bin/osascript", ["-e", 'tell application id "com.google.Chrome" to quit']],
    ]);
  });

  it("refuses a bundle id that could break out of the script", async () => {
    const { run, calls } = fakeRun({
      "/usr/libexec/PlistBuddy": 'evil" to do shell script "rm -rf ~\n',
      "/usr/bin/osascript": "",
    });
    await expect(quitAppBundle(chrome, run)).rejects.toThrow(/bundle id/i);
    expect(calls.some(([c]) => c === "/usr/bin/osascript")).toBe(false);
  });

  it("refuses a path that is not an absolute .app bundle, before running anything", async () => {
    for (const bad of ["Google Chrome.app", "/Applications/Google Chrome", "/bin/ls", ""]) {
      const { run, calls } = fakeRun({});
      await expect(quitAppBundle(bad, run)).rejects.toThrow(/bundle/i);
      expect(calls).toEqual([]);
    }
  });

  it("says plainly when macOS has not allowed Pulso to control the app", async () => {
    const denied = new Error("execution error: Not authorized to send Apple events to Google Chrome. (-1743)");
    const { run } = fakeRun({ "/usr/libexec/PlistBuddy": "com.google.Chrome\n", "/usr/bin/osascript": denied });
    await expect(quitAppBundle(chrome, run)).rejects.toThrow(/Privacy & Security.*Automation/);
  });

  it("passes any other failure through", async () => {
    const { run } = fakeRun({
      "/usr/libexec/PlistBuddy": new Error("Print: Entry, \":CFBundleIdentifier\", Does Not Exist"),
    });
    await expect(quitAppBundle(chrome, run)).rejects.toThrow(/Does Not Exist/);
  });
});
