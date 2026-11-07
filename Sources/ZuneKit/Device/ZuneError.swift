public enum ZuneError: Error, Equatable, Sendable {
    case noDevice
    /// A libmtp call didn't return in time. The call can't be abandoned safely, so the app
    /// has to be quit and the Zune soft-reset.
    case deviceNotResponding(operation: String)
    case libmtp(operation: String, message: String)
    /// The Zune didn't confirm that a copy or delete happened.
    case verificationFailed(operation: String)
}
