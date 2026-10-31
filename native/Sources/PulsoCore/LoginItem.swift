// Open at Login: Pulso turns it on at its first launch only, then the user's choice wins.
import Foundation

/// The login item's state as macOS reports it (mirrors SMAppService.Status).
public enum LoginItemStatus: Equatable, Sendable { case enabled, requiresApproval, notRegistered, notFound }

/// What to do with the login item.
public enum LoginStep: Equatable, Sendable { case register, unregister, none }

// Pulso applies its default only the first time it runs; once it has, the user's choice wins.
public func loginStepAtLaunch(decided: Bool) -> LoginStep {
    decided ? .none : .register
}

// Approved, or still awaiting the user's System Settings approval, counts as on.
public func loginIsOn(_ status: LoginItemStatus) -> Bool {
    switch status {
    case .enabled, .requiresApproval: return true
    default: return false
    }
}

// On it goes off; off it goes on, whether Pulso or the user set it.
public func loginStepOnToggle(_ status: LoginItemStatus) -> LoginStep {
    loginIsOn(status) ? .unregister : .register
}
