// Tests for showing each row's CPU as a share of the whole Mac, the same scale as the CPU
// tile, so a row never reads more than the machine. The
// snapshot carries the core count the collector measured; 1 keeps the old per-core scale.
import Foundation
import Testing
@testable import PulsoCore

private let chrome = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
private let chromeHelper = "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper"

private func snapshot(cores: Int, _ processes: [ProcessSample]) -> Snapshot {
    Snapshot(
        takenAt: Date(timeIntervalSince1970: 0),
        memory: MemoryReading(totalBytes: 1000, freeBytes: 100, usedBytes: 700, wiredBytes: 100,
                              compressedBytes: 50, swapUsedBytes: 0, pressure: .normal),
        cpuPercent: 30,
        processes: processes,
        cores: cores)
}

private let busyChrome = [
    ProcessSample(pid: 760, cpu: 120, memoryBytes: 400, command: chrome),
    ProcessSample(pid: 761, cpu: 80, memoryBytes: 300, command: chromeHelper),
]

@Suite("CPU scale")
struct CpuScaleTests {
    @Test("shows a row's CPU as a share of all cores")
    func wholeMachine() {
        let rows = buildPanelView(snapshot(cores: 8, busyChrome), refreshSeconds: 3).rows
        #expect(rows.first?.cpu == "25.0%")
    }

    @Test("never shows a row above 100 % when every core is busy")
    func neverAbove100() {
        let rows = buildPanelView(snapshot(cores: 2, busyChrome), refreshSeconds: 3).rows
        #expect(rows.first?.cpu == "100.0%")
    }

    @Test("keeps one core's scale for a snapshot built without a core count")
    func defaultIsOneCore() {
        let s = Snapshot(takenAt: Date(timeIntervalSince1970: 0),
                         memory: MemoryReading(totalBytes: 1000, freeBytes: 100, usedBytes: 700, wiredBytes: 100,
                                               compressedBytes: 50, swapUsedBytes: 0, pressure: .normal),
                         cpuPercent: 30, processes: busyChrome)
        #expect(s.cores == 1)
        #expect(buildPanelView(s, refreshSeconds: 3).rows.first?.cpu == "200.0%")
    }

    @Test("collects the Mac's core count into the snapshot")
    func realCores() throws {
        var collector = try Collector()
        Thread.sleep(forTimeInterval: 0.2)
        let snap = try collector.collect()
        #expect(snap.cores == ProcessInfo.processInfo.processorCount)
    }
}
