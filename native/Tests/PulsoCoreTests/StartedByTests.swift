// Tests for showing who started a copy apart from the app's name, so the panel can cut a
// long name and still show "by Raycast" whole. The group keeps its full name for elsewhere.
import Foundation
import Testing
@testable import PulsoCore

private let chromeMain = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
private let raycastMain = "/Applications/Raycast.app/Contents/MacOS/Raycast"

private func proc(_ pid: Int32, _ command: String, _ bytes: UInt64, _ launcher: Int32, _ path: String) -> ProcessSample {
    ProcessSample(pid: pid, cpu: 0, memoryBytes: bytes, command: command, launcherPid: launcher, launcherPath: path)
}

private let twoCopies: [ProcessSample] = [
    proc(760, chromeMain, 400, 760, chromeMain),
    proc(800, chromeMain, 100, 5704, raycastMain),
]

private func snapshot(_ processes: [ProcessSample]) -> Snapshot {
    Snapshot(
        takenAt: Date(timeIntervalSince1970: 0),
        memory: MemoryReading(totalBytes: 1000, freeBytes: 100, usedBytes: 700, wiredBytes: 100,
                              compressedBytes: 50, swapUsedBytes: 0, pressure: .normal),
        cpuPercent: 0,
        processes: processes)
}

@Suite("Started by")
struct StartedByTests {
    @Test("records the starter on the copy another app started, and nothing on the user's")
    func onGroup() {
        let groups = groupByApp(twoCopies)
        #expect(groups[0].startedBy == nil)
        #expect(groups[1].startedBy == "Raycast")
        #expect(groups[1].name == "Google Chrome · Raycast")
    }

    @Test("gives the row the app's own name and the starter apart")
    func onRow() {
        let rows = buildPanelView(snapshot(twoCopies), refreshSeconds: 3).rows
        #expect(rows[0].name == "Google Chrome")
        #expect(rows[0].startedBy == nil)
        #expect(rows[1].name == "Chrome")
        #expect(rows[1].startedBy == "Raycast")
    }

    @Test("leaves a lone copy without a starter, like any other app")
    func alone() {
        let rows = buildPanelView(snapshot([twoCopies[1]]), refreshSeconds: 3).rows
        #expect(rows.first?.name == "Google Chrome")
        #expect(rows.first?.startedBy == nil)
    }
}
