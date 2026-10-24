/** The bridge the preload exposes on the page. */
import type { PulsoBridge } from "../shared/bridge";

declare global {
  interface Window {
    /** The bridge the preload exposes, typed for the page. */
    pulso: PulsoBridge;
  }
}

declare module "*.css";
