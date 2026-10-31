// Tests for the short app name used beside "by …", so "Chrome by Raycast" fits whole. Only a
// leading vendor word from a short known list is dropped; any other name stays as it is.
import Testing
@testable import PulsoCore

@Suite("withoutVendor")
struct WithoutVendorTests {
    @Test("drops a known vendor word in front of the app's name")
    func knownVendors() {
        #expect(withoutVendor("Google Chrome") == "Chrome")
        #expect(withoutVendor("Microsoft Edge") == "Edge")
        #expect(withoutVendor("Mozilla Firefox") == "Firefox")
        #expect(withoutVendor("Adobe Photoshop 2025") == "Photoshop 2025")
    }

    @Test("leaves every other name alone")
    func others() {
        #expect(withoutVendor("Brave Browser") == "Brave Browser")
        #expect(withoutVendor("Visual Studio Code") == "Visual Studio Code")
        #expect(withoutVendor("Slack") == "Slack")
        #expect(withoutVendor("Google") == "Google")
        #expect(withoutVendor("Googler App") == "Googler App")
    }
}
