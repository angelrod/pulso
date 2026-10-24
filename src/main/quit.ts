/** Asks an app to quit via ⌘Q by bundle id, runner injected as in collect.ts. */
import type { Run } from "./collect";
import { runCommand } from "./collect";

// A bundle id must stay one token; a space or quote could break the AppleScript apart.
const BUNDLE_ID = /^[A-Za-z0-9][A-Za-z0-9.-]*$/;

/** PlistBuddy reads the bundle id; osascript asks the app to quit. */
const TOOLS = {
  plist: "/usr/libexec/PlistBuddy",
  script: "/usr/bin/osascript",
};

/** The AppleScript that asks the app identified by id to quit; id is already validated. */
function quitScript(id: string): string {
  return `tell application id "${id}" to quit`;
}

/** Asks the app at bundlePath to quit the way ⌘Q does, via its bundle identifier. */
export async function quitAppBundle(bundlePath: string, run: Run = runCommand): Promise<void> {
  if (!bundlePath.startsWith("/") || !bundlePath.endsWith(".app")) {
    throw new Error(`Not a bundle path: expected an absolute .app, got ${JSON.stringify(bundlePath)}.`);
  }

  const raw = (await run(TOOLS.plist, ["-c", "Print :CFBundleIdentifier", `${bundlePath}/Contents/Info.plist`])).trim();
  if (!BUNDLE_ID.test(raw)) {
    throw new Error(`Not a bundle id: ${JSON.stringify(raw)} could break out of the script.`);
  }

  try {
    await run(TOOLS.script, ["-e", quitScript(raw)]);
  } catch (err) {
    // A denial names both; any other failure passes through unchanged.
    if (/(-1743|Not authorized)/i.test((err as Error).message)) {
      throw new Error(`Pulso is not allowed to control ${appBundleName(bundlePath)}. Allow it in System Settings > Privacy & Security > Automation.`);
    }
    throw err;
  }
}

/** The bundle's folder name without ".app", for the privacy message the caller cannot see. */
function appBundleName(bundlePath: string): string {
  return bundlePath.slice(bundlePath.lastIndexOf("/") + 1, -4);
}
