// What a row's click brings to the front: its own app, the app a lone process runs in, or nothing
import Foundation

// The app a lone process runs in, as the app layer found it.
public struct FrontHost: Equatable, Sendable {
    public let pid: Int32
    public let name: String
    public init(pid: Int32, name: String) {
        self.pid = pid
        self.name = name
    }
}

public enum FrontPlan: Equatable, Sendable {
    case app(pid: Int32)                // bring this app process to the front
    case host(pid: Int32, name: String) // a lone process: bring the app it runs in
    case none                           // a background process with no window
}

// A bundle is its app; a lone process counts only when the row is outside any app.
public func frontPlan(_ group: AppGroup, host: FrontHost?) -> FrontPlan {
    if let bundlePath = group.bundlePath {
        return group.mainPid.map(FrontPlan.app) ?? .none
    }
    if let host {
        return .host(pid: host.pid, name: host.name)
    }
    return .none
}

// What the row's tooltip says before the click, so the click is not a surprise.
public func frontHint(_ plan: FrontPlan, name: String) -> String {
    switch plan {
    case .app:
        return "Click to bring \(name) to the front."
    case .host(_, let hostName):
        return "Runs in \(hostName). Click to show \(hostName)."
    case .none:
        return "Background process, no window to show."
    }
}
