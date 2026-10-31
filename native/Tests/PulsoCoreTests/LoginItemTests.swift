// Tests for Open at Login: on by default the first time Pulso
// runs, then the user's choice wins, whether made in Pulso or in System Settings. Pulso never
// turns it back on by itself.
import Testing
@testable import PulsoCore

@Suite("Open at Login")
struct LoginItemTests {
    @Test("turns itself on at the first launch only")
    func firstLaunch() {
        #expect(loginStepAtLaunch(decided: false) == .register)
        #expect(loginStepAtLaunch(decided: true) == .none)
    }

    @Test("reads as on while enabled or waiting for the user's approval")
    func isOn() {
        #expect(loginIsOn(.enabled))
        #expect(loginIsOn(.requiresApproval))
        #expect(!loginIsOn(.notRegistered))
        #expect(!loginIsOn(.notFound))
    }

    @Test("the menu item turns it off when on, and on when off")
    func toggle() {
        #expect(loginStepOnToggle(.enabled) == .unregister)
        #expect(loginStepOnToggle(.requiresApproval) == .unregister)
        #expect(loginStepOnToggle(.notRegistered) == .register)
        #expect(loginStepOnToggle(.notFound) == .register)
    }
}
