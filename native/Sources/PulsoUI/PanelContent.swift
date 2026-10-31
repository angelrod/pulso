// PulsoUI: the panel's SwiftUI view, rendered from a PulsoCore view model.
import SwiftUI
import PulsoCore

/// Actions the panel can fire back to the controller.
public enum PanelAction: Equatable, Sendable {
    case refresh
    case activityMonitor
    case help
    case about
    case checkForUpdates
    case quitPulso
    case quitRow(pid: Int32)
    case front(pid: Int32)
    case toggleLogin
}

// The panel is a fixed 340 pt wide material; no background or frame is drawn.
private let panelWidth: Double = 340

// The hover highlight colour, matching panel.css :hover.
private let hoverFill = Color(red: 0x0A / 255, green: 0x64 / 255, blue: 0xD8 / 255)

// Tone colours from panel.css, the one source for the bar and the pressure dot.
private let toneColor = [
    Pressure.normal: Color(hex: 0x30D158),
    Pressure.warning: Color(hex: 0xFF9F0A),
    Pressure.critical: Color(hex: 0xFF453A),
]

public struct PanelContent: View {
    let view: PanelView
    let highlightedPid: Int32?
    let onAction: (PanelAction) -> Void

    public init(view: PanelView, highlightedPid: Int32? = nil,
                onAction: @escaping (PanelAction) -> Void) {
        self.view = view
        self.highlightedPid = highlightedPid
        self.onAction = onAction
    }

    @Environment(\.colorScheme) private var scheme
    @State private var hoverPid: Int32?
    @State private var hoverAction: String?

    // The mini-bar track and fill are scheme-aware, matching panel.css per-scheme values.
    private func miniTrack() -> Color {
        scheme == .dark ? Color(hex: 0xFFFFFF).opacity(0.10) : Color(hex: 0x000000).opacity(0.10)
    }

    private func miniFill() -> Color {
        scheme == .dark ? Color(hex: 0xFFFFFF).opacity(0.55) : Color(hex: 0x000000).opacity(0.28)
    }

    private var activePid: Int32? {
        hoverPid ?? highlightedPid
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            memoryHeader
            tiles
            if let advice = view.advice {
                adviceBox(advice)
            }
            divider
            usingHeader
            rows
            divider
            actionMenu
        }
        .frame(width: panelWidth)
        .padding(6)
        .onAppear { hoverPid = highlightedPid }
    }

    // The MEMORY label carries the memory help; the amounts sit on the right.
    private var memoryHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("MEMORY")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.04)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .help(view.memory.help)
                Spacer(minLength: 0)
                Text(view.memory.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text(view.memory.percent)
                .font(.system(size: 30, weight: .semibold))
            panelBar(view.memory.barPercent, tone: view.tone)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // One info dot per tile, each showing the tile's tooltip via native help.
    private func helpDot(_ help: String) -> some View {
        Image(systemName: "i.circle")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .help(help)
    }

    // The memory bar: a tone-coloured fill on a scheme-faint track, width = barPercent.
    private func panelBar(_ barPercent: Double, tone: Pressure) -> some View {
        let w = max(0, min(100, barPercent)) / 100
        let track = scheme == .dark ? Color(hex: 0xFFFFFF).opacity(0.10) : Color(hex: 0x000000).opacity(0.10)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(track)
                    .frame(height: 6)
                Rectangle()
                    .fill(toneColor[tone] ?? .secondary)
                    .frame(width: w * geo.size.width, height: 6)
            }
        }
        .frame(height: 6)
    }

    private var tiles: some View {
        HStack(spacing: 0) {
            tile("PRESSURE", view.tiles[0].value) { helpDot(view.tiles[0].help) }
            Divider()
            tile("SWAP", view.tiles[1].value) { helpDot(view.tiles[1].help) }
            Divider()
            tile("CPU", view.tiles[2].value) { helpDot(view.tiles[2].help) }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private func tile(_ label: String, _ value: String, _ icon: () -> some View) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.04)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                icon()
            }
            HStack(spacing: 4) {
                if label == "PRESSURE" {
                    Circle()
                        .frame(width: 8, height: 8)
                        .foregroundStyle(toneColor[view.tone] ?? .secondary)
                }
                Text(value)
                    .font(.system(size: 17, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // The advice box, tinted by the tone, with per-scheme text colour and a row-width inset.
    private func adviceBox(_ text: String) -> some View {
        let toneColor = view.tone == .warning ? Color(hex: 0xFF9F0A) : Color(hex: 0xFF453A)
        let toneText = scheme == .dark
            ? (view.tone == .warning ? Color(hex: 0xFFD08A) : Color(hex: 0xFFB3AD))
            : (view.tone == .warning ? Color(hex: 0xB35300) : Color(hex: 0xC41E3A))
        return Text(text)
            .font(.system(size: 12))
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(toneColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(toneText)
            .padding(.horizontal, 14)
    }

    // A 1 pt divider between sections.
    private var divider: some View {
        return Rectangle()
            .fill(Color.secondary)
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private var usingHeader: some View {
        Text(view.sectionTitle)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.04)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 14)
            .padding(.top, 8)
    }

    // The rows; the highlighted one gets the blue highlight and reveals Quit.
    private var rows: some View {
        return VStack(spacing: 0) {
            ForEach(view.rows, id: \.pid) { row in
                panelRow(row)
            }
        }
        .padding(.horizontal, 6)
    }

    // The row columns: name / 46 pt slot / memory / cpu, fixed widths.
    private func panelRow(_ row: PanelView.Row) -> some View {
        return HStack {
            HStack(spacing: 4) {
                Text(row.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let by = row.startedBy {
                    Text("by \(by)")
                        .foregroundStyle(activePid == row.pid ? .white.opacity(0.75) : .secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .font(.system(size: 13))
            Spacer(minLength: 8)
            slot(row)
                .frame(width: 46)
            Text(row.memory)
                .font(.system(size: 13))
                .frame(width: 66, alignment: .trailing)
            Text(row.cpu)
                .font(.system(size: 12))
                .frame(width: 44, alignment: .trailing)
        }
        .foregroundStyle(activePid == row.pid ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { onAction(.front(pid: row.pid)) }
        .help(row.hint ?? "")
        .onHover { hovering in
            if hovering {
                hoverPid = row.pid
            } else if hoverPid == row.pid {
                hoverPid = nil
            }
        }
        .background(activePid == row.pid ? hoverFill : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // The mini bar on its track, or the Quit button when the row is hovered.
    private func slot(_ row: PanelView.Row) -> some View {
        return Group {
            if activePid == row.pid {
                Button(action: { onAction(.quitRow(pid: row.pid)) }) {
                    Text("Quit")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .background(Color(hex: 0xFFFFFF).opacity(0.22), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(.white)
            } else {
                MiniBar(share: row.share, track: miniTrack(), fill: miniFill())
            }
        }
    }

    // Refresh, the help links, then the app actions, each group behind a divider.
    private var actionMenu: some View {
        VStack(spacing: 0) {
            actionItem("Refresh") { onAction(.refresh) }
            actionItem("Open Activity Monitor") { onAction(.activityMonitor) }
            actionItem("What do these mean?") { onAction(.help) }
            divider
            actionItem("About Pulso") { onAction(.about) }
            actionItem("Check for Updates…") { onAction(.checkForUpdates) }
            if view.openAtLogin != nil { actionItem("Open at Login") { onAction(.toggleLogin) } }
            actionItem("Quit Pulso") { onAction(.quitPulso) }
        }
    }

    // An action row with its keyboard shortcut on the right, dimmed; plain style fills the row.
    private func actionItem(_ title: String, _ action: @escaping () -> Void) -> some View {
        return Button(action: action) {
            HStack {
                Text(title)
                Spacer(minLength: 0)
                Text(shortcut(for: title))
                    .foregroundStyle(hoverAction == title ? .white.opacity(0.75) : .secondary)
            }
            .font(.system(size: 13))
            .foregroundStyle(hoverAction == title ? .white : .primary)
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoverAction = title
            } else if hoverAction == title {
                hoverAction = nil
            }
        }
        .background(hoverAction == title ? hoverFill : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 6)
    }

    // The shortcuts the panel advertises for Refresh and Quit Pulso.
    private func shortcut(for title: String) -> String {
        switch title {
        case "Refresh": return "⌘R"
        case "Quit Pulso": return "⌘Q"
        case "Open at Login": return view.openAtLogin == true ? "✓" : ""
        default: return ""
        }
    }

}

// A 46×4 pt track with a fill to `share`, clamped to 0...1; both colors scheme-aware.
public struct MiniBar: View {
    let share: Double
    let track: Color
    let fill: Color

    public init(share: Double, track: Color, fill: Color) {
        self.share = share
        self.track = track
        self.fill = fill
    }

    public var body: some View {
        return ZStack(alignment: .leading) {
            Rectangle()
                .fill(track)
                .frame(height: 4)
            Rectangle()
                .fill(fill)
                .frame(width: max(0, min(1, share) * 46), height: 4)
        }
    }
}

// A hex colour, matching the panel.css values.
extension Color {
    init(hex: UInt32) {
        let r = Double(hex >> 16 & 0xFF) / 255
        let g = Double(hex >> 8 & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
