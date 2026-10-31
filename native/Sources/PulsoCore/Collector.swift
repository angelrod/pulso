// PulsoCore: one Snapshot from every reader, keeping CPU and per-process readings between calls.
import Foundation
@preconcurrency import Darwin

// Every external read the Collector needs, injected so its pure logic is testable.
public struct Readers: Sendable {
    public let memory: @Sendable () throws -> MemoryReading
    public let cpuTicks: @Sendable () throws -> CpuSample
    public let processes: @Sendable () throws -> [ProcessReading]
    public let responsible: @Sendable (Int32) -> Int32?
    public let now: @Sendable () -> Date
    public let monotonicNanos: @Sendable () -> UInt64
    // The process macOS holds responsible, asked only for processes inside an app.
    public let launcher: @Sendable (Int32) -> Int32?
    // The process that started this one, for a copy's helper to follow its parent.
    public let parent: @Sendable (Int32) -> Int32?

    public init(
        memory: @escaping @Sendable () throws -> MemoryReading,
        cpuTicks: @escaping @Sendable () throws -> CpuSample,
        processes: @escaping @Sendable () throws -> [ProcessReading],
        responsible: @escaping @Sendable (Int32) -> Int32?,
        now: @escaping @Sendable () -> Date,
        monotonicNanos: @escaping @Sendable () -> UInt64,
        launcher: @escaping @Sendable (Int32) -> Int32? = { _ in nil },
        parent: @escaping @Sendable (Int32) -> Int32? = { _ in nil }
    ) {
        self.memory = memory
        self.cpuTicks = cpuTicks
        self.processes = processes
        self.responsible = responsible
        self.now = now
        self.monotonicNanos = monotonicNanos
        self.launcher = launcher
        self.parent = parent
    }
}

// The real readers, wired to the system calls, for the Collector's default.
extension Readers {
    public static let system = Readers(
        memory: readMemory,
        cpuTicks: readCpuTicks,
        processes: readProcesses,
        responsible: responsiblePid,
        now: { Date() },
        monotonicNanos: { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) },
        launcher: responsiblePid,
        parent: parentPid)
}

// The process that started this one, read from the kernel's process info.
func parentPid(_ pid: Int32) -> Int32? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return Int32(clamping: info.pbi_ppid)
}

// A process list between calls, keyed by pid, holding its footprint and CPU time.
private struct ProcessState {
    var footprint = [Int32: UInt64]()
    var cpuTime = [Int32: UInt64]()
}

// The state the Collector keeps between snapshots, so each reading has something to measure.
private struct State {
    var cpu: CpuSample
    var processes: ProcessState
    var now: UInt64
}

/// Turns every reader into one Snapshot, keeping CPU and per-process readings between calls.
public struct Collector: Sendable {
    private let readers: Readers
    private var state: State

    // Read a baseline right away, so the first collect() already has something to measure.
    public init(readers: Readers = .system) throws {
        self.readers = readers
        let cpu = try readers.cpuTicks()
        let processes = try Self.processState(readers.processes())
        let now = readers.monotonicNanos()
        self.state = State(cpu: cpu, processes: processes, now: now)
    }

    // One previous process list, keyed by pid, holding each process's footprint and CPU time.
    private static func processState(_ reading: [ProcessReading]) -> ProcessState {
        var state = ProcessState()
        for r in reading {
            state.footprint[r.pid] = r.footprintBytes
            state.cpuTime[r.pid] = r.cpuTimeNanos
        }
        return state
    }

    // Read memory, CPU, processes and time, computing deltas since the last collect().
    public mutating func collect() throws -> Snapshot {
        let memory = try readers.memory()
        let cpu = try readers.cpuTicks()
        let processes = try readers.processes()
        let now = readers.monotonicNanos()
        let prev = state.processes
        let next = Self.processState(processes)
        let cpuPercent = try cpuPercent(state.cpu, cpu)
        let perProcess = processCpuPercent(prev: prev.cpuTime, next: next.cpuTime, elapsedNanos: saturatingDiff(now, state.now))
        let snapshot = Snapshot(
            takenAt: readers.now(),
            memory: memory,
            cpuPercent: cpuPercent,
            processes: buildProcesses(processes, perProcess),
            cores: max(1, cpu.count))
        state = State(cpu: cpu, processes: next, now: now)
        return snapshot
    }

    // Build each row: a process inside an app carries its launcher, an XPC service its responsible.
    private func buildProcesses(_ processes: [ProcessReading], _ perProcess: [Int32: Double]) -> [ProcessSample] {
        var byPid = [Int32: ProcessSample]()
        var byPath = [Int32: String]()
        var xpcPids: [Int32] = []
        // Fill every path first, so a copy's launcher can be looked up regardless of list order.
        for r in processes {
            byPath[r.pid] = r.path
            byPid[r.pid] = ProcessSample(
                pid: r.pid,
                cpu: perProcess[r.pid] ?? 0,
                memoryBytes: r.footprintBytes,
                command: r.path,
                responsiblePath: nil)
            if r.path.contains(".xpc/") { xpcPids.append(r.pid) }
        }
        // A copy's launcher is its own start pid, so two copies of one bundle separate.
        for r in processes {
            guard let bundlePath = bundlePathOf(r.path), let launcherPid = readers.launcher(r.pid) else { continue }
            var nextLauncher = launcherPid
            var nextPath = byPath[launcherPid]
            // A helper answering to its own pid follows a copy another app launched of the app.
            if launcherPid == r.pid, !isMain(r.path, bundlePath),
               let parent = readers.parent(r.pid), bundlePathOf(byPath[parent] ?? "") == bundlePath,
               let parentLauncher = readers.launcher(parent) {
                nextLauncher = parentLauncher
                nextPath = byPath[parentLauncher]
            }
            byPid[r.pid] = ProcessSample(
                pid: r.pid, cpu: byPid[r.pid]!.cpu, memoryBytes: byPid[r.pid]!.memoryBytes,
                command: r.path, launcherPid: nextLauncher, launcherPath: nextPath)
        }
        // The responsible app is looked up in the same process list, so a missing pid is nil.
        for pid in xpcPids {
            guard let responsible = readers.responsible(pid), let row = byPid[pid] else { continue }
            byPid[pid] = ProcessSample(
                pid: pid, cpu: row.cpu, memoryBytes: row.memoryBytes, command: row.command,
                responsiblePath: byPath[responsible],
                launcherPid: readers.launcher(responsible), launcherPath: byPath[responsible])
        }
        return processes.map { byPid[$0.pid]! }
    }
}
