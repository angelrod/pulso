// Integration tests for reading memory natively (no vm_stat), checked against what
// vm_stat and sysctl report at the same moment. Memory moves between the two readings,
// so values are compared within 1 % of total memory.
import Foundation
import Testing
@testable import PulsoCore

private func run(_ path: String, _ args: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    var env = ProcessInfo.processInfo.environment
    env["LC_ALL"] = "C"
    process.environment = env
    let pipe = Pipe()
    process.standardOutput = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// The same reading the Electron app takes, done here as the reference.
private struct Reference {
    let total: UInt64, free: UInt64, used: UInt64, wired: UInt64, compressed: UInt64
    let swapUsed: UInt64, pressure: String

    static func take() throws -> Reference {
        let vm = try run("/usr/bin/vm_stat", [])
        let sys = try run("/usr/sbin/sysctl", ["-n", "hw.memsize", "kern.memorystatus_vm_pressure_level", "vm.swapusage"])
            .split(separator: "\n").map(String.init)
        let pageSize = UInt64(vm.firstMatch(of: /page size of (\d+) bytes/)!.1)!
        func pages(_ label: String) -> UInt64 {
            let line = vm.split(separator: "\n").first { $0.hasPrefix(label + ":") }!
            return UInt64(line.split(separator: ":")[1].trimmingCharacters(in: .whitespaces).dropLast())!
        }
        let swapMatch = sys[2].firstMatch(of: /used = ([\d.]+)([MG])/)!
        let swapUnit: Double = swapMatch.2 == "G" ? 1024 * 1024 * 1024 : 1024 * 1024
        return Reference(
            total: UInt64(sys[0])!,
            free: pages("Pages free") * pageSize,
            used: (pages("Anonymous pages") - pages("Pages purgeable") + pages("Pages wired down")
                + pages("Pages occupied by compressor")) * pageSize,
            wired: pages("Pages wired down") * pageSize,
            compressed: pages("Pages occupied by compressor") * pageSize,
            swapUsed: UInt64((Double(swapMatch.1)! * swapUnit).rounded()),
            pressure: ["1": "normal", "2": "warning", "4": "critical"][sys[1]]!
        )
    }
}

private func close(_ a: UInt64, _ b: UInt64, of total: UInt64) -> Bool {
    let diff = a > b ? a - b : b - a
    return Double(diff) <= Double(total) * 0.01
}

@Suite("readMemory")
struct MemoryTests {
    @Test("reports the machine's total memory exactly")
    func total() throws {
        let native = try readMemory()
        let ref = try Reference.take()
        #expect(native.totalBytes == ref.total)
    }

    @Test("matches vm_stat's used, wired, compressed and free within 1 % of total")
    func pages() throws {
        let native = try readMemory()
        let ref = try Reference.take()
        #expect(close(native.usedBytes, ref.used, of: ref.total), "used \(native.usedBytes) vs \(ref.used)")
        #expect(close(native.wiredBytes, ref.wired, of: ref.total), "wired \(native.wiredBytes) vs \(ref.wired)")
        #expect(close(native.compressedBytes, ref.compressed, of: ref.total), "compressed \(native.compressedBytes) vs \(ref.compressed)")
        #expect(close(native.freeBytes, ref.free, of: ref.total), "free \(native.freeBytes) vs \(ref.free)")
    }

    @Test("matches sysctl's swap used within 1 % of total, and its pressure level")
    func swapAndPressure() throws {
        let native = try readMemory()
        let ref = try Reference.take()
        #expect(close(native.swapUsedBytes, ref.swapUsed, of: ref.total), "swap \(native.swapUsedBytes) vs \(ref.swapUsed)")
        #expect(native.pressure.rawValue == ref.pressure)
    }

    @Test("keeps used below total and the percentage in range")
    func sane() throws {
        let native = try readMemory()
        #expect(native.usedBytes <= native.totalBytes)
        #expect(native.usedPercent > 0 && native.usedPercent <= 100)
        #expect(abs(native.usedPercent - Double(native.usedBytes) / Double(native.totalBytes) * 100) < 1e-9)
    }

    @Test("takes well under a millisecond per reading on average")
    func fast() throws {
        let start = Date()
        for _ in 0..<100 { _ = try readMemory() }
        #expect(Date().timeIntervalSince(start) / 100 < 0.001)
    }
}
