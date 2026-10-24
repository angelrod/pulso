import "./panel.css";

import { actionFrom, type PanelAction } from "../shared/bridge";
import { renderPanel } from "./render";
import type { PanelView } from "../main/panel";

/** The three keyboard shortcuts and the action each one sends. */
const KEYBOARD_ACTIONS: Array<{ key: string; code: string; action: PanelAction }> = [
  { key: "Escape", code: "Escape", action: { type: "close" } },
  { key: "r", code: "KeyR", action: { type: "refresh" } },
  { key: "q", code: "KeyQ", action: { type: "quit-app" } },
];

/** The rendered panel's height in whole pixels, for the main process to size the window. */
function panelHeight(): number {
  return Math.ceil(document.getElementById("panel")!.scrollHeight);
}

/** Replaces #root's HTML with a rendered view and tells the main process its height. */
function onPanelView(view: PanelView): void {
  const root = document.getElementById("root");
  if (!root) return;
  root.innerHTML = renderPanel(view);
  window.pulso.resize(panelHeight());
}

/** The closest element with a data-action, or null. */
function actionTarget(event: MouseEvent): HTMLElement | null {
  const target = event.target as Node | null;
  if (!target || !(target instanceof HTMLElement)) return null;
  return target.closest("[data-action]");
}

/** Handles a click: turn the target's data attributes into an action and send it. */
function onClick(event: MouseEvent): void {
  const el = actionTarget(event);
  if (!el) return;
  const rawAction = el.getAttribute("data-action");
  if (typeof rawAction !== "string") return;
  const pid = el.closest("[data-pid]")?.getAttribute("data-pid") ?? undefined;
  const action = actionFrom({ action: rawAction, pid });
  if (action) window.pulso.act(action);
}

/** Handles a keyboard shortcut: send its action and stop the page's default. */
function onKeydown(event: KeyboardEvent): void {
  const match = KEYBOARD_ACTIONS.find(
    (k) => k.code === event.code && (!k.key || event.key === k.key) && (event.metaKey || event.key === "Escape"),
  );
  if (!match) return;
  event.preventDefault();
  window.pulso.act(match.action);
}

window.pulso.onView(onPanelView);
document.getElementById("root")?.addEventListener("click", onClick);
window.addEventListener("keydown", onKeydown);
