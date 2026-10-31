// Tests for Open at Login through a per-user LaunchAgent. With
// ad-hoc signing, an SMAppService login item breaks at every update; an agent pointing at the
// app's executable path survives it (probed). The agent's file is the state: present and
// pointing at this executable means on.
import Foundation
import Testing
@testable import PulsoCore

private let exe = "/Applications/Pulso.app/Contents/MacOS/Pulso"

@Suite("Login agent")
struct LoginAgentTests {
    @Test("is labelled with the bundle id and lives in the user's LaunchAgents")
    func names() {
        #expect(loginAgentLabel == "io.github.angelrod.pulso")
        #expect(loginAgentPath(home: "/Users/me") == "/Users/me/Library/LaunchAgents/io.github.angelrod.pulso.plist")
    }

    @Test("runs this executable once at login, in the user's session, and never relaunches it")
    func plist() throws {
        let data = try #require(loginAgentPlist(executable: exe))
        let any = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try #require(any as? [String: Any])
        #expect(dict["Label"] as? String == "io.github.angelrod.pulso")
        #expect(dict["ProgramArguments"] as? [String] == [exe])
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(dict["LimitLoadToSessionType"] as? String == "Aqua")
        #expect(dict["AssociatedBundleIdentifiers"] as? [String] == ["io.github.angelrod.pulso"])
        #expect(dict["KeepAlive"] == nil)
    }

    @Test("reads on when the agent points at this executable, off when there is none")
    func status() {
        #expect(loginAgentStatus(agentExecutable: exe, executable: exe) == .enabled)
        #expect(loginAgentStatus(agentExecutable: nil, executable: exe) == .notRegistered)
    }

    @Test("reads an agent that points at another copy as not found, so it can be rewritten")
    func stale() {
        #expect(loginAgentStatus(agentExecutable: "/Users/me/Downloads/Pulso.app/Contents/MacOS/Pulso", executable: exe) == .notFound)
    }
}
