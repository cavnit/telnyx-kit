import Vapor

/// Why a webhook was rejected.
///
/// As an `AbortError`: signature and timestamp failures are 401, a missing or undecodable body is
/// 400, and a missing or invalid configured public key is 500. Reasons never echo header or body values.
public enum TelnyxWebhookError: Error, Sendable, Equatable {
    /// No public key is configured (`TelnyxConfiguration.publicKey` is `nil`).
    case publicKeyNotConfigured
    /// The configured public key is not base64 of a 32-byte Ed25519 key or a 44-byte Ed25519 SPKI key.
    case invalidPublicKey
    /// The `telnyx-signature-ed25519` header is missing or empty.
    case missingSignature
    /// The `telnyx-signature-ed25519` header is not base64 of a 64-byte signature.
    case malformedSignature
    /// The `telnyx-timestamp` header is missing or empty.
    case missingTimestamp
    /// The `telnyx-timestamp` header is not an integer number of Unix seconds.
    case malformedTimestamp
    /// The timestamp is older than the tolerance allows.
    case staleTimestamp
    /// The timestamp is further in the future than the tolerance allows.
    case futureTimestamp
    /// The signature does not match the body and timestamp for the configured key.
    case invalidSignature
    /// The request has no body.
    case missingBody
    /// The body was correctly signed but is not a Telnyx event envelope. The associated value
    /// names the failing coding path, never body content.
    case malformedEvent(String)
}

extension TelnyxWebhookError: AbortError {
    public var status: HTTPResponseStatus {
        switch self {
        case .publicKeyNotConfigured, .invalidPublicKey:
            return .internalServerError
        case .missingSignature, .malformedSignature, .missingTimestamp, .malformedTimestamp,
             .staleTimestamp, .futureTimestamp, .invalidSignature:
            return .unauthorized
        case .missingBody, .malformedEvent:
            return .badRequest
        }
    }

    public var reason: String {
        switch self {
        case .publicKeyNotConfigured:
            return "Telnyx webhook public key is not configured"
        case .invalidPublicKey:
            return "Telnyx webhook public key is invalid"
        case .missingSignature:
            return "Missing telnyx-signature-ed25519 header"
        case .malformedSignature:
            return "Malformed telnyx-signature-ed25519 header"
        case .missingTimestamp:
            return "Missing telnyx-timestamp header"
        case .malformedTimestamp:
            return "Malformed telnyx-timestamp header"
        case .staleTimestamp:
            return "Telnyx webhook timestamp is too old"
        case .futureTimestamp:
            return "Telnyx webhook timestamp is in the future"
        case .invalidSignature:
            return "Invalid Telnyx webhook signature"
        case .missingBody:
            return "Telnyx webhook has no body"
        case .malformedEvent:
            return "Telnyx webhook body is not a valid event"
        }
    }
}
