// PulsoCore: attributes a process to the app responsible for it, via a private API.
import Foundation
import Darwin

// The private attribution symbol, resolved once; nil if the API is absent on this macOS.
private struct Responsible {
    static let symbol: (@convention(c) (pid_t) -> pid_t)? = {
        let defaultImage = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(defaultImage, "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()
}

// The process responsible for this one, or nil for a missing result or absent API.
public func responsiblePid(_ pid: Int32) -> Int32? {
    guard let symbol = Responsible.symbol else { return nil }
    let result = symbol(pid)
    guard result > 0 else { return nil }
    return result
}
