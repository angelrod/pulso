// Tests for the two readings behind one row per running copy. A process's path is the one
// it was started from when the kernel's path has left its app (Chrome, with an update
// waiting, runs from a temporary copy). And every process inside an app carries the
// process macOS holds responsible for it, which tells the copies of one app apart.
import Darwin
import Foundation
import Testing
@testable import PulsoCore

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private let second: UInt64 = 1_000_000_000
private let chromeMain = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
private let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
private let chromeClone = "/private/var/folders/zt/abc/X/com.google.Chrome.code_sign_clone/code_sign_clone.1K5vKe/Google Chrome.app.bundle/Contents/MacOS/Google Chrome"
private let raycastMain = "/Applications/Raycast.app/Contents/MacOS/Raycast"
private let safariMain = "/Applications/Safari.app/Contents/MacOS/Safari"
private let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"

@Suite("preferredPath")
struct PreferredPathTests {
    @Test("takes the path it was started from when the kernel's path has left the app")
    func clone() {
        #expect(preferredPath(pidPath: chromeClone, execPath: chromeMain) == chromeMain)
    }

    @Test("keeps the kernel's path when it is inside an app")
    func insideApp() {
        #expect(preferredPath(pidPath: chromeMain, execPath: "/tmp/other.app/Contents/MacOS/x") == chromeMain)
    }

    @Test("keeps the kernel's path when the start path is unknown or not in an app")
    func noBetter() {
        #expect(preferredPath(pidPath: "/bin/zsh", execPath: nil) == "/bin/zsh")
        #expect(preferredPath(pidPath: "/usr/local/bin/node", execPath: "node") == "/usr/local/bin/node")
        #expect(preferredPath(pidPath: chromeClone, execPath: nil) == chromeClone)
    }
}

@Suite("execPath")
struct ExecPathTests {
    @Test("reads the path this process was started from")
    func ownProcess() throws {
        let path = try #require(execPath(getpid()))
        let name = (CommandLine.arguments[0] as NSString).lastPathComponent
        #expect(path.hasSuffix("/" + name) || path == name)
    }

    @Test("gives nil, without crashing, for a process it may not read")
    func notOurs() {
        #expect(execPath(1) == nil)
        #expect(execPath(-1) == nil)
    }
}

/// Fake readers: one scripted process list per call, and a scripted launcher per pid.
private struct Script {
    let processes = Box<[[ProcessReading]]>([])
    let clock = Box<[UInt64]>([])
    let cpu = Box<[CpuSample]>([])
    let launcherCalls = Box<[Int32]>([])
    let launcherMap: [Int32: Int32]
    let responsibleMap: [Int32: Int32]

    var readers: Readers {
        Readers(
            memory: {
                MemoryReading(totalBytes: 1000, freeBytes: 100, usedBytes: 700, wiredBytes: 100,
                              compressedBytes: 50, swapUsedBytes: 0, pressure: .normal)
            },
            cpuTicks: {
                let next = self.cpu.value.removeFirst()
                return next
            },
            processes: {
                let next = self.processes.value.removeFirst()
                return next
            },
            responsible: { pid in self.responsibleMap[pid] },
            now: { Date(timeIntervalSince1970: 1_000_000) },
            monotonicNanos: {
                let next = self.clock.value.removeFirst()
                return next
            },
            launcher: { pid in
                self.launcherCalls.value.append(pid)
                return self.launcherMap[pid]
            })
    }
}

private func reading(_ pid: Int32, _ path: String) -> ProcessReading {
    ProcessReading(pid: pid, path: path, footprintBytes: 100, cpuTimeNanos: 0)
}

private func collectOnce(_ s: Script, _ list: [ProcessReading]) throws -> Snapshot {
    s.cpu.value = [[CpuTimes(user: 0, nice: 0, system: 0, idle: 0)], [CpuTimes(user: 0, nice: 0, system: 0, idle: 1)]]
    s.processes.value = [list, list]
    s.clock.value = [0, second]
    var collector = try Collector(readers: s.readers)
    return try collector.collect()
}

@Suite("Collector: launchers")
struct CollectorLauncherTests {
    @Test("fills in the launcher of every process inside an app, with its path")
    func bundled() throws {
        let s = Script(launcherMap: [760: 760, 761: 760, 800: 5704], responsibleMap: [:])
        let snap = try collectOnce(s, [
            reading(5704, raycastMain),
            reading(760, chromeMain),
            reading(761, chromeHelper),
            reading(800, chromeMain),
        ])
        let chrome = snap.processes.first { $0.pid == 761 }
        #expect(chrome?.launcherPid == 760)
        #expect(chrome?.launcherPath == chromeMain)
        let second = snap.processes.first { $0.pid == 800 }
        #expect(second?.launcherPid == 5704)
        #expect(second?.launcherPath == raycastMain)
    }

    @Test("asks only for processes inside an app, never for command line tools")
    func onlyBundled() throws {
        let s = Script(launcherMap: [:], responsibleMap: [:])
        _ = try collectOnce(s, [reading(760, chromeMain), reading(50, "/usr/local/bin/node")])
        #expect(s.launcherCalls.value.contains(760))
        #expect(!s.launcherCalls.value.contains(50))
    }

    @Test("leaves the path nil when the launcher is not in the list")
    func launcherNotListed() throws {
        let s = Script(launcherMap: [760: 1], responsibleMap: [:])
        let snap = try collectOnce(s, [reading(760, chromeMain)])
        #expect(snap.processes.first?.launcherPid == 1)
        #expect(snap.processes.first?.launcherPath == nil)
    }

    @Test("gives an XPC service its responsible process as launcher, so it joins that copy")
    func xpc() throws {
        let s = Script(launcherMap: [10: 10], responsibleMap: [11: 10])
        let snap = try collectOnce(s, [reading(10, safariMain), reading(11, webContent)])
        let service = snap.processes.first { $0.pid == 11 }
        #expect(service?.responsiblePath == safariMain)
        #expect(service?.launcherPid == 10)
        #expect(service?.launcherPath == safariMain)
    }

    @Test("splits two copies of an app into two rows end to end")
    func endToEnd() throws {
        let s = Script(launcherMap: [760: 760, 761: 760, 800: 5704], responsibleMap: [:])
        let snap = try collectOnce(s, [
            reading(760, chromeMain),
            reading(761, chromeHelper),
            reading(800, chromeMain),
            reading(5704, raycastMain),
        ])
        let rows = buildPanelView(snap, refreshSeconds: 3).rows
        #expect(rows.contains { $0.name == "Google Chrome" && $0.startedBy == nil })
        #expect(rows.contains { $0.name == "Chrome" && $0.startedBy == "Raycast" })
    }
}
