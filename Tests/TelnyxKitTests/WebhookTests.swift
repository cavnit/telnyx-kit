import Crypto
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import TelnyxKit

/// A freshly generated signing key standing in for Telnyx's.
struct WebhookSigner {
    let privateKey: Curve25519.Signing.PrivateKey = Curve25519.Signing.PrivateKey()

    var rawPublicKeyBase64: String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    var spkiPublicKeyBase64: String {
        Data(TelnyxWebhookVerifier.spkiPrefix + Array(privateKey.publicKey.rawRepresentation)).base64EncodedString()
    }

    func sign(_ body: String, timestamp: String) throws -> String {
        let signed: Data = Data("\(timestamp)|\(body)".utf8)
        return try privateKey.signature(for: signed).base64EncodedString()
    }
}

enum WebhookFixture {
    static let timestamp: String = "1795341600"
    static let now: Date = Date(timeIntervalSince1970: 1_795_341_600)

    // Deliberately irregular whitespace and key order: re-encoding the JSON would break the signature.
    static let callInitiated: String = """
    {"data":{"record_type":"event","event_type":"call.initiated","id":"0ccc7b54-4df3-4bca-a65a-3da1ecc777f0",
      "occurred_at":"2026-11-22T10:00:00.123456Z",
      "payload":{"call_control_id":"v3:abc123","call_leg_id":"leg-1","call_session_id":"session-1",
        "connection_id":"1494404757140276705","client_state":"aGVsbG8=","from":"+15550100199","to":"+15550100123",
        "direction":"incoming","state":"parked","start_time":"2026-11-22T10:00:00Z"}},
     "meta":{"attempt":1,"delivered_to":"https://example.com/webhooks/telnyx"}}
    """

    static func message(_ eventType: String, direction: String, status: String) -> String {
        """
        {"data": {"record_type": "event", "event_type": "\(eventType)", "id": "evt-\(eventType)",
          "occurred_at": "2026-11-22T10:00:00.000+00:00",
          "payload": {"id": "40385f64-5717-4562-b3fc-2c963f66afa6", "record_type": "message", "direction": "\(direction)",
            "type": "SMS", "from": {"phone_number": "+15550100199", "carrier": "Example Carrier", "line_type": "Wireless"},
            "to": [{"phone_number": "+15550100123", "status": "\(status)"}], "text": "Hi there", "parts": 1,
            "media": [], "cost": null, "errors": []}},
         "meta": {"attempt": 2, "delivered_to": "https://example.com/webhooks/telnyx"}}
        """
    }

    static let unknownEvent: String = """
    {"data": {"record_type": "event", "event_type": "number_order.complete", "id": "evt-9",
      "occurred_at": "2026-11-22T10:00:00Z", "payload": {"id": "12ade33a", "status": "success", "count": 2, "nested": {"ok": true}}},
     "meta": {"attempt": 1}}
    """
}

@Suite("Webhook verification")
struct WebhookVerificationTests {
    let signer: WebhookSigner = WebhookSigner()

    func verifier(tolerance: TimeInterval = 300) throws -> TelnyxWebhookVerifier {
        try TelnyxWebhookVerifier(base64PublicKey: signer.rawPublicKeyBase64, tolerance: tolerance)
    }

    @Test("a valid signature verifies")
    func valid() throws {
        let body: String = WebhookFixture.callInitiated
        let signature: String = try signer.sign(body, timestamp: WebhookFixture.timestamp)
        try verifier().verify(body: Array(body.utf8), signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now)
        try verifier().verify(body: Data(body.utf8), signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now)
    }

    @Test("raw and SPKI public key forms both verify")
    func keyForms() throws {
        let body: String = WebhookFixture.callInitiated
        let signature: String = try signer.sign(body, timestamp: WebhookFixture.timestamp)
        for key: String in [signer.rawPublicKeyBase64, signer.spkiPublicKeyBase64, "  \(signer.rawPublicKeyBase64)\n"] {
            let verifier: TelnyxWebhookVerifier = try TelnyxWebhookVerifier(base64PublicKey: key)
            try verifier.verify(body: Array(body.utf8), signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now)
        }
        #expect(Data(base64Encoded: signer.spkiPublicKeyBase64)?.count == 44)
    }

    @Test("invalid public keys are rejected")
    func invalidKeys() throws {
        var wrongPrefix: [UInt8] = TelnyxWebhookVerifier.spkiPrefix + Array(signer.privateKey.publicKey.rawRepresentation)
        wrongPrefix[8] = 0x6E // Ed448's OID byte
        let candidates: [String] = [
            "not base64!",
            Data(repeating: 1, count: 31).base64EncodedString(),
            Data(repeating: 1, count: 33).base64EncodedString(),
            Data(wrongPrefix).base64EncodedString(),
            "",
        ]
        for candidate: String in candidates {
            #expect(throws: TelnyxWebhookError.invalidPublicKey) {
                _ = try TelnyxWebhookVerifier(base64PublicKey: candidate)
            }
        }
        #expect(throws: TelnyxWebhookError.publicKeyNotConfigured) {
            _ = try TelnyxWebhookVerifier(configuration: TelnyxConfiguration(apiKey: ""))
        }
    }

    @Test("a different key is rejected")
    func wrongKey() throws {
        let body: String = WebhookFixture.callInitiated
        let signature: String = try WebhookSigner().sign(body, timestamp: WebhookFixture.timestamp)
        #expect(throws: TelnyxWebhookError.invalidSignature) {
            try verifier().verify(body: Array(body.utf8), signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now)
        }
    }

    @Test("a tampered body or timestamp is rejected")
    func tampered() throws {
        let body: String = WebhookFixture.callInitiated
        let signature: String = try signer.sign(body, timestamp: WebhookFixture.timestamp)
        let tamperedBody: String = body.replacingOccurrences(of: "+15550100199", with: "+15550100198")
        #expect(throws: TelnyxWebhookError.invalidSignature) {
            try verifier().verify(body: Array(tamperedBody.utf8), signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now)
        }
        #expect(throws: TelnyxWebhookError.invalidSignature) {
            try verifier().verify(body: Array((body + " ").utf8), signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now)
        }
        #expect(throws: TelnyxWebhookError.invalidSignature) {
            try verifier().verify(body: Array(body.utf8), signature: signature, timestamp: "1795341601", now: WebhookFixture.now)
        }
    }

    @Test("stale and future timestamps are rejected; the edges of the tolerance pass")
    func timestamps() throws {
        let body: String = WebhookFixture.callInitiated
        let signature: String = try signer.sign(body, timestamp: WebhookFixture.timestamp)
        let bytes: [UInt8] = Array(body.utf8)
        let verifier: TelnyxWebhookVerifier = try verifier()

        try verifier.verify(body: bytes, signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now.addingTimeInterval(300))
        try verifier.verify(body: bytes, signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now.addingTimeInterval(-300))
        #expect(throws: TelnyxWebhookError.staleTimestamp) {
            try verifier.verify(body: bytes, signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now.addingTimeInterval(301))
        }
        #expect(throws: TelnyxWebhookError.futureTimestamp) {
            try verifier.verify(body: bytes, signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now.addingTimeInterval(-301))
        }
        let strict: TelnyxWebhookVerifier = try self.verifier(tolerance: 10)
        #expect(throws: TelnyxWebhookError.staleTimestamp) {
            try strict.verify(body: bytes, signature: signature, timestamp: WebhookFixture.timestamp, now: WebhookFixture.now.addingTimeInterval(11))
        }
    }

    @Test("missing and garbled headers are rejected")
    func headers() throws {
        let body: [UInt8] = Array(WebhookFixture.callInitiated.utf8)
        let signature: String = try signer.sign(WebhookFixture.callInitiated, timestamp: WebhookFixture.timestamp)
        let verifier: TelnyxWebhookVerifier = try verifier()
        let now: Date = WebhookFixture.now
        let ts: String = WebhookFixture.timestamp

        #expect(throws: TelnyxWebhookError.missingSignature) { try verifier.verify(body: body, signature: nil, timestamp: ts, now: now) }
        #expect(throws: TelnyxWebhookError.missingSignature) { try verifier.verify(body: body, signature: "", timestamp: ts, now: now) }
        #expect(throws: TelnyxWebhookError.missingTimestamp) { try verifier.verify(body: body, signature: signature, timestamp: nil, now: now) }
        #expect(throws: TelnyxWebhookError.missingTimestamp) { try verifier.verify(body: body, signature: signature, timestamp: " ", now: now) }
        #expect(throws: TelnyxWebhookError.malformedSignature) { try verifier.verify(body: body, signature: "%%%not-base64", timestamp: ts, now: now) }
        #expect(throws: TelnyxWebhookError.malformedSignature) {
            try verifier.verify(body: body, signature: Data(repeating: 7, count: 63).base64EncodedString(), timestamp: ts, now: now)
        }
        for garbled: String in ["17953416OO", "-1795341600", "+1795341600", "1795341600.5", "99999999999999999999999"] {
            #expect(throws: TelnyxWebhookError.malformedTimestamp) { try verifier.verify(body: body, signature: signature, timestamp: garbled, now: now) }
        }
    }

    @Test("errors are AbortErrors with sensible statuses")
    func abortStatuses() {
        #expect(TelnyxWebhookError.invalidSignature.status == .unauthorized)
        #expect(TelnyxWebhookError.staleTimestamp.status == .unauthorized)
        #expect(TelnyxWebhookError.missingSignature.status == .unauthorized)
        #expect(TelnyxWebhookError.missingBody.status == .badRequest)
        #expect(TelnyxWebhookError.malformedEvent("x").status == .badRequest)
        #expect(TelnyxWebhookError.publicKeyNotConfigured.status == .internalServerError)
    }
}

@Suite("Webhook events")
struct WebhookEventTests {
    let signer: WebhookSigner = WebhookSigner()

    func event(_ body: String) throws -> TelnyxWebhookEvent {
        let verifier: TelnyxWebhookVerifier = try TelnyxWebhookVerifier(base64PublicKey: signer.rawPublicKeyBase64)
        return try verifier.verifiedEvent(
            body: Array(body.utf8),
            signature: try signer.sign(body, timestamp: WebhookFixture.timestamp),
            timestamp: WebhookFixture.timestamp,
            now: WebhookFixture.now
        )
    }

    @Test("call.initiated")
    func callInitiated() throws {
        let event: TelnyxWebhookEvent = try event(WebhookFixture.callInitiated)
        #expect(event.eventType == .callInitiated)
        #expect(event.recordType == "event")
        #expect(event.id == "0ccc7b54-4df3-4bca-a65a-3da1ecc777f0")
        #expect(event.meta?.attempt == 1)
        #expect(event.meta?.deliveredTo == "https://example.com/webhooks/telnyx")
        let occurred: Date = try #require(event.occurredAt)
        #expect(abs(occurred.timeIntervalSince1970 - (1_795_341_600 + 0.123456)) < 0.000_01)
        guard case .callInitiated(let payload) = event.payload else {
            Issue.record("expected call.initiated, got \(event.payload)")
            return
        }
        #expect(payload.callControlID == "v3:abc123")
        #expect(payload.callLegID == "leg-1")
        #expect(payload.callSessionID == "session-1")
        #expect(payload.connectionID == "1494404757140276705")
        #expect(payload.from == "+15550100199")
        #expect(payload.to == "+15550100123")
        #expect(payload.direction == .incoming)
        #expect(payload.state == .parked)
        #expect(payload.decodedClientState == Data("hello".utf8))
    }

    @Test("message.received, message.sent and message.finalized")
    func messageEvents() throws {
        let received: TelnyxWebhookEvent = try event(WebhookFixture.message("message.received", direction: "inbound", status: "webhook_delivered"))
        guard case .messageReceived(let inbound) = received.payload else {
            Issue.record("expected message.received, got \(received.payload)")
            return
        }
        #expect(inbound.direction == .inbound)
        #expect(inbound.text == "Hi there")
        #expect(inbound.from?.phoneNumber == "+15550100199")
        #expect(inbound.to?.first?.status?.rawValue == "webhook_delivered")
        #expect(inbound.cost == nil)
        #expect(received.meta?.attempt == 2)

        let sent: TelnyxWebhookEvent = try event(WebhookFixture.message("message.sent", direction: "outbound", status: "sent"))
        guard case .messageSent(let outbound) = sent.payload else {
            Issue.record("expected message.sent, got \(sent.payload)")
            return
        }
        #expect(outbound.to?.first?.status == .sent)

        let finalized: TelnyxWebhookEvent = try event(WebhookFixture.message("message.finalized", direction: "outbound", status: "delivered"))
        guard case .messageFinalized(let final) = finalized.payload else {
            Issue.record("expected message.finalized, got \(finalized.payload)")
            return
        }
        #expect(final.to?.first?.status == .delivered)
    }

    @Test("an unknown event type keeps its type string and raw payload")
    func unknownEvent() throws {
        let event: TelnyxWebhookEvent = try event(WebhookFixture.unknownEvent)
        #expect(event.eventType.rawValue == "number_order.complete")
        guard case .unknown(let eventType, let payload) = event.payload else {
            Issue.record("expected .unknown, got \(event.payload)")
            return
        }
        #expect(eventType == "number_order.complete")
        #expect(payload["status"] == .string("success"))
        #expect(payload["count"] == .int(2))
        #expect(payload["nested"]?["ok"] == .bool(true))
    }

    @Test("an unknown event without a payload decodes with .null")
    func unknownEventNoPayload() throws {
        let event: TelnyxWebhookEvent = try event(#"{"data": {"event_type": "something.new"}}"#)
        guard case .unknown(let eventType, let payload) = event.payload else {
            Issue.record("expected .unknown")
            return
        }
        #expect(eventType == "something.new")
        #expect(payload == .null)
        #expect(event.meta == nil)
    }

    @Test("a signed body that is not an envelope is malformedEvent")
    func malformed() throws {
        #expect(throws: TelnyxWebhookError.malformedEvent("missing key data.event_type")) {
            _ = try event(#"{"data": {"id": "x"}}"#)
        }
        #expect(throws: TelnyxWebhookError.self) {
            _ = try event("not json")
        }
    }
}

@Suite("Webhook route")
struct WebhookRouteTests {
    let signer: WebhookSigner = WebhookSigner()

    func configure(_ app: Application) {
        app.telnyx.configuration = TelnyxConfiguration(apiKey: "", publicKey: signer.spkiPublicKeyBase64)
        app.post("webhooks", "telnyx") { (req: Request) async throws -> String in
            let event: TelnyxWebhookEvent = try await req.telnyx.webhooks.verifiedEvent(now: WebhookFixture.now)
            return event.eventType.rawValue
        }
        app.on(.POST, "webhooks", "streamed", body: .stream) { (req: Request) async throws -> String in
            let verifier: TelnyxWebhookVerifier = try req.application.telnyx.webhooks.verifier
            let event: TelnyxWebhookEvent = try await verifier.verifiedEvent(from: req, now: WebhookFixture.now)
            return event.eventType.rawValue
        }
    }

    func headers(_ body: String, timestamp: String = WebhookFixture.timestamp) throws -> HTTPHeaders {
        [
            "content-type": "application/json",
            "telnyx-signature-ed25519": try signer.sign(body, timestamp: timestamp),
            "telnyx-timestamp": timestamp,
        ]
    }

    @Test("a signed body posted to a real route verifies against the raw bytes")
    func signedRequest() async throws {
        let body: String = WebhookFixture.callInitiated
        try await withApp(configure: { (app: Application) async throws in configure(app) }) { (app: Application) async throws in
            try await app.testing().test(.POST, "webhooks/telnyx", headers: try headers(body), body: ByteBuffer(string: body)) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                #expect(response.body.string == "call.initiated")
            }
            try await app.testing().test(.POST, "webhooks/streamed", headers: try headers(body), body: ByteBuffer(string: body)) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                #expect(response.body.string == "call.initiated")
            }
        }
    }

    @Test("a tampered body, stale timestamp or missing header is a 401; no body is a 400")
    func rejectedRequests() async throws {
        let body: String = WebhookFixture.message("message.received", direction: "inbound", status: "webhook_delivered")
        try await withApp(configure: { (app: Application) async throws in configure(app) }) { (app: Application) async throws in
            let signed: HTTPHeaders = try headers(body)
            try await app.testing().test(.POST, "webhooks/telnyx", headers: signed, body: ByteBuffer(string: body + "\n")) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unauthorized)
                #expect(response.body.string.contains("Invalid Telnyx webhook signature"))
            }

            let stale: HTTPHeaders = try headers(body, timestamp: "1795341000")
            try await app.testing().test(.POST, "webhooks/telnyx", headers: stale, body: ByteBuffer(string: body)) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unauthorized)
                #expect(response.body.string.contains("too old"))
            }

            var unsigned: HTTPHeaders = signed
            unsigned.remove(name: "telnyx-signature-ed25519")
            try await app.testing().test(.POST, "webhooks/telnyx", headers: unsigned, body: ByteBuffer(string: body)) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unauthorized)
            }

            try await app.testing().test(.POST, "webhooks/telnyx", headers: signed) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("Application and Request accessors expose clients built from the shared configuration")
    func accessors() async throws {
        try await withApp { (app: Application) async throws in
            app.telnyx.configuration = TelnyxConfiguration(apiKey: Fixture.apiKey, baseURL: TelnyxConfiguration.sandboxBaseURL)
            #expect(app.telnyx.numbers.client.configuration.baseURL == TelnyxConfiguration.sandboxBaseURL)
            #expect(app.telnyx.messaging.client.configuration.apiKey == Fixture.apiKey)
            #expect(app.telnyx.webhooks.configuration.publicKey == nil)
            #expect(throws: TelnyxWebhookError.publicKeyNotConfigured) {
                _ = try app.telnyx.webhooks.verifier
            }
            let request: Request = Request(application: app, on: app.eventLoopGroup.any())
            #expect(request.telnyx.numbers.client.configuration.baseURL == TelnyxConfiguration.sandboxBaseURL)
            #expect(request.telnyx.messaging.client.configuration.baseURL == TelnyxConfiguration.sandboxBaseURL)
        }
    }
}
