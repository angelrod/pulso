// Tests for what a click on a row brings to the front: that copy of the app, the app a lone
// process runs in (a terminal's node shows the terminal), or nothing for a background
// service. Each plan has the hint the row's tooltip shows before the click.
import Testing
@testable import PulsoCore

private let chrome = "/Applications/Google Chrome.app"

private let userChrome = AppGroup(name: "Google Chrome", bundlePath: chrome, pids: [760, 761], mainPid: 760,
                                  memoryBytes: 700, cpu: 0)
private let toolChrome = AppGroup(name: "Google Chrome · Raycast", bundlePath: chrome, pids: [800], mainPid: 800,
                                  memoryBytes: 150, cpu: 0, startedBy: "Raycast")
private let helpersOnly = AppGroup(name: "Safari", bundlePath: "/Applications/Safari.app", pids: [11], mainPid: nil,
                                   memoryBytes: 50, cpu: 0)
private let node = AppGroup(name: "node", bundlePath: nil, pids: [50], mainPid: 50, memoryBytes: 280, cpu: 0)
private let mysqld = AppGroup(name: "mysqld", bundlePath: nil, pids: [60], mainPid: 60, memoryBytes: 600, cpu: 0)

@Suite("frontPlan")
struct FrontPlanTests {
    @Test("brings an app's own copy to the front through its main process")
    func app() {
        #expect(frontPlan(userChrome, host: nil) == .app(pid: 760))
        #expect(frontPlan(toolChrome, host: nil) == .app(pid: 800))
    }

    @Test("shows the app a lone process runs in")
    func host() {
        #expect(frontPlan(node, host: FrontHost(pid: 611, name: "Cursor")) == .host(pid: 611, name: "Cursor"))
    }

    @Test("does nothing for a lone process that runs in no app")
    func service() {
        #expect(frontPlan(mysqld, host: nil) == .none)
    }

    @Test("does nothing for an app whose main process is not running")
    func noMain() {
        #expect(frontPlan(helpersOnly, host: nil) == .none)
    }

    @Test("ignores a host for a row that is an app")
    func appIgnoresHost() {
        #expect(frontPlan(userChrome, host: FrontHost(pid: 611, name: "Cursor")) == .app(pid: 760))
    }
}

@Suite("frontHint")
struct FrontHintTests {
    @Test("tells the user what the click will do, before the click")
    func hints() {
        #expect(frontHint(.app(pid: 760), name: "Chrome") == "Click to bring Chrome to the front.")
        #expect(frontHint(.host(pid: 611, name: "Cursor"), name: "node") == "Runs in Cursor. Click to show Cursor.")
        #expect(frontHint(.none, name: "mysqld") == "Background process, no window to show.")
    }
}
