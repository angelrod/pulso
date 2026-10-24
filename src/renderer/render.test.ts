/**
 * Tests for the panel's markup.
 *
 * `render.ts` turns the view model from `src/main/panel.ts` into an HTML string. It is
 * pure, so it is tested here without a browser. The look itself (CSS) is checked by
 * eye with `pnpm preview:panel`.
 */
import { describe, expect, it } from "vitest";

import type { PanelView } from "../main/panel";
import { renderPanel } from "./render";

const view: PanelView = {
  memory: {
    percent: "85%",
    detail: "27.2 GB of 32.0 GB",
    help: "How much memory is in use. A high number is normal on a Mac.",
    barPercent: 85.1,
  },
  tone: "warning",
  advice: "Your Mac is starting to slow down. Quitting a heavy app below will help.",
  tiles: [
    { label: "Pressure", value: "Warning", help: "How hard your Mac is working to find free memory. The one to watch." },
    { label: "Swap", value: "20.0 GB", help: "Memory moved to the disk when it ran out of room. Many GB feels slower." },
    { label: "CPU", value: "22%", help: "How busy the processor is right now." },
  ],
  processes: [
    { pid: 760, name: "Google Chrome", memory: "459.6 MB", cpu: "0.2%", share: 1 },
    { pid: 62726, name: "node", memory: "382.0 MB", cpu: "2.0%", share: 0.83 },
  ],
  updated: "Updated 00:42:00 · refreshes every 3 s",
  update: null,
};

const html = (over: Partial<PanelView> = {}) => renderPanel({ ...view, ...over });
const count = (haystack: string, needle: string) => haystack.split(needle).length - 1;

describe("renderPanel: content", () => {
  it("shows the memory percent, the amounts and the bar at the exact width", () => {
    const out = html();
    expect(out).toContain("85%");
    expect(out).toContain("27.2 GB of 32.0 GB");
    expect(out).toContain("width: 85.1%");
  });

  it("marks the whole panel with the tone, so the CSS can colour it", () => {
    expect(html()).toContain("tone-warning");
    expect(html({ tone: "critical" })).toContain("tone-critical");
    expect(html({ tone: "normal" })).toContain("tone-normal");
  });

  it("renders the three tiles with their labels and values", () => {
    const out = html();
    expect(count(out, 'class="tile"')).toBe(3);
    for (const t of view.tiles) {
      expect(out).toContain(t.label);
      expect(out).toContain(t.value);
    }
  });

  it("puts every explanation in a title attribute, so it shows on hover", () => {
    const out = html();
    expect(out).toContain(`title="${view.memory.help}"`);
    for (const t of view.tiles) expect(out).toContain(`title="${t.help}"`);
  });

  it("shows the advice box only when there is advice", () => {
    expect(html()).toContain('class="advice"');
    expect(html()).toContain(view.advice!);
    expect(html({ advice: null, tone: "normal" })).not.toContain('class="advice"');
  });

  it("shows the footer line", () => {
    expect(html()).toContain("Updated 00:42:00 · refreshes every 3 s");
  });
});

describe("renderPanel: processes", () => {
  it("renders one row per process, keyed by pid, with a quit button", () => {
    const out = html();
    expect(count(out, 'class="proc"')).toBe(2);
    expect(out).toContain('data-pid="760"');
    expect(out).toContain('data-pid="62726"');
    expect(count(out, 'data-action="quit-process"')).toBe(2);
  });

  it("sizes each row's bar by its share", () => {
    const out = html();
    expect(out).toContain("width: 100%");
    expect(out).toContain("width: 83%");
  });

  it("says so when there are no processes", () => {
    const out = html({ processes: [] });
    expect(out).toContain("No processes");
    expect(out).not.toContain('class="proc"');
  });
});

describe("renderPanel: actions", () => {
  it("offers every action as a data-action the renderer can wire up", () => {
    const out = html();
    for (const action of ["refresh", "activity-monitor", "help", "about", "quit-app"]) {
      expect(out).toContain(`data-action="${action}"`);
    }
  });
});

describe("renderPanel: safety", () => {
  // Real `ps` output includes names like `<defunct>`; text must never become markup.
  it("escapes every text it inserts", () => {
    const out = html({
      processes: [{ pid: 1, name: `<defunct> & "x" 'y'`, memory: "1 B", cpu: "0.0%", share: 1 }],
      advice: "<b>bold</b>",
    });
    expect(out).toContain("&lt;defunct&gt; &amp; &quot;x&quot; &#39;y&#39;");
    expect(out).not.toContain("<defunct>");
    expect(out).toContain("&lt;b&gt;bold&lt;/b&gt;");
    expect(out).not.toContain("<b>bold</b>");
  });

  it("escapes inside attributes too", () => {
    const out = html({ tiles: [{ label: "CPU", value: "1%", help: `say "hi" <now>` }] });
    expect(out).toContain('title="say &quot;hi&quot; &lt;now&gt;"');
  });
});

describe("renderPanel: update", () => {
  it("offers the download only when there is an update", () => {
    expect(html()).not.toContain('data-action="download-update"');
    const out = html({ update: { text: "Pulso 0.2.0 is available" } });
    expect(out).toContain("Pulso 0.2.0 is available");
    expect(out).toContain('data-action="download-update"');
  });

  it("escapes the update text", () => {
    const out = html({ update: { text: "<img src=x>" } });
    expect(out).toContain("&lt;img src=x&gt;");
    expect(out).not.toContain("<img src=x>");
  });
});
