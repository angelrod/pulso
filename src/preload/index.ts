import { contextBridge, ipcRenderer } from "electron";

import { CHANNELS } from "../shared/bridge";
import type { PanelAction, PanelView, PulsoBridge } from "../shared/bridge";

/** The page-facing bridge: one `onView` subscription and two `send` actions, nothing more. */
const bridge: PulsoBridge = {
  /** Listens on the view channel and returns an unsubscribe function. */
  onView(cb: (view: PanelView) => void): () => void {
    const listener = (_event: unknown, view: PanelView) => cb(view);
    ipcRenderer.on(CHANNELS.view, listener);
    return () => ipcRenderer.removeListener(CHANNELS.view, listener);
  },
  /** Sends an action over its channel. */
  act(action: PanelAction): void {
    ipcRenderer.send(CHANNELS.act, action);
  },
  /** Sends a new panel height over its channel. */
  resize(height: number): void {
    ipcRenderer.send(CHANNELS.resize, height);
  },
};

// Expose the bridge under `window.pulso` and nothing else; the page never sees ipcRenderer.
contextBridge.exposeInMainWorld("pulso", bridge);
