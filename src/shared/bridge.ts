/** The IPC channel names shared by the renderer and the main process. */
export const CHANNELS = { view: "pulso:view", act: "pulso:act", resize: "pulso:resize" } as const;

/** An action the renderer can send to the main process. */
export type PanelAction =
  | { type: "refresh" }
  | { type: "activity-monitor" }
  | { type: "help" }
  | { type: "about" }
  | { type: "quit-app" }
  | { type: "close" }
  | { type: "quit-process"; pid: number }
  | { type: "download-update" };

/** The kinds of view the main process can send back to the renderer. */
export type PanelView = import("../main/panel").PanelView;

/** The bridge the preload exposes on `window.pulso`: one view subscription, two sends. */
export interface PulsoBridge {
  /** Subscribes to incoming views; returns an unsubscribe function. */
  onView(cb: (view: PanelView) => void): () => void;
  /** Sends an action to the main process. */
  act(action: PanelAction): void;
  /** Sends a new panel height to the main process. */
  resize(height: number): void;
}

/** The known action kinds the renderer may request from a click. */
const KNOWN_ACTIONS = [
  "refresh",
  "activity-monitor",
  "help",
  "about",
  "quit-app",
  "close",
  "download-update",
] as const;

/** "close" and the six buttons never need a pid; the only pid action is "quit-process". */
const PID_ACTIONS = new Set(["quit-process"]);

/** A pid is valid only as a positive integer: digits become a number, anything else is rejected. */
function parsePid(pid: unknown): number | null {
  return typeof pid === "string" && /^\d+$/.test(pid) && Number(pid) > 0 ? Number(pid) : null;
}

/** Turns a clicked element's data attributes into an action, or null when the click is not one. */
export function actionFrom(data: { action?: string; pid?: string }): PanelAction | null {
  const { action, pid } = data;
  if (typeof action !== "string") return null;
  if (PID_ACTIONS.has(action)) {
    const parsedPid = parsePid(pid);
    return parsedPid === null ? null : { type: action, pid: parsedPid } as PanelAction;
  }
  if ((KNOWN_ACTIONS as readonly string[]).includes(action)) return { type: action } as PanelAction;
  return null;
}

/** Accepts only a well-formed action of a known kind, rejecting anything else without throwing. */
export function parseAction(raw: unknown): PanelAction | null {
  if (typeof raw !== "object" || raw === null) return null;
  const candidate = raw as { type?: unknown; pid?: unknown };
  const type = candidate.type;
  if (typeof type !== "string") return null;
  if (PID_ACTIONS.has(type)) {
    const pid = typeof candidate.pid === "number" && Number.isInteger(candidate.pid) && candidate.pid > 0 ? candidate.pid : null;
    return pid === null ? null : { type, pid } as PanelAction;
  }
  if ((KNOWN_ACTIONS as readonly string[]).includes(type)) return { type } as PanelAction;
  return null;
}
