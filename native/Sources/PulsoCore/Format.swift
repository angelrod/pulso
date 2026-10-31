// PulsoCore: the testable, pure core of a native Pulso (viability spike).
import Foundation

let sizeUnits = ["B", "KB", "MB", "GB", "TB"]

// A short name fits the menu's row width, the ellipsis counting toward the limit.
let nameMax = 32

func whole(_ v: Double) -> String { "\(Int(v.rounded()))" }

func fraction(_ v: Double) -> String {
    // One decimal place, forced '.', matching the TypeScript NumberFormat.
    let scaled = (v * 10).rounded()
    return "\(Int(scaled / 10)).\(Int(scaled) % 10)"
}

/// Steps up a unit before rounding would otherwise display 1024.0 of it.
public func formatBytes(_ bytes: UInt64) -> String {
    var unit = 0
    var value = Double(bytes)
    while unit < sizeUnits.count - 1 && value >= 1024 {
        value /= 1024
        unit += 1
    }
    // Step up once more if a single decimal would round up to 1024 of this unit.
    if unit < sizeUnits.count - 1, Double(round(value * 10) / 10) >= 1024 {
        value /= 1024
        unit += 1
    }
    return "\(unit == 0 ? whole(value) : fraction(value)) \(sizeUnits[unit])"
}

public func shortName(_ command: String) -> String {
    var name = command
    if name.hasPrefix("/") {
        // Anchor on the last .app: the segment before .app/Contents/MacOS/ is the app name.
        let marker = ".app/Contents/MacOS/"
        let before = (name as NSString).components(separatedBy: marker).dropLast().joined()
        if before.isEmpty {
            name = (command as NSString).components(separatedBy: "/").last ?? ""
        } else {
            name = (before as NSString).components(separatedBy: "/").last ?? ""
        }
    }
    return trimName(name)
}

private func trimName(_ name: String) -> String {
    name.count > nameMax ? String(name.prefix(nameMax - 1)) + "\u{2026}" : name
}
