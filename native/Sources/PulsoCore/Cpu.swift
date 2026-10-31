// PulsoCore: CPU layer — port metrics.cpuPercent and read kernel tick counters.
import Foundation
@preconcurrency import Darwin

/// One core's tick counters since boot; no irq counter as os.cpus(), so irq folds into nice.
public struct CpuTimes: Equatable, Sendable {
    public let user: UInt64
    public let nice: UInt64
    public let system: UInt64
    public let idle: UInt64

    public init(user: UInt64, nice: UInt64, system: UInt64, idle: UInt64) {
        self.user = user
        self.nice = nice
        self.system = system
        self.idle = idle
    }
}

/// A whole machine's counters, one entry per core in core order.
public typealias CpuSample = [CpuTimes]

// Sampled counters can run backwards; a saturating subtraction never crashes.
func saturatingDiff(_ after: UInt64, _ before: UInt64) -> UInt64 {
    after >= before ? after - before : 0
}

/// CPU usage as busy time over total time, summed across every core between two readings.
public func cpuPercent(_ prev: CpuSample, _ next: CpuSample) throws -> Double {
    guard prev.count == next.count else {
        throw CpuError(message: "samples have different core counts: \(prev.count) and \(next.count)")
    }
    var busy: UInt64 = 0
    var total: UInt64 = 0
    for (p, n) in zip(prev, next) {
        let busyBefore = p.user + p.nice + p.system
        let totalBefore = busyBefore + p.idle
        let busyAfter = n.user + n.nice + n.system
        let totalAfter = busyAfter + n.idle
        busy += saturatingDiff(busyAfter, busyBefore)
        total += saturatingDiff(totalAfter, totalBefore)
    }
    guard total > 0 else { return 0 }
    let percent = Double(busy) / Double(total) * 100
    return min(100, max(0, percent))
}

// The kernel's tick-counter read fails on error; report why the read failed.
struct CpuError: Error {
    let message: String
}

/// Reads each core's tick counters straight from the kernel with no process spawned.
public func readCpuTicks() throws -> CpuSample {
    var cpuCount: natural_t = 0
    var infoCount: natural_t = 0
    var info: processor_info_array_t?
    let status = host_processor_info(
        mach_host_self(),
        PROCESSOR_CPU_LOAD_INFO,
        &cpuCount,
        &info,
        &infoCount)
    guard status == KERN_SUCCESS, let info else {
        throw CpuError(message: "host_processor_info failed with \(mach_error_string(status))")
    }
    var result: CpuSample = []
    result.reserveCapacity(Int(cpuCount))
    // The kernel returns a typed integer_t array, one CPU_STATE_MAX block per core.
    let values = UnsafePointer<integer_t>(info)!
    let perCore = Int(CPU_STATE_MAX)
    for core in 0..<Int(cpuCount) {
        let offset = core * perCore
        let user = UInt64(UInt32(bitPattern: values[offset + Int(CPU_STATE_USER)]))
        let system = UInt64(UInt32(bitPattern: values[offset + Int(CPU_STATE_SYSTEM)]))
        let idle = UInt64(UInt32(bitPattern: values[offset + Int(CPU_STATE_IDLE)]))
        let nice = UInt64(UInt32(bitPattern: values[offset + Int(CPU_STATE_NICE)]))
        result.append(CpuTimes(user: user, nice: nice, system: system, idle: idle))
    }
    vm_deallocate(
        mach_task_self_,
        vm_address_t(bitPattern: info),
        vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
    return result
}
