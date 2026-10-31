// Tests for attributing XPC services to the app responsible for them (Safari's web
// content under Safari), and only them: processes started from a terminal report the
// terminal app as responsible, and must stay their own rows, never merged into it.
import Darwin
import Foundation
import Testing
@testable import PulsoCore

private let safari = "/Applications/Safari.app"
private let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
private let raycast = "/Applications/Raycast.app"

private func proc(_ pid: Int32, _ command: String, _ bytes: UInt64, responsible: String? = nil) -> ProcessSample {
    ProcessSample(pid: pid, cpu: 0, memoryBytes: bytes, command: command, responsiblePath: responsible)
}

@Suite("groupByApp with responsible apps")
struct ResponsibleGroupingTests {
    @Test("counts an XPC service under the app responsible for it")
    func xpcUnderSafari() throws {
        let groups = groupByApp([
            proc(10, "\(safari)/Contents/MacOS/Safari", 300),
            proc(11, webContent, 500, responsible: "\(safari)/Contents/MacOS/Safari"),
            proc(12, webContent, 200, responsible: "\(safari)/Contents/MacOS/Safari"),
        ])
        #expect(groups.count == 1)
        let g = try #require(groups.first)
        #expect(g.name == "Safari")
        #expect(g.bundlePath == safari)
        #expect(g.memoryBytes == 1000)
        #expect(g.pids.sorted() == [10, 11, 12])
        #expect(g.mainPid == 10)
    }

    @Test("creates the app's row from its XPC services even when the app itself is not listed")
    func xpcAloneMakesTheRow() throws {
        let groups = groupByApp([proc(11, webContent, 500, responsible: "\(safari)/Contents/MacOS/Safari")])
        let g = try #require(groups.first)
        #expect(g.name == "Safari")
        #expect(g.mainPid == nil)
    }

    @Test("never merges a command line tool into the terminal app responsible for it")
    func terminalChildrenStayApart() {
        let groups = groupByApp([
            proc(20, "\(raycast)/Contents/MacOS/Raycast", 400),
            proc(21, "/usr/local/bin/node", 280, responsible: "\(raycast)/Contents/MacOS/Raycast"),
            proc(22, "/bin/zsh", 5, responsible: "\(raycast)/Contents/MacOS/Raycast"),
        ])
        #expect(groups.map(\.name) == ["Raycast", "node", "zsh"])
        #expect(groups.first?.memoryBytes == 400)
    }

    @Test("keeps an XPC service as its own row when its responsible process is not in an app")
    func xpcWithoutApp() {
        let groups = groupByApp([proc(30, webContent, 50, responsible: "/usr/libexec/somedaemon")])
        #expect(groups.count == 1)
        #expect(groups.first?.bundlePath == nil)
        #expect(groups.first?.name == "com.apple.WebKit.WebContent")
    }

    @Test("ignores a responsible path for processes that already live inside an app")
    func bundledProcessUnchanged() {
        let groups = groupByApp([
            proc(40, "/Applications/Slack.app/Contents/MacOS/Slack", 100, responsible: "\(raycast)/Contents/MacOS/Raycast"),
        ])
        #expect(groups.map(\.name) == ["Slack"])
    }
}

@Suite("responsiblePid")
struct ResponsiblePidTests {
    @Test("finds a living responsible process for this one")
    func forSelf() throws {
        let me = ProcessInfo.processInfo.processIdentifier
        let holder = try #require(responsiblePid(me))
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        #expect(proc_pidpath(holder, &buffer, UInt32(buffer.count)) > 0, "pid \(holder) has no path")
    }

    @Test("gives nil, not a crash, for a pid that does not exist")
    func missing() {
        #expect(responsiblePid(999_999) == nil)
    }
}
