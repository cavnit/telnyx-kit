import Crypto
import Foundation
import Vapor

/// Verifies Telnyx webhook signatures and decodes the events.
///
/// Telnyx signs `"{telnyx-timestamp}|{raw body}"` with Ed25519 and sends the base64 signature in
/// `telnyx-signature-ed25519`. Verification needs the exact bytes received, so pass the raw body,
/// not a re-encoded copy.
///
/// ```swift
/// let verifier: TelnyxWebhookVerifier = try TelnyxWebhookVerifier(base64PublicKey: key)
/// let event: TelnyxWebhookEvent = try verifier.verifiedEvent(
///     body: bodyBytes,
///     signature: signatureHeader,
///     timestamp: timestampHeader
/// )
/// ```
public struct TelnyxWebhookVerifier: Sendable {
    /// The signature header name.
    public static let signatureHeader: String = "telnyx-signature-ed25519"
    /// The timestamp header name.
    public static let timestampHeader: String = "telnyx-timestamp"

    /// The DER prefix of an Ed25519 SubjectPublicKeyInfo (RFC 8410): SEQUENCE, AlgorithmIdentifier
    /// with OID 1.3.101.112, then a 33-byte BIT STRING header; the 32 key bytes follow.
    static let spkiPrefix: [UInt8] = [0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00]

    public let publicKey: Curve25519.Signing.PublicKey
    /// Allowed difference between the webhook timestamp and `now`, in seconds, in either direction.
    public let tolerance: TimeInterval

    /// Creates a verifier from a public key.
    public init(publicKey: Curve25519.Signing.PublicKey, tolerance: TimeInterval = TelnyxConfiguration.defaultWebhookTimestampTolerance) {
        self.publicKey = publicKey
        self.tolerance = tolerance
    }

    /// Creates a verifier from the base64 public key shown in the Telnyx portal.
    ///
    /// Accepts either the raw 32-byte Ed25519 key or the 44-byte SPKI (X.509 DER) form, since
    /// Telnyx's examples disagree on which the portal shows.
    ///
    /// - Throws: ``TelnyxWebhookError/invalidPublicKey`` for anything else.
    public init(base64PublicKey: String, tolerance: TimeInterval = TelnyxConfiguration.defaultWebhookTimestampTolerance) throws {
        let trimmed: String = base64PublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decoded: Data = Data(base64Encoded: trimmed) else {
            throw TelnyxWebhookError.invalidPublicKey
        }
        let bytes: [UInt8] = Array(decoded)
        let raw: [UInt8]
        if bytes.count == 32 {
            raw = bytes
        } else if bytes.count == 44, Array(bytes.prefix(12)) == TelnyxWebhookVerifier.spkiPrefix {
            raw = Array(bytes.suffix(32))
        } else {
            throw TelnyxWebhookError.invalidPublicKey
        }
        do {
            let key: Curve25519.Signing.PublicKey = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
            self.init(publicKey: key, tolerance: tolerance)
        } catch {
            throw TelnyxWebhookError.invalidPublicKey
        }
    }

    /// Creates a verifier from ``TelnyxConfiguration/publicKey`` and its tolerance.
    ///
    /// - Throws: ``TelnyxWebhookError/publicKeyNotConfigured`` or ``TelnyxWebhookError/invalidPublicKey``.
    public init(configuration: TelnyxConfiguration) throws {
        guard let key: String = configuration.publicKey, !key.isEmpty else {
            throw TelnyxWebhookError.publicKeyNotConfigured
        }
        try self.init(base64PublicKey: key, tolerance: configuration.webhookTimestampTolerance)
    }

    /// Checks the signature and timestamp of a webhook.
    ///
    /// - Parameters:
    ///   - body: The raw request body, exactly as received.
    ///   - signature: The `telnyx-signature-ed25519` header value.
    ///   - timestamp: The `telnyx-timestamp` header value (Unix seconds).
    ///   - now: The current time; injectable for tests.
    /// - Throws: ``TelnyxWebhookError``.
    public func verify<Body: DataProtocol>(
        body: Body,
        signature: String?,
        timestamp: String?,
        now: Date = Date()
    ) throws {
        guard let signature: String = signature?.trimmingCharacters(in: .whitespaces), !signature.isEmpty else {
            throw TelnyxWebhookError.missingSignature
        }
        guard let timestamp: String = timestamp?.trimmingCharacters(in: .whitespaces), !timestamp.isEmpty else {
            throw TelnyxWebhookError.missingTimestamp
        }
        guard let signatureBytes: Data = Data(base64Encoded: signature), signatureBytes.count == 64 else {
            throw TelnyxWebhookError.malformedSignature
        }
        guard timestamp.utf8.allSatisfy({ (byte: UInt8) -> Bool in byte >= 0x30 && byte <= 0x39 }),
              let seconds: Int64 = Int64(timestamp)
        else {
            throw TelnyxWebhookError.malformedTimestamp
        }

        var signed: [UInt8] = Array(timestamp.utf8)
        signed.append(0x7C)
        signed.append(contentsOf: body)
        guard publicKey.isValidSignature(signatureBytes, for: signed) else {
            throw TelnyxWebhookError.invalidSignature
        }

        let age: TimeInterval = now.timeIntervalSince1970 - TimeInterval(seconds)
        if age > tolerance {
            throw TelnyxWebhookError.staleTimestamp
        }
        if -age > tolerance {
            throw TelnyxWebhookError.futureTimestamp
        }
    }

    /// Verifies a webhook and decodes its event. The pure form: no `Request` needed.
    ///
    /// - Throws: ``TelnyxWebhookError``; ``TelnyxWebhookError/malformedEvent(_:)`` when the
    ///   signature is valid but the body is not an event envelope.
    public func verifiedEvent<Body: DataProtocol>(
        body: Body,
        signature: String?,
        timestamp: String?,
        now: Date = Date()
    ) throws -> TelnyxWebhookEvent {
        try verify(body: body, signature: signature, timestamp: timestamp, now: now)
        return try TelnyxWebhookVerifier.decodeEvent(body: body)
    }

    /// Verifies the webhook carried by `request` and decodes its event.
    ///
    /// Reads the raw body (collecting it first, up to `maximumBodySize` bytes, if the route
    /// streams its body) and the two signature headers.
    ///
    /// - Throws: ``TelnyxWebhookError``, which is an `AbortError`.
    public func verifiedEvent(
        from request: Request,
        now: Date = Date(),
        maximumBodySize: Int = 1 << 20
    ) async throws -> TelnyxWebhookEvent {
        let buffer: ByteBuffer
        if let collected: ByteBuffer = request.body.data {
            buffer = collected
        } else if let streamed: ByteBuffer = try await request.body.collect(max: maximumBodySize).get() {
            buffer = streamed
        } else {
            throw TelnyxWebhookError.missingBody
        }
        let bytes: [UInt8] = Array(buffer.readableBytesView)
        guard !bytes.isEmpty else {
            throw TelnyxWebhookError.missingBody
        }
        let event: TelnyxWebhookEvent = try verifiedEvent(
            body: bytes,
            signature: request.headers.first(name: TelnyxWebhookVerifier.signatureHeader),
            timestamp: request.headers.first(name: TelnyxWebhookVerifier.timestampHeader),
            now: now
        )
        request.logger.debug("Telnyx webhook verified", metadata: ["eventType": "\(event.eventType.rawValue)"])
        return event
    }

    /// Decodes an event envelope without verifying it. Only use on bytes already verified.
    static func decodeEvent<Body: DataProtocol>(body: Body) throws -> TelnyxWebhookEvent {
        do {
            return try TelnyxJSON.makeDecoder().decode(TelnyxWebhookEvent.self, from: Data(body))
        } catch {
            throw TelnyxWebhookError.malformedEvent(TelnyxHTTP.describe(error))
        }
    }
}
