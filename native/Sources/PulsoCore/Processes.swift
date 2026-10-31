// PulsoCore: the user's own process list — the Activity Monitor footprint and total CPU time.
import Foundation
@preconcurrency import Darwin

/// One process: the executable's path, the footprint Activity Monitor shows, and total CPU time.
public struct ProcessReading: Equatable, Sendable {
    public let pid: Int32
    public let path: String
    public let footprintBytes: UInt64
    public let cpuTimeNanos: UInt64
}

// The path a process was started from, read from the kernel's process arguments.
public func execPath(_ pid: Int32) -> String? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 4 else { return nil }
    var buf = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0, size > 4 else { return nil }
    let end = buf[4..<size].firstIndex(of: 0) ?? size
    return String(decoding: buf[4..<end], as: UTF8.self)
}

// Keep the start path only when the kernel's path left the app and the start path is in one.
public func preferredPath(pidPath: String, execPath: String?) -> String {
    guard bundlePathOf(pidPath) == nil, let exec = execPath, bundlePathOf(exec) != nil else { return pidPath }
    return exec
}

// Mach time units are not nanoseconds; read the conversion once, falling back if unreadable.
private func machTimebase() -> (numer: UInt64, denom: UInt64) {
    var info = mach_timebase_info_data_t()
    _ = mach_timebase_info(&info)
    return (UInt64(info.numer), info.denom == 0 ? 1 : UInt64(info.denom))
}

// Convert Mach time units to nanoseconds; the multiply can overflow UInt64, so report and saturate.
private func machToNanos(_ units: UInt64, _ tb: (numer: UInt64, denom: UInt64)) -> UInt64 {
    let (product, overflow) = units.multipliedReportingOverflow(by: tb.numer)
    return overflow ? .max : product / tb.denom
}

// Processes come and go between calls, so size the buffer a little larger than the count.
private func allPids() -> [Int32] {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else { return [] }
    let slots = Int(count) + 32
    var buffer = [Int32](repeating: 0, count: slots)
    let written = buffer.withUnsafeMutableBufferPointer { bp in
        proc_listallpids(UnsafeMutableRawPointer(bp.baseAddress!), Int32(slots * MemoryLayout<Int32>.size))
    }
    guard written > 0 else { return [] }
    return Array(buffer.prefix(Int(written)))
}

// proc_pidpath writes a C string; a length ≤ 0 means no path to read for this pid.
private func processPath(_ pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let size = buffer.count
    let len = buffer.withUnsafeMutableBufferPointer { bp in
        proc_pidpath(pid, bp.baseAddress!, UInt32(size))
    }
    guard len > 0 else { return nil }
    return String(cString: &buffer)
}

// RUSAGE_INFO_V4 takes the struct's address rebound to rusage_info_t?; EPERM means skip it.
private func usage(_ pid: Int32) -> (footprint: UInt64, cpuTime: UInt64)? {
    var info = rusage_info_v4()
    let rc = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    guard rc == 0 else { return nil }
    return (info.ri_phys_footprint, info.ri_user_time + info.ri_system_time)
}

// pid 0 is not a process; unreadable ones (EPERM) are skipped so the list holds only real readings.
public func readProcesses() throws -> [ProcessReading] {
    let timebase = machTimebase()
    let pids = allPids()
    var readings: [ProcessReading] = []
    for pid in pids {
        guard pid != 0, let info = usage(pid), let path = processPath(pid) else { continue }
        // Read the start path only when the kernel path left its app but still names an app folder.
        let finalPath = bundlePathOf(path) == nil && path.contains(".app") ? preferredPath(pidPath: path, execPath: execPath(pid)) : path
        readings.append(ProcessReading(pid: pid, path: finalPath, footprintBytes: info.footprint, cpuTimeNanos: machToNanos(info.cpuTime, timebase)))
    }
    return readings
}

// Only pids in both readings count; a backwards counter gives 0, no elapsed time gives nothing.
public func processCpuPercent(prev: [Int32: UInt64], next: [Int32: UInt64], elapsedNanos: UInt64) -> [Int32: Double] {
    guard elapsedNanos > 0 else { return [:] }
    var result: [Int32: Double] = [:]
    for (pid, nextCpu) in next {
        guard let prevCpu = prev[pid] else { continue }
        let gained = nextCpu >= prevCpu ? nextCpu - prevCpu : 0
        result[pid] = Double(gained) / Double(elapsedNanos) * 100
    }
    return result
}
