// Tests for formatBytes and shortName, translated one to one from the TypeScript
// contract in src/main/metrics.test.ts.
import Testing
@testable import PulsoCore

@Suite("shortName")
struct ShortNameTests {
    @Test("keeps the last segment of the path")
    func lastSegment() {
        #expect(shortName("/usr/libexec/mediaanalysisd") == "mediaanalysisd")
        #expect(shortName("/sbin/launchd") == "launchd")
    }

    @Test("unwraps macOS bundles to the app name")
    func bundles() {
        #expect(shortName("/Applications/Chrome.app/Contents/MacOS/Chrome") == "Chrome")
    }

    @Test("leaves an already short command alone")
    func alreadyShort() {
        #expect(shortName("node") == "node")
        #expect(shortName("") == "")
    }

    @Test("truncates very long names so they fit a menu row")
    func truncates() {
        let long = "/usr/bin/" + String(repeating: "a", count: 80)
        #expect(shortName(long).count <= 32)
    }
}

@Suite("formatBytes")
struct FormatBytesTests {
    @Test("picks the largest unit that keeps the number readable")
    func units() {
        #expect(formatBytes(0) == "0 B")
        #expect(formatBytes(512) == "512 B")
        #expect(formatBytes(1024) == "1.0 KB")
        #expect(formatBytes(1536) == "1.5 KB")
        #expect(formatBytes(1024 * 1024) == "1.0 MB")
        #expect(formatBytes(2_684_354_560) == "2.5 GB")
    }

    @Test("uses a period as the decimal separator (the UI is English)")
    func period() {
        #expect(formatBytes(1_610_612_736) == "1.5 GB")
        #expect(!formatBytes(1_610_612_736).contains(","))
    }
}
