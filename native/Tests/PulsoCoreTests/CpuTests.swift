// Tests for CPU usage: cpuPercent translated one to one from the TypeScript contract in
// src/main/metrics.test.ts, plus integration tests for the native tick reader.
// The kernel reports user, system, idle and nice ticks per core; there is no irq
// counter as in os.cpus(), so the TypeScript irq case is folded into nice.
import Foundation
import Testing
@testable import PulsoCore

private func core(_ user: UInt64, _ nice: UInt64, _ system: UInt64, _ idle: UInt64) -> CpuTimes {
    CpuTimes(user: user, nice: nice, system: system, idle: idle)
}

@Suite("cpuPercent")
struct CpuPercentTests {
    @Test("is busy time over total time, across every core, between two readings")
    func busyOverTotal() throws {
        let prev = [core(100, 0, 50, 1000), core(200, 0, 0, 2000)]
        // Core 1: +20 user +10 system +70 idle. Core 2: +10 user +90 idle. Busy 40 of 200.
        let next = [core(120, 0, 60, 1070), core(210, 0, 0, 2090)]
        #expect(abs(try cpuPercent(prev, next) - 20) < 1e-10)
    }

    @Test("counts nice time as busy")
    func niceIsBusy() throws {
        #expect(abs(try cpuPercent([core(0, 0, 0, 0)], [core(0, 50, 0, 50)]) - 50) < 1e-10)
    }

    @Test("reads 0 when no time has passed, rather than dividing by zero")
    func noTime() throws {
        let same = [core(10, 0, 10, 10)]
        #expect(try cpuPercent(same, same) == 0)
    }

    // Counters are sampled; one going backwards must neither crash nor leave 0–100.
    @Test("stays between 0 and 100, without crashing, even if a counter goes backwards")
    func backwards() throws {
        let pct = try cpuPercent([core(500, 0, 0, 100)], [core(100, 0, 0, 200)])
        #expect(pct >= 0 && pct <= 100)
    }

    @Test("refuses readings with different core counts")
    func coreCounts() {
        #expect(throws: (any Error).self) { try cpuPercent([core(0, 0, 0, 0)], []) }
    }
}

@Suite("readCpuTicks")
struct CpuReaderTests {
    @Test("reads one entry per logical core")
    func oneEntryPerCore() throws {
        #expect(try readCpuTicks().count == ProcessInfo.processInfo.processorCount)
    }

    @Test("never goes backwards between two readings")
    func monotonic() throws {
        let a = try readCpuTicks()
        Thread.sleep(forTimeInterval: 0.2)
        let b = try readCpuTicks()
        for (x, y) in zip(a, b) {
            #expect(y.user >= x.user && y.system >= x.system && y.idle >= x.idle && y.nice >= x.nice)
        }
    }

    @Test("tracks top within 15 points over the same second")
    func matchesTop() throws {
        let before = try readCpuTicks()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/top")
        process.arguments = ["-l", "2", "-n", "0", "-s", "1"]
        process.environment = ["LC_ALL": "C"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let after = try readCpuTicks()

        let line = try #require(out.split(separator: "\n").last { $0.hasPrefix("CPU usage") })
        let m = try #require(String(line).firstMatch(of: /([\d.]+)% user, ([\d.]+)% sys/))
        let top = Double(m.1)! + Double(m.2)!
        let native = try cpuPercent(before, after)
        #expect(abs(native - top) <= 15, "native \(native) vs top \(top)")
    }

    @Test("takes well under a millisecond per reading on average")
    func fast() throws {
        let start = Date()
        for _ in 0..<100 { _ = try readCpuTicks() }
        #expect(Date().timeIntervalSince(start) / 100 < 0.001)
    }
}
