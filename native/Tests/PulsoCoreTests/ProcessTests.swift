// Tests for the native process list: the user's own processes, with the memory
// footprint Activity Monitor shows, checked against ps; and per-process CPU from the
// change in CPU time between two readings.
@preconcurrency import Darwin
import Foundation
import Testing
@testable import PulsoCore

private func ps(_ args: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = args
    process.environment = ["LC_ALL": "C"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return out
}

private func ownFootprint() -> UInt64 {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return info.phys_footprint
}

@Suite("readProcesses")
struct ReadProcessesTests {
    @Test("includes this process, with its executable path and its footprint")
    func includesSelf() throws {
        let me = ProcessInfo.processInfo.processIdentifier
        let mine = try #require(try readProcesses().first { $0.pid == me })
        #expect(mine.path == (CommandLine.arguments[0] as NSString).resolvingSymlinksInPath
            || mine.path.hasSuffix("/" + ((CommandLine.arguments[0] as NSString).lastPathComponent)))
        // readProcesses itself allocates between the two readings: allow 10 % or 4 MB.
        let reference = Double(ownFootprint())
        let tolerance = max(reference * 0.10, 4 * 1024 * 1024)
        #expect(abs(Double(mine.footprintBytes) - reference) <= tolerance, "\(mine.footprintBytes) vs \(reference)")
    }

    @Test("sees the user's own processes that ps sees, with the same paths")
    func matchesPs() throws {
        let uid = String(getuid())
        let reference = try ps(["-U", uid, "-o", "pid=,comm="])
            .split(separator: "\n")
            .compactMap { line -> (Int32, String)? in
                let s = line.trimmingCharacters(in: .whitespaces)
                guard let space = s.firstIndex(of: " "), let pid = Int32(s[..<space]) else { return nil }
                return (pid, s[space...].trimmingCharacters(in: .whitespaces))
            }
        let native = Dictionary(try readProcesses().map { ($0.pid, $0.path) }, uniquingKeysWith: { a, _ in a })
        let seen = reference.filter { native[$0.0] != nil }
        // Processes start and stop between the two readings; allow 5 % churn.
        #expect(Double(seen.count) >= Double(reference.count) * 0.95, "\(seen.count) of \(reference.count)")
        // ps shows the path as launched (through framework symlinks such as
        // Foo.framework/Support); the kernel gives the resolved one (Versions/A/Support).
        let resolved = { (path: String) in URL(fileURLWithPath: path).resolvingSymlinksInPath().path }
        let samePath = seen.filter { pid, comm in
            comm.hasPrefix("/") ? native[pid].map(resolved) == resolved(comm) : true
        }
        #expect(Double(samePath.count) >= Double(seen.count) * 0.95, "\(samePath.count) of \(seen.count) paths match")
    }

    @Test("gives a positive footprint for nearly every process it lists")
    func footprints() throws {
        let all = try readProcesses()
        #expect(!all.isEmpty)
        #expect(Double(all.filter { $0.footprintBytes > 0 }.count) >= Double(all.count) * 0.95)
    }

    // On Apple silicon the kernel counts CPU time in timebase ticks, not nanoseconds.
    @Test("measures CPU time in nanoseconds: burning 0.2 s of CPU shows at least 0.1 s")
    func cpuTimeUnits() throws {
        let me = ProcessInfo.processInfo.processIdentifier
        let before = try #require(try readProcesses().first { $0.pid == me }).cpuTimeNanos
        let end = Date().addingTimeInterval(0.2)
        var x = 0.0
        while Date() < end { x += sin(x + 1) }
        #expect(x != .infinity)
        let after = try #require(try readProcesses().first { $0.pid == me }).cpuTimeNanos
        #expect(after - before >= 100_000_000, "grew \(after - before) ns for 0.2 s of work")
        #expect(after - before <= 2_000_000_000, "grew \(after - before) ns for 0.2 s of work")
    }

    @Test("takes under 20 ms per reading on average")
    func fast() throws {
        let start = Date()
        for _ in 0..<10 { _ = try readProcesses() }
        #expect(Date().timeIntervalSince(start) / 10 < 0.020)
    }
}

@Suite("processCpuPercent")
struct ProcessCpuPercentTests {
    private let second: UInt64 = 1_000_000_000

    @Test("is CPU time over wall time, as a percentage of one core")
    func percentOfOneCore() {
        let pct = processCpuPercent(prev: [1: 0, 2: 0], next: [1: second / 2, 2: second * 2], elapsedNanos: second)
        #expect(abs(pct[1]! - 50) < 1e-9)
        #expect(abs(pct[2]! - 200) < 1e-9, "two cores' worth reads 200 %, as in Activity Monitor")
    }

    @Test("leaves out processes that were not in the previous reading")
    func newProcesses() {
        #expect(processCpuPercent(prev: [1: 0], next: [1: second, 3: second], elapsedNanos: second)[3] == nil)
    }

    @Test("never crashes on a counter going backwards, reading 0 instead")
    func backwards() {
        #expect(processCpuPercent(prev: [1: second], next: [1: 0], elapsedNanos: second)[1] == 0)
    }

    @Test("gives nothing when no time has passed")
    func noTime() {
        #expect(processCpuPercent(prev: [1: 0], next: [1: second], elapsedNanos: 0).isEmpty)
    }
}
