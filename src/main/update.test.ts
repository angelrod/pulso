/**
 * Tests for the update check.
 *
 * Pulso is not signed with a Developer ID yet, so macOS will not let it update itself.
 * Instead, once a day it asks GitHub for the latest release and, if it is newer, the
 * panel offers a link to download it. Only a link to this repository's releases is
 * ever accepted, whatever the response says.
 */
import { describe, expect, it } from "vitest";

import { RELEASES_API, isNewer, parseLatestRelease } from "./update";

describe("RELEASES_API", () => {
  it("asks GitHub for this repository's latest release", () => {
    expect(RELEASES_API).toBe("https://api.github.com/repos/angelrod/pulso/releases/latest");
  });
});

describe("isNewer", () => {
  it("compares versions number by number, not as text", () => {
    expect(isNewer("0.2.0", "0.1.0")).toBe(true);
    expect(isNewer("0.10.0", "0.9.0")).toBe(true);
    expect(isNewer("1.0.0", "0.99.99")).toBe(true);
    expect(isNewer("0.1.1", "0.1.0")).toBe(true);
  });

  it("is false for the same or an older version", () => {
    expect(isNewer("0.1.0", "0.1.0")).toBe(false);
    expect(isNewer("0.1.0", "0.2.0")).toBe(false);
    expect(isNewer("0.9.0", "0.10.0")).toBe(false);
  });

  it("accepts a leading v on either side", () => {
    expect(isNewer("v0.2.0", "0.1.0")).toBe(true);
    expect(isNewer("0.2.0", "v0.2.0")).toBe(false);
  });

  it("is false for anything that is not a plain x.y.z version", () => {
    for (const bad of ["", "latest", "0.2", "0.2.0-beta.1", "1.2.3.4", "v", "1.x.0"]) {
      expect(isNewer(bad, "0.1.0")).toBe(false);
    }
  });
});

describe("parseLatestRelease", () => {
  const ok = {
    tag_name: "v0.2.0",
    html_url: "https://github.com/angelrod/pulso/releases/tag/v0.2.0",
    draft: false,
    prerelease: false,
  };

  it("reads the version and the release page", () => {
    expect(parseLatestRelease(ok)).toEqual({
      version: "0.2.0",
      url: "https://github.com/angelrod/pulso/releases/tag/v0.2.0",
    });
  });

  it("ignores drafts and prereleases", () => {
    expect(parseLatestRelease({ ...ok, draft: true })).toBeNull();
    expect(parseLatestRelease({ ...ok, prerelease: true })).toBeNull();
  });

  // The URL is opened in the browser: only this repository's release pages qualify.
  it("rejects a release page outside this repository", () => {
    for (const html_url of [
      "https://evil.example/angelrod/pulso/releases/tag/v0.2.0",
      "http://github.com/angelrod/pulso/releases/tag/v0.2.0",
      "https://github.com/someone/pulso/releases/tag/v0.2.0",
      "https://github.com/angelrod/pulso-fake/releases/tag/v0.2.0",
      "https://github.com.evil.example/angelrod/pulso/releases/tag/v0.2.0",
      "javascript:alert(1)",
    ]) {
      expect(parseLatestRelease({ ...ok, html_url })).toBeNull();
    }
  });

  it("rejects anything malformed, without throwing", () => {
    for (const raw of [null, undefined, "x", 42, {}, { ...ok, tag_name: 3 }, { ...ok, tag_name: "nightly" }, { ...ok, html_url: null }]) {
      expect(parseLatestRelease(raw)).toBeNull();
    }
  });
});
