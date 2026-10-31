// Open at Login: the LaunchAgent file is the state, surviving updates that break SMAppService.
import Foundation

// The LaunchAgent label: the bundle id, so the signed app and the agent share a namespace.
public let loginAgentLabel = "io.github.angelrod.pulso"

// Where the agent's plist lives, per user.
public func loginAgentPath(home: String) -> String {
    "\(home)/Library/LaunchAgents/\(loginAgentLabel).plist"
}

// The plist for an agent that runs the given executable once at login, never relaunches it.
public func loginAgentPlist(executable: String) -> Data? {
    let plist: [String: Any] = [
        "Label": loginAgentLabel,
        "ProgramArguments": [executable],
        "RunAtLoad": true,
        "LimitLoadToSessionType": "Aqua",
        "AssociatedBundleIdentifiers": [loginAgentLabel]
    ]
    do {
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    } catch {
        return nil
    }
}

public func loginAgentStatus(agentExecutable: String?, executable: String) -> LoginItemStatus {
    guard let agentExecutable else { return .notRegistered }
    // nil is off; on when it points at this executable; any other path is stale and rewriteable.
    switch agentExecutable == executable {
    case true: return .enabled
    default: return .notFound
    }
}
