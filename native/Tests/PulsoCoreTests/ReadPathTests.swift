// Tests that the process list uses the start path when the kernel's path has left the app,
// checked on the real system: no listed process is outside an app if it was started in one.
import Darwin
import Foundation
import Testing
@testable import PulsoCore

@Suite("readProcesses: start paths")
struct ReadPathTests {
    @Test("lists no process outside an app when it was started inside one")
    func usesStartPath() throws {
        var outside: [String] = []
        for r in try readProcesses() where bundlePathOf(r.path) == nil {
            if let start = execPath(r.pid), bundlePathOf(start) != nil {
                outside.append("\(r.pid) \(r.path)")
            }
        }
        #expect(outside.isEmpty, "\(outside)")
    }
}
