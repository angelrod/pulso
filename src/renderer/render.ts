import type { PanelView } from "../main/panel";

/** The five HTML-breaking characters, escaped in an order that never double-escapes. */
function escapeText(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/** Renders a PanelView into the panel's HTML string (pure; no DOM). */
export function renderPanel(view: PanelView): string {
  const e = escapeText;
  const rows = view.processes
    .map(
      (p) => `
    <div class="proc" data-pid="${p.pid}">
      <div class="name">${e(p.name)}</div>
      <div class="minibar"><i style="width: ${Math.round(p.share * 100)}%"></i></div>
      <span class="quit-btn" data-action="quit-process">Quit</span>
      <div class="mem">${e(p.memory)}</div>
      <div class="cpu">${e(p.cpu)}</div>
    </div>`,
    )
    .join("");
  const sections = view.processes.length
    ? rows
    : `    <div class="empty">${e("No processes")}</div>`;
  const update = view.update
    ? `<div class="update-row">
      <span>${e(view.update.text)}</span>
      <span class="update-btn" data-action="download-update">Download</span>
    </div>`
    : "";
  const advice = view.advice ? `<div class="advice">${e(view.advice)}</div>` : "";
  const tiles = view.tiles
    .map(
      (t, i) => `
      <div class="tile">
        <div class="label">${e(t.label)}<span class="info" title="${e(t.help)}">i</span></div>
        <div class="value">${i === 0 ? '<span class="dot"></span>' : ""}${e(t.value)}</div>
      </div>`,
    )
    .join("");

  return `
<div class="panel tone-${view.tone}" id="panel">
  ${update}
  <div class="section">
    <div class="row-between">
      <span class="label" title="${e(view.memory.help)}">Memory</span>
      <span class="hero-sub">${e(view.memory.detail)}</span>
    </div>
    <div class="row-between" style="margin-top:2px">
      <span class="hero-value">${e(view.memory.percent)}</span>
    </div>
    <div class="bar"><i style="width: ${view.memory.barPercent}%"></i></div>
  </div>

  <div class="tiles">${tiles}
  </div>

  ${advice}
  <div class="divider"></div>
  <div class="section" style="padding-bottom:4px"><span class="label">Using most memory</span></div>
  ${sections}

  <div class="divider"></div>
  <div class="item" data-action="refresh"><span>Refresh</span><span class="key">⌘R</span></div>
  <div class="item" data-action="activity-monitor"><span>Open Activity Monitor</span></div>
  <div class="item" data-action="help"><span>What do these mean?</span></div>
  <div class="divider"></div>
  <div class="item" data-action="about"><span>About Pulso</span></div>
  <div class="item" data-action="quit-app"><span>Quit Pulso</span><span class="key">⌘Q</span></div>
  <div class="foot">${e(view.updated)}</div>
</div>
`;
}
