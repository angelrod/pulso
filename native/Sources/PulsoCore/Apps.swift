// PulsoCore: per-process grouping, mirroring groupByApp in src/main/metrics.ts.
import Foundation

/// A single process snapshot: its id, the two spendings tracked, and its command.
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    public let cpu: Double
    public let memoryBytes: UInt64
    public let command: String
    // The app that launched this process, if the private attribution API reported one.
    public let responsiblePath: String?
    // Who macOS holds responsible for this process, and that process's executable path.
    public let launcherPid: Int32?
    public let launcherPath: String?

    public init(pid: Int32, cpu: Double, memoryBytes: UInt64, command: String, responsiblePath: String? = nil, launcherPid: Int32? = nil, launcherPath: String? = nil) {
        self.pid = pid
        self.cpu = cpu
        self.memoryBytes = memoryBytes
        self.command = command
        self.responsiblePath = responsiblePath
        self.launcherPid = launcherPid
        self.launcherPath = launcherPath
    }
}

/// One app, or one outside-bundle command, with its summed spendings.
public struct AppGroup: Equatable, Sendable {
    public let name: String          // the outermost bundle's folder name without ".app"
    public let bundlePath: String?   // up to and including the outermost ".app", or nil
    public let pids: [Int32]
    public let mainPid: Int32?
    public let memoryBytes: UInt64      // sum over pids
    public let cpu: Double           // sum over pids
    // Who started a copy that shares the app's name, so the panel can keep "by Raycast" whole.
    public let startedBy: String?

    public init(name: String, bundlePath: String?, pids: [Int32], mainPid: Int32?, memoryBytes: UInt64, cpu: Double, startedBy: String? = nil) {
        self.name = name
        self.bundlePath = bundlePath
        self.pids = pids
        self.mainPid = mainPid
        self.memoryBytes = memoryBytes
        self.cpu = cpu
        self.startedBy = startedBy
    }
}

// Track each group's launcher key beside it, so two copies of one bundle separate.
struct GroupEntry {
    let group: AppGroup
    let launcherPid: Int32?
    let launcherPath: String?
}

// The outermost .app segment names the app, so scan for the first one from the left.
func bundlePathOf(_ command: String) -> String? {
    guard command.hasPrefix("/") else { return nil }
    let parts = command.split(separator: "/", omittingEmptySubsequences: false)
    if let index = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
        return parts.prefix(index + 1).joined(separator: "/")
    }
    return nil
}

// Takes the folder name the caller matched, minus its trailing ".app".
func appName(_ bundlePath: String) -> String {
    let folder = bundlePath.split(separator: "/").last.map(String.init) ?? ""
    return String(folder.dropLast(4))
}

// A main process runs straight from the app's own Contents/MacOS, not a helper bundle.
func isMain(_ command: String, _ bundlePath: String) -> Bool {
    let prefix = bundlePath + "/Contents/MacOS/"
    guard command.hasPrefix(prefix) else { return false }
    let rest = command.dropFirst(prefix.count)
    return !rest.isEmpty && !rest.contains("/")
}

// Outside-bundle commands each stay their own row, so quitting one never ends its twin.
public func groupByApp(_ processes: [ProcessSample]) -> [AppGroup] {
    var entries: [GroupEntry] = []
    for p in processes {
        // An XPC service outside any app is attributed to the responsible app's bundle.
        let bundlePath: String?
        if let responsibleBundle = xpcBundleOf(p) {
            bundlePath = responsibleBundle
        } else {
            bundlePath = bundlePathOf(p.command)
        }
        let foreign = p.launcherPath.map { bundlePathOf($0) != bundlePath } ?? false
        let launcher = foreign ? p.launcherPid : nil
        let launcherPath = bundlePath.flatMap { _ in p.launcherPath }
        guard let matched = bundlePath else {
            entries.append(GroupEntry(
                group: AppGroup(
                    name: shortName(p.command),
                    bundlePath: nil,
                    pids: [p.pid],
                    mainPid: p.pid,
                    memoryBytes: p.memoryBytes,
                    cpu: p.cpu),
                launcherPid: launcher,
                launcherPath: launcherPath))
            continue
        }
        if let i = entries.firstIndex(where: { $0.group.bundlePath == matched && $0.launcherPid == launcher }) {
            let existing = entries[i].group
            let isMainProc = existing.mainPid == nil && isMain(p.command, matched)
            entries[i] = GroupEntry(
                group: AppGroup(
                    name: existing.name,
                    bundlePath: existing.bundlePath,
                    pids: existing.pids + [p.pid],
                    mainPid: isMainProc ? p.pid : existing.mainPid,
                    memoryBytes: existing.memoryBytes + p.memoryBytes,
                    cpu: existing.cpu + p.cpu),
                launcherPid: launcher,
                launcherPath: launcherPath)
        } else {
            let isMainProc = isMain(p.command, matched)
            entries.append(GroupEntry(
                group: AppGroup(
                    name: appName(matched),
                    bundlePath: matched,
                    pids: [p.pid],
                    mainPid: isMainProc ? p.pid : nil,
                    memoryBytes: p.memoryBytes,
                    cpu: p.cpu),
                launcherPid: launcher,
                launcherPath: launcherPath))
        }
    }
    return renameCollisions(entries, in: processes).map { $0.group }
}

// The user's and a launcher-started copy share a name, so rename the launcher copy.
func renameCollisions(_ entries: [GroupEntry], in processes: [ProcessSample]) -> [GroupEntry] {
    let collisionNames = Dictionary(grouping: entries) { $0.group.name }
        .values.filter { $0.count > 1 }
        .flatMap { $0.map(\.group.name) }
    var result = entries
    for i in result.indices where collisionNames.contains(result[i].group.name) {
        guard let launcherPath = launcherPath(of: result[i], in: processes),
              bundlePathOf(launcherPath) != result[i].group.bundlePath else { continue }
        let starter = launcherName(launcherPath)
        let renamed = result[i].group
        result[i] = GroupEntry(
            group: AppGroup(
                name: "\(renamed.name) · \(starter)",
                bundlePath: renamed.bundlePath,
                pids: renamed.pids,
                mainPid: renamed.mainPid,
                memoryBytes: renamed.memoryBytes,
                cpu: renamed.cpu,
                startedBy: starter),
            launcherPid: result[i].launcherPid,
            launcherPath: result[i].launcherPath)
    }
    return result
}

// The launcher of the copy: its first process with a launcher path.
func launcherPath(of entry: GroupEntry, in processes: [ProcessSample]) -> String? {
    let withPath = entry.group.pids.compactMap { pid in processes.first { $0.pid == pid } }
        .first(where: { $0.launcherPath != nil })
    return withPath?.launcherPath
}

// The starter is named after its bundle when it lives in an app, else its command.
func launcherName(_ launcherPath: String) -> String {
    guard let launcherBundle = bundlePathOf(launcherPath) else { return shortName(launcherPath) }
    return appName(launcherBundle)
}

// XPC services outside any app are counted under the responsible app's outermost bundle.
func xpcBundleOf(_ p: ProcessSample) -> String? {
    guard bundlePathOf(p.command) == nil, p.command.contains(".xpc/") else { return nil }
    guard let responsible = p.responsiblePath else { return nil }
    return bundlePathOf(responsible)
}
