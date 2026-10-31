// Tests for telling apart two running copies of the same app. macOS holds one process
// responsible for each process: an app's helpers answer to its main process, while a
// copy started by another app (a browser opened by a tool) answers to that app. Rows are
// one per copy, and a copy started by another app is named after it when names collide.
import Testing
@testable import PulsoCore

private let chrome = "/Applications/Google Chrome.app"
private let chromeMain = "\(chrome)/Contents/MacOS/Google Chrome"
private let chromeHelper = "\(chrome)/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
private let raycastMain = "/Applications/Raycast.app/Contents/MacOS/Raycast"
private let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"

private func proc(_ pid: Int32, _ command: String, _ bytes: UInt64,
                  launcher: Int32? = nil, launcherPath: String? = nil) -> ProcessSample {
    ProcessSample(pid: pid, cpu: 0, memoryBytes: bytes, command: command,
                  launcherPid: launcher, launcherPath: launcherPath)
}

// The user's Chrome (main 760) and a second Chrome that Raycast (pid 5704) started.
private let twoChromes: [ProcessSample] = [
    proc(760, chromeMain, 400, launcher: 760, launcherPath: chromeMain),
    proc(761, chromeHelper, 300, launcher: 760, launcherPath: chromeMain),
    proc(800, chromeMain, 100, launcher: 5704, launcherPath: raycastMain),
    proc(801, chromeHelper, 50, launcher: 5704, launcherPath: raycastMain),
]

@Suite("groupByApp: one row per running copy")
struct InstanceTests {
    @Test("splits two copies of one app into two rows, each with its own processes")
    func splits() {
        let groups = groupByApp(twoChromes)
        #expect(groups.count == 2)
        #expect(groups[0].pids.sorted() == [760, 761])
        #expect(groups[0].memoryBytes == 700)
        #expect(groups[1].pids.sorted() == [800, 801])
        #expect(groups[1].memoryBytes == 150)
    }

    @Test("gives each copy its own main process, so Quit reaches the right one")
    func ownMain() {
        let groups = groupByApp(twoChromes)
        #expect(groups[0].mainPid == 760)
        #expect(groups[1].mainPid == 800)
        #expect(groups[0].bundlePath == chrome)
        #expect(groups[1].bundlePath == chrome)
    }

    @Test("names the copy another app started after that app, and leaves the user's plain")
    func labels() {
        let names = groupByApp(twoChromes).map(\.name)
        #expect(names == ["Google Chrome", "Google Chrome · Raycast"])
    }

    @Test("names the starter by its command when it is not inside an app")
    func starterOutsideApp() {
        let groups = groupByApp([
            proc(760, chromeMain, 400, launcher: 760, launcherPath: chromeMain),
            proc(800, chromeMain, 100, launcher: 42, launcherPath: "/usr/local/bin/node"),
        ])
        #expect(groups.map(\.name) == ["Google Chrome", "Google Chrome · node"])
    }

    @Test("keeps the plain name when only one copy is running, whoever started it")
    func aloneStaysPlain() {
        let groups = groupByApp([twoChromes[2], twoChromes[3]])
        #expect(groups.count == 1)
        #expect(groups.first?.name == "Google Chrome")
    }

    @Test("puts an XPC service in the copy whose process is responsible for it")
    func xpcJoinsItsCopy() {
        let groups = groupByApp(twoChromes + [
            ProcessSample(pid: 900, cpu: 0, memoryBytes: 20, command: webContent,
                          responsiblePath: chromeMain, launcherPid: 760, launcherPath: chromeMain),
        ])
        #expect(groups.count == 2)
        #expect(groups[0].pids.sorted() == [760, 761, 900])
    }

    @Test("accounts for every process exactly once")
    func everyPidOnce() {
        let pids = groupByApp(twoChromes).flatMap(\.pids).sorted()
        #expect(pids == [760, 761, 800, 801])
    }

    @Test("groups as before when nothing says who started a process")
    func withoutLaunchers() {
        let groups = groupByApp([
            ProcessSample(pid: 760, cpu: 0, memoryBytes: 400, command: chromeMain),
            ProcessSample(pid: 800, cpu: 0, memoryBytes: 100, command: chromeMain),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.name == "Google Chrome")
    }
}
