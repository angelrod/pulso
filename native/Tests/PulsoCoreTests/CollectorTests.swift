// Tests for the Collector: one snapshot from every reader, keeping the previous CPU and
// per-process readings so each snapshot measures since the last one. Readers are
// injected; one integration test runs the real ones.
import Foundation
import Testing
@testable import PulsoCore

private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}

private func memoryReading() -> MemoryReading {
    MemoryReading(totalBytes: 1000, freeBytes: 100, usedBytes: 700, wiredBytes: 100,
                  compressedBytes: 50, swapUsedBytes: 0, pressure: .normal)
}

private let second: UInt64 = 1_000_000_000
private let safariApp = "/Applications/Safari.app/Contents/MacOS/Safari"
private let webContent = "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"

/// Fake readers that return the next scripted value on each call.
private struct Script {
    let cpu = Box<[CpuSample]>([])
    let processes = Box<[[ProcessReading]]>([])
    let clock = Box<[UInt64]>([])
    let responsibleCalls = Box<[Int32]>([])
    let responsibleMap: [Int32: Int32]

    init(responsibleMap: [Int32: Int32] = [:]) { self.responsibleMap = responsibleMap }

    var readers: Readers {
        Readers(
            memory: { memoryReading() },
            cpuTicks: {
                let next = self.cpu.value.removeFirst()
                return next
            },
            processes: {
                let next = self.processes.value.removeFirst()
                return next
            },
            responsible: { pid in
                self.responsibleCalls.value.append(pid)
                return self.responsibleMap[pid]
            },
            now: { Date(timeIntervalSince1970: 1_000_000) },
            monotonicNanos: {
                let next = self.clock.value.removeFirst()
                return next
            })
    }
}

private func core(busy: UInt64, idle: UInt64) -> CpuTimes {
    CpuTimes(user: busy, nice: 0, system: 0, idle: idle)
}

private func reading(_ pid: Int32, _ path: String, footprint: UInt64, cpuNanos: UInt64) -> ProcessReading {
    ProcessReading(pid: pid, path: path, footprintBytes: footprint, cpuTimeNanos: cpuNanos)
}

@Suite("Collector")
struct CollectorTests {
    @Test("measures the first snapshot from the readings taken when it was created")
    func firstFromBaseline() throws {
        let s = Script()
        s.cpu.value = [[core(busy: 0, idle: 0)], [core(busy: 30, idle: 70)]]
        s.processes.value = [
            [reading(5, "/bin/a", footprint: 10, cpuNanos: 0)],
            [reading(5, "/bin/a", footprint: 20, cpuNanos: second / 4)],
        ]
        s.clock.value = [0, second]
        var collector = try Collector(readers: s.readers)
        let snap = try collector.collect()
        #expect(abs(snap.cpuPercent - 30) < 1e-9)
        let a = try #require(snap.processes.first { $0.pid == 5 })
        #expect(abs(a.cpu - 25) < 1e-9)
        #expect(a.memoryBytes == 20)
        #expect(a.command == "/bin/a")
    }

    @Test("measures each later snapshot from the one before")
    func laterFromPrevious() throws {
        let s = Script()
        s.cpu.value = [[core(busy: 0, idle: 0)], [core(busy: 30, idle: 70)], [core(busy: 40, idle: 160)]]
        s.processes.value = [
            [reading(5, "/bin/a", footprint: 10, cpuNanos: 0)],
            [reading(5, "/bin/a", footprint: 10, cpuNanos: second)],
            [reading(5, "/bin/a", footprint: 10, cpuNanos: second + second / 2)],
        ]
        s.clock.value = [0, second, 2 * second]
        var collector = try Collector(readers: s.readers)
        _ = try collector.collect()
        let second2 = try collector.collect()
        #expect(abs(second2.cpuPercent - 10) < 1e-9)
        #expect(abs((second2.processes.first { $0.pid == 5 }?.cpu ?? -1) - 50) < 1e-9)
    }

    @Test("gives a new process 0 % CPU until it has a previous reading")
    func newProcess() throws {
        let s = Script()
        s.cpu.value = [[core(busy: 0, idle: 0)], [core(busy: 1, idle: 1)]]
        s.processes.value = [[], [reading(7, "/bin/new", footprint: 1, cpuNanos: second)]]
        s.clock.value = [0, second]
        var collector = try Collector(readers: s.readers)
        let snap = try collector.collect()
        #expect(snap.processes.first { $0.pid == 7 }?.cpu == 0)
    }

    @Test("passes memory and time through")
    func passThrough() throws {
        let s = Script()
        s.cpu.value = [[core(busy: 0, idle: 0)], [core(busy: 0, idle: 1)]]
        s.processes.value = [[], []]
        s.clock.value = [0, second]
        var collector = try Collector(readers: s.readers)
        let snap = try collector.collect()
        #expect(snap.memory == memoryReading())
        #expect(snap.takenAt == Date(timeIntervalSince1970: 1_000_000))
    }

    @Test("asks for the responsible process of XPC services only, and fills in its path")
    func responsibleForXpcOnly() throws {
        let s = Script(responsibleMap: [11: 10])
        s.cpu.value = [[core(busy: 0, idle: 0)], [core(busy: 0, idle: 1)]]
        let list = [
            reading(10, safariApp, footprint: 300, cpuNanos: 0),
            reading(11, webContent, footprint: 500, cpuNanos: 0),
            reading(12, "/usr/local/bin/node", footprint: 50, cpuNanos: 0),
        ]
        s.processes.value = [list, list]
        s.clock.value = [0, second]
        var collector = try Collector(readers: s.readers)
        let snap = try collector.collect()
        #expect(s.responsibleCalls.value == [11])
        #expect(snap.processes.first { $0.pid == 11 }?.responsiblePath == safariApp)
        #expect(snap.processes.first { $0.pid == 12 }?.responsiblePath == nil)
        let rows = buildPanelView(snap, refreshSeconds: 3).rows
        #expect(rows.map(\.name) == ["Safari", "node"])
    }

    @Test("runs the real readers: a sane snapshot that includes this process")
    func realReaders() throws {
        var collector = try Collector()
        Thread.sleep(forTimeInterval: 0.3)
        let snap = try collector.collect()
        #expect(snap.memory.totalBytes > 0)
        #expect(snap.cpuPercent >= 0 && snap.cpuPercent <= 100)
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(snap.processes.contains { $0.pid == me })
        // As measured in A2: nearly all, not all, processes report a positive footprint.
        let positive = snap.processes.filter { $0.memoryBytes > 0 }.count
        #expect(Double(positive) >= Double(snap.processes.count) * 0.95)
    }

    @Test("collects in under 20 ms on average with the real readers")
    func fast() throws {
        var collector = try Collector()
        let start = Date()
        for _ in 0..<10 { _ = try collector.collect() }
        #expect(Date().timeIntervalSince(start) / 10 < 0.020)
    }
}
