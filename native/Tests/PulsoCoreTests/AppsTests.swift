// Tests for groupByApp, translated one to one from the TypeScript contract in
// src/main/apps.test.ts. Every process inside an .app bundle is summed under the
// outermost bundle; processes outside any bundle stay one row each, never merged.
import Testing
@testable import PulsoCore

private let chrome = "/Applications/Google Chrome.app"

private func proc(_ pid: Int32, _ command: String, _ memoryBytes: UInt64, _ cpu: Double = 0) -> ProcessSample {
    ProcessSample(pid: pid, cpu: cpu, memoryBytes: memoryBytes, command: command)
}

private let processes: [ProcessSample] = [
    proc(760, "\(chrome)/Contents/MacOS/Google Chrome", 400, 1.5),
    proc(761, "\(chrome)/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", 300, 2),
    proc(762, "\(chrome)/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)", 200, 0.5),
    proc(900, "/Applications/Slack.app/Contents/MacOS/Slack", 100),
    proc(901, "/Applications/Slack.app/Contents/Frameworks/Slack Helper (Renderer).app/Contents/MacOS/Slack Helper (Renderer)", 250),
    proc(50, "/usr/local/bin/node", 280, 3),
    proc(51, "/usr/local/bin/node", 270, 4),
    proc(1, "/sbin/launchd", 18),
    proc(70, "-zsh", 5),
]

private func byName(_ name: String) -> [AppGroup] {
    groupByApp(processes).filter { $0.name == name }
}

@Suite("groupByApp: apps")
struct GroupAppsTests {
    @Test("sums every process of an app under the outermost bundle's name")
    func sums() throws {
        let g = try #require(byName("Google Chrome").first)
        #expect(g.memoryBytes == 900)
        #expect(abs(g.cpu - 4) < 1e-10)
        #expect(g.pids.sorted() == [760, 761, 762])
        #expect(g.bundlePath == chrome)
    }

    @Test("never lists a helper bundle as its own app")
    func noHelpers() throws {
        let names = groupByApp(processes).map(\.name)
        #expect(!names.contains { $0.contains("Helper") })
        #expect(try #require(byName("Slack").first).memoryBytes == 350)
    }

    @Test("knows the app's main process: the executable directly in its Contents/MacOS")
    func mainProcess() throws {
        #expect(try #require(byName("Google Chrome").first).mainPid == 760)
        #expect(try #require(byName("Slack").first).mainPid == 900)
    }

    @Test("has no main process when only helpers are running")
    func helpersOnly() {
        let groups = groupByApp([processes[1], processes[2]])
        #expect(groups.count == 1)
        #expect(groups.first?.mainPid == nil)
    }
}

@Suite("groupByApp: everything else")
struct GroupOthersTests {
    @Test("keeps each process outside a bundle as its own row, never merged by name")
    func neverMerged() {
        let node = byName("node")
        #expect(node.count == 2)
        #expect(node.map(\.pids) == [[50], [51]])
        for g in node {
            #expect(g.bundlePath == nil)
            #expect(g.mainPid == g.pids.first)
        }
    }

    @Test("carries each one's own memory and cpu")
    func ownMemory() throws {
        let first = try #require(byName("node").first)
        #expect(first.memoryBytes == 280)
        #expect(first.cpu == 3)
        #expect(try #require(byName("launchd").first).memoryBytes == 18)
    }

    @Test("names them as shortName does, including commands that are not paths")
    func names() {
        #expect(byName("launchd").count == 1)
        #expect(byName("-zsh").count == 1)
    }
}

@Suite("groupByApp: shape")
struct GroupShapeTests {
    @Test("accounts for every process exactly once")
    func everyProcessOnce() {
        let pids = groupByApp(processes).flatMap(\.pids)
        #expect(pids.sorted() == processes.map(\.pid).sorted())
    }

    @Test("keeps the order in which apps first appear")
    func order() {
        #expect(groupByApp(processes).map(\.name) == ["Google Chrome", "Slack", "node", "node", "launchd", "-zsh"])
    }

    @Test("returns nothing for nothing")
    func empty() {
        #expect(groupByApp([]).isEmpty)
    }
}
