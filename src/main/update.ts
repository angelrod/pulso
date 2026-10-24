/** Where the app asks GitHub for the latest release of this repository. */
export const RELEASES_API: string =
  "https://api.github.com/repos/angelrod/pulso/releases/latest";

/** A release the user may be offered: its version and its download page. */
export interface AvailableUpdate {
  version: string;
  url: string;
}

/** A plain x.y.z with one optional leading v, each part whole — else null. */
function parseVersion(v: string): string[] | null {
  const withoutV = v.startsWith("v") ? v.slice(1) : v;
  const parts = withoutV.split(".");
  if (parts.length !== 3 || parts.some((p) => !/^\d+$/.test(p))) return null;
  return parts;
}

/** A version is newer at the first part where the two differ, compared numerically. */
export function isNewer(latest: string, current: string): boolean {
  const a = parseVersion(latest);
  const b = parseVersion(current);
  if (a === null || b === null) return false;
  for (let i = 0; i < a.length; i++) {
    const diff = Number(a[i]) - Number(b[i]);
    if (diff !== 0) return diff > 0;
  }
  return false;
}

/** Only this repository's release pages are ever accepted, whatever the response says. */
function isReleaseUrl(url: string): boolean {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return false;
  }
  return (
    parsed.protocol === "https:" &&
    parsed.host === "github.com" &&
    parsed.pathname.startsWith("/angelrod/pulso/releases/")
  );
}

/** GitHub's latest release into a link we show, or null for anything we reject. */
export function parseLatestRelease(raw: unknown): AvailableUpdate | null {
  if (typeof raw !== "object" || raw === null) return null;
  const obj = raw as {
    tag_name?: unknown;
    html_url?: unknown;
    draft?: unknown;
    prerelease?: unknown;
  };
  if (obj.draft === true || obj.prerelease === true) return null;

  if (typeof obj.tag_name !== "string") return null;
  const version = parseVersion(obj.tag_name);
  if (version === null) return null;

  if (typeof obj.html_url !== "string" || !isReleaseUrl(obj.html_url)) return null;

  return { version: version.join("."), url: obj.html_url };
}
