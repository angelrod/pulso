// PulsoCore: read memory straight from the kernel, replacing the vm_stat/sysctl parse.
import Foundation
import MachO

/// The kernel's memory pressure tier, read from kern.memorystatus_vm_pressure_level.
public enum Pressure: String, Sendable { case normal, warning, critical }

/// A point-in-time memory snapshot, matching the shape vm_stat and sysctl report.
public struct MemoryReading: Equatable, Sendable {
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let usedBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressure: Pressure

    /// Percentage of total memory accounted for by used bytes.
    public var usedPercent: Double {
        Double(usedBytes) / Double(totalBytes) * 100
    }
}

private struct MemoryError: Error { let message: String }

// Counters are sampled not atomic; saturate at zero so a transient reading crashes nothing.
private func saturate(_ a: UInt64, _ b: UInt64) -> UInt64 { a > b ? a - b : 0 }

// host_statistics64 fills this struct by name; rebind the pointer to integer_t for the call.
private func hostVmInfo64() throws -> vm_statistics64 {
    var stats = vm_statistics64()
    var count = Int32(MemoryLayout<vm_statistics64>.size / MemoryLayout<Int32>.stride)
    let rc = withUnsafeMutablePointer(to: &stats) { statsPtr in
        statsPtr.withMemoryRebound(to: Int32.self, capacity: Int(count)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
        }
    }
    guard rc == KERN_SUCCESS else {
        throw MemoryError(message: "host_statistics64: \(mach_error_string(rc))")
    }
    return stats
}

// sysctlbyname reports swap usage (an xsw_usage struct) and the pressure level (an int).
private func swapUsedBytes() throws -> UInt64 {
    var usage = xsw_usage()
    var len = Int(MemoryLayout<xsw_usage>.size)
    guard sysctlbyname("vm.swapusage", &usage, &len, nil, 0) == 0 else {
        throw MemoryError(message: "sysctlbyname vm.swapusage")
    }
    return UInt64(usage.xsu_used)
}

// The pressure kernel variable is one of 1/2/4; anything else is a new tier we reject.
private func pressureLevel() throws -> Pressure {
    var level: Int32 = -1
    var len = Int(MemoryLayout<Int32>.size)
    guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &len, nil, 0) == 0 else {
        throw MemoryError(message: "sysctlbyname kern.memorystatus_vm_pressure_level")
    }
    switch level {
    case 1: return .normal
    case 2: return .warning
    case 4: return .critical
    default: throw MemoryError(message: "unknown memorystatus pressure level \(level)")
    }
}

// Reads total RAM, the live page counts, swap usage and pressure tier in one pass.
public func readMemory() throws -> MemoryReading {
    var ps: Int32 = 0
    var len = Int(MemoryLayout<Int32>.size)
    guard sysctlbyname("vm.pagesize", &ps, &len, nil, 0) == 0, ps > 0 else {
        throw MemoryError(message: "sysctlbyname vm.pagesize")
    }
    let psSize = UInt64(ps)
    var totalBytes: UInt64 = 0
    var len2 = Int(MemoryLayout<UInt64>.size)
    guard sysctlbyname("hw.memsize", &totalBytes, &len2, nil, 0) == 0, totalBytes > 0 else {
        throw MemoryError(message: "sysctlbyname hw.memsize")
    }

    let stats = try hostVmInfo64()
    let anonymous = UInt64(stats.internal_page_count)
    let purgeable = UInt64(stats.purgeable_count)
    let wiredPages = UInt64(stats.wire_count)
    let wired = wiredPages * psSize
    let compressor = UInt64(stats.compressor_page_count) * psSize
    let free = saturate(UInt64(stats.free_count), UInt64(stats.speculative_count)) * psSize
    let used = (saturate(anonymous, purgeable) + wiredPages + UInt64(stats.compressor_page_count)) * psSize

    return MemoryReading(
        totalBytes: totalBytes,
        freeBytes: free,
        usedBytes: used,
        wiredBytes: wired,
        compressedBytes: compressor,
        swapUsedBytes: try swapUsedBytes(),
        pressure: try pressureLevel())
}
