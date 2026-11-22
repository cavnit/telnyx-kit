import Foundation

/// Settings shared by every TelnyxKit area (numbers, messaging and webhooks).
///
/// Set it once in `configure.swift`:
///
/// ```swift
/// app.telnyx.configuration = TelnyxConfiguration(
///     apiKey: Environment.get("TELNYX_API_KEY") ?? "",
///     publicKey: Environment.get("TELNYX_PUBLIC_KEY")
/// )
/// ```
///
/// The API key is never included in `description`, `debugDescription` or the reflection mirror,
/// so printing or dumping a configuration does not leak it.
public struct TelnyxConfiguration: Sendable {
    /// The production API base URL, `https://api.telnyx.com/v2`.
    public static let productionBaseURL: String = "https://api.telnyx.com/v2"

    /// The sandbox API base URL, `https://api-sandbox.telnyx.com/v2`.
    public static let sandboxBaseURL: String = "https://api-sandbox.telnyx.com/v2"

    /// The default webhook timestamp tolerance: five minutes.
    public static let defaultWebhookTimestampTolerance: TimeInterval = 300

    /// The API key sent as `Authorization: Bearer <key>`.
    public let apiKey: String

    /// The API base URL, without a trailing slash.
    public let baseURL: String

    /// The base64 webhook signing public key from the Telnyx portal, if webhooks are used.
    ///
    /// Both the raw 32-byte Ed25519 key and the 44-byte SPKI (X.509 DER) form are accepted.
    public let publicKey: String?

    /// How far a webhook's `telnyx-timestamp` may be from the current time, in seconds,
    /// before the webhook is rejected. Applies to both stale and future timestamps.
    public let webhookTimestampTolerance: TimeInterval

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - apiKey: The Telnyx API key. Pass an empty string if only webhook verification is used.
    ///   - baseURL: The API base URL. Defaults to ``productionBaseURL``.
    ///   - publicKey: The base64 webhook signing public key, if webhooks are used.
    ///   - webhookTimestampTolerance: Allowed clock difference for webhook timestamps, in seconds.
    public init(
        apiKey: String,
        baseURL: String = TelnyxConfiguration.productionBaseURL,
        publicKey: String? = nil,
        webhookTimestampTolerance: TimeInterval = TelnyxConfiguration.defaultWebhookTimestampTolerance
    ) {
        self.apiKey = apiKey
        var trimmed: String = baseURL
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        self.baseURL = trimmed
        self.publicKey = publicKey
        self.webhookTimestampTolerance = webhookTimestampTolerance
    }
}

extension TelnyxConfiguration: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        let hasPublicKey: String = publicKey == nil ? "no" : "yes"
        return "TelnyxConfiguration(baseURL: \(baseURL), apiKey: <redacted>, publicKey: \(hasPublicKey), webhookTimestampTolerance: \(webhookTimestampTolerance))"
    }

    public var debugDescription: String {
        description
    }

    public var customMirror: Mirror {
        Mirror(
            self,
            children: [
                "baseURL": baseURL,
                "apiKey": "<redacted>",
                "publicKey": publicKey == nil ? "nil" : "<set>",
                "webhookTimestampTolerance": webhookTimestampTolerance,
            ],
            displayStyle: .struct
        )
    }
}
