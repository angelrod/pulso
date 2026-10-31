// Tests for which processes make a separate copy of an app. Only a launcher that is another
// app does: helpers that macOS holds responsible for themselves stay in their app's row
// (Dock's helpers, Cursor's), and a helper of a copy another app started follows its parent.
import Foundation
import Testing
@testable import PulsoCore

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private let chrome = "/Applications/Google Chrome.app"
private let chromeMain = "\(chrome)/Contents/MacOS/Google Chrome"
private let chromeHelper = "\(chrome)/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"
private let raycastMain = "/Applications/Raycast.app/Contents/MacOS/Raycast"
private let dockMain = "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock"
private let dockHelper = "/System/Library/CoreServices/Dock.app/Contents/XPCServices/com.apple.dock.extra.xpc/Contents/MacOS/com.apple.dock.extra"

private func proc(_ pid: Int32, _ command: String, _ bytes: UInt64,
                  launcher: Int32?, launcherPath: String?) -> ProcessSample {
    ProcessSample(pid: pid, cpu: 0, memoryBytes: bytes, command: command,
                  launcherPid: launcher, launcherPath: launcherPath)
}

@Suite("groupByApp: what makes a copy")
struct CopyKeyTests {
    @Test("keeps a helper that is responsible for itself in its app's row")
    func selfResponsibleHelper() {
        let groups = groupByApp([
            proc(724, dockMain, 30, launcher: 724, launcherPath: dockMain),
            proc(725, dockHelper, 10, launcher: 725, launcherPath: dockHelper),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.name == "Dock")
        #expect(groups.first?.pids.sorted() == [724, 725])
        #expect(groups.first?.mainPid == 724)
    }

    @Test("keeps the user's copy whole when its helpers answer to different processes of it")
    func ownCopyWhole() {
        let groups = groupByApp([
            proc(760, chromeMain, 400, launcher: 760, launcherPath: chromeMain),
            proc(761, chromeHelper, 300, launcher: 760, launcherPath: chromeMain),
            proc(762, chromeHelper, 200, launcher: 762, launcherPath: chromeHelper),
        ])
        #expect(groups.count == 1)
        #expect(groups.first?.memoryBytes == 900)
        #expect(groups.first?.mainPid == 760)
    }

    @Test("still splits off a copy that another app started")
    func otherAppStillSplits() {
        let groups = groupByApp([
            proc(760, chromeMain, 400, launcher: 760, launcherPath: chromeMain),
            proc(800, chromeMain, 100, launcher: 5704, launcherPath: raycastMain),
        ])
        #expect(groups.map(\.name) == ["Google Chrome", "Google Chrome · Raycast"])
    }
}

/// Fake readers with a scripted launcher and parent per pid.
private struct Script {
    let processes = Box<[[ProcessReading]]>([])
    let clock = Box<[UInt64]>([])
    let cpu = Box<[CpuSample]>([])
    let launcherMap: [Int32: Int32]
    let parentMap: [Int32: Int32]

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
            responsible: { _ in nil },
            now: { Date(timeIntervalSince1970: 1_000_000) },
            monotonicNanos: {
                let next = self.clock.value.removeFirst()
                return next
            },
            launcher: { pid in self.launcherMap[pid] },
            parent: { pid in self.parentMap[pid] })
    }
}

private func collectOnce(_ s: Script, _ list: [ProcessReading]) throws -> Snapshot {
    s.cpu.value = [[CpuTimes(user: 0, nice: 0, system: 0, idle: 0)], [CpuTimes(user: 0, nice: 0, system: 0, idle: 1)]]
    s.processes.value = [list, list]
    s.clock.value = [0, 1_000_000_000]
    var collector = try Collector(readers: s.readers)
    return try collector.collect()
}

private func reading(_ pid: Int32, _ path: String, _ bytes: UInt64) -> ProcessReading {
    ProcessReading(pid: pid, path: path, footprintBytes: bytes, cpuTimeNanos: 0)
}

@Suite("Collector: helpers follow their parent")
struct ParentLauncherTests {
    @Test("gives a self-responsible helper its parent's launcher when the parent is the same app")
    func followsParent() throws {
        let s = Script(launcherMap: [5704: 5704, 800: 5704, 801: 801], parentMap: [801: 800])
        let snap = try collectOnce(s, [
            reading(5704, raycastMain, 50),
            reading(800, chromeMain, 100),
            reading(801, chromeHelper, 400),
        ])
        let helper = snap.processes.first { $0.pid == 801 }
        #expect(helper?.launcherPid == 5704)
        #expect(helper?.launcherPath == raycastMain)
    }

    @Test("puts that helper's memory in the copy's row, end to end")
    func endToEnd() throws {
        let s = Script(launcherMap: [760: 760, 5704: 5704, 800: 5704, 801: 801], parentMap: [801: 800])
        let snap = try collectOnce(s, [
            reading(760, chromeMain, 1000),
            reading(5704, raycastMain, 50),
            reading(800, chromeMain, 100),
            reading(801, chromeHelper, 400),
        ])
        let rows = buildPanelView(snap, refreshSeconds: 3).rows
        let copy = rows.first { $0.startedBy == "Raycast" }
        #expect(copy?.memory == formatBytes(500))
        #expect(rows.filter { $0.name.hasSuffix("Chrome") }.count == 2)
    }

    @Test("leaves a self-responsible helper alone when its parent is not the same app")
    func parentElsewhere() throws {
        let s = Script(launcherMap: [724: 724, 725: 725], parentMap: [725: 1])
        let snap = try collectOnce(s, [reading(724, dockMain, 30), reading(725, dockHelper, 10)])
        #expect(snap.processes.first { $0.pid == 725 }?.launcherPid == 725)
        #expect(buildPanelView(snap, refreshSeconds: 3).rows.map(\.name) == ["Dock"])
    }
}
