import Foundation
import Testing
import Vapor
@testable import TelnyxKit

@Suite("Messaging client")
struct MessagingClientTests {
    @Test("send posts the message with an idempotency key and decodes the response")
    func send() async throws {
        let client: RecordingClient = RecordingClient(body: "{\"data\": \(Fixture.messageJSON)}")
        let message: TelnyxOutboundMessage = TelnyxOutboundMessage(
            to: "+15550100199",
            from: "+15550100123",
            text: "Hello from the tests",
            mediaURLs: ["https://example.com/a.png"],
            webhookURL: "https://example.com/webhooks/telnyx",
            useProfileWebhooks: false,
            type: .mms,
            sendAt: try Fixture.date("2026-11-23T08:00:00Z"),
            encoding: .auto
        )

        let sent: TelnyxMessage = try await Fixture.messaging(client).send(message, idempotencyKey: "order-42_retry-1")

        let request: ClientRequest = try #require(client.lastRequest)
        #expect(request.method == .POST)
        #expect(request.url.string == "https://api.telnyx.com/v2/messages")
        #expect(request.headers.first(name: "Idempotency-Key") == "order-42_retry-1")
        #expect(request.headers.first(name: .authorization) == "Bearer \(Fixture.apiKey)")
        #expect(request.headers.first(name: .contentType) == "application/json")
        #expect(try Fixture.jsonBody(request) == (try Fixture.json("""
        {
          "to": "+15550100199",
          "from": "+15550100123",
          "text": "Hello from the tests",
          "media_urls": ["https://example.com/a.png"],
          "webhook_url": "https://example.com/webhooks/telnyx",
          "use_profile_webhooks": false,
          "type": "MMS",
          "send_at": "2026-11-23T08:00:00Z",
          "encoding": "auto"
        }
        """)))

        #expect(sent.id == "40385f64-5717-4562-b3fc-2c963f66afa6")
        #expect(sent.direction == .outbound)
        #expect(sent.type == .sms)
        #expect(sent.from?.phoneNumber == "+15550100123")
        #expect(sent.to?.first?.status == .queued)
        #expect(sent.to?.first?.lineType == "Wireless")
        #expect(sent.media?.first?.size == 2048)
        #expect(sent.cost?.amount == "0.0040")
        #expect(sent.encoding?.rawValue == "GSM-7")
        #expect(sent.parts == 1)
        #expect(sent.receivedAt == (try Fixture.date("2026-11-22T10:00:00Z")))
        #expect(sent.sentAt == nil)
        #expect(sent.errors == [])
    }

    @Test("no idempotency key means no header")
    func sendWithoutKey() async throws {
        let client: RecordingClient = RecordingClient(body: "{\"data\": {\"id\": \"m-1\"}}")
        let sent: TelnyxMessage = try await Fixture.messaging(client).send(
            TelnyxOutboundMessage(to: "+15550100199", messagingProfileID: "4000eba1-a0c0-4563-9925-b25e842a7cb6", text: "Hi")
        )
        #expect(client.lastRequest?.headers.contains(name: "Idempotency-Key") == false)
        #expect(try Fixture.jsonBody(client.lastRequest) == (try Fixture.json("""
        {"to": "+15550100199", "messaging_profile_id": "4000eba1-a0c0-4563-9925-b25e842a7cb6", "text": "Hi"}
        """)))
        #expect(sent.id == "m-1")
        #expect(sent.to == nil)
    }

    @Test("malformed idempotency keys and empty recipients are rejected before sending",
          arguments: ["", "has space", "slash/key", "emoji-\u{1F600}", String(repeating: "a", count: 256)])
    func invalidIdempotencyKey(key: String) async throws {
        let client: RecordingClient = RecordingClient(body: "{}")
        await #expect(throws: TelnyxError.self) {
            _ = try await Fixture.messaging(client).send(TelnyxOutboundMessage(to: "+15550100199", text: "Hi"), idempotencyKey: key)
        }
        #expect(client.requests.isEmpty)
    }

    @Test("idempotency key rules")
    func idempotencyKeyRules() {
        #expect(TelnyxMessagingClient.isValidIdempotencyKey("a"))
        #expect(TelnyxMessagingClient.isValidIdempotencyKey("A-z_0-9"))
        #expect(TelnyxMessagingClient.isValidIdempotencyKey(String(repeating: "k", count: 255)))
        #expect(!TelnyxMessagingClient.isValidIdempotencyKey("a.b"))
    }

    @Test("empty to is rejected")
    func emptyTo() async throws {
        let client: RecordingClient = RecordingClient(body: "{}")
        await #expect(throws: TelnyxError.self) {
            _ = try await Fixture.messaging(client).send(TelnyxOutboundMessage(to: "", text: "Hi"))
        }
        #expect(client.requests.isEmpty)
    }
}

@Suite("Errors")
struct ErrorTests {
    @Test("documented error body decodes into .api")
    func documentedError() async throws {
        let body: String = """
        {"errors": [{
          "code": "10005",
          "title": "Resource not found",
          "detail": "The requested resource or URL could not be found.",
          "source": {"pointer": "/id", "parameter": "id"},
          "meta": {"url": "https://developers.telnyx.com/docs/overview/errors/10005"}
        }]}
        """
        let client: RecordingClient = RecordingClient(status: .notFound, body: body)
        let error: TelnyxError = try await #require(throws: TelnyxError.self) {
            _ = try await Fixture.numbers(client).getPhoneNumber(id: "1")
        }
        guard case .api(let status, let errors, let rateLimit) = error else {
            Issue.record("expected .api, got \(error)")
            return
        }
        #expect(status == .notFound)
        #expect(rateLimit == nil)
        #expect(errors.count == 1)
        #expect(errors.first?.code == .notFound)
        #expect(errors.first?.title == "Resource not found")
        #expect(errors.first?.source?.pointer == "/id")
        #expect(errors.first?.source?.parameter == "id")
        #expect(errors.first?.meta?.url == "https://developers.telnyx.com/docs/overview/errors/10005")
        #expect(error.hasCode(.notFound))
        #expect(!error.isRateLimited)
        #expect(error.httpStatus == .notFound)
        // As an AbortError it is an upstream failure, not the caller's 404.
        #expect(error.status == .badGateway)
        #expect(error.reason == "Telnyx API request failed (status 404, codes 10005)")
    }

    @Test("429 keeps the rate-limit headers")
    func rateLimited() async throws {
        let headers: HTTPHeaders = [
            "x-ratelimit-limit": "100",
            "x-ratelimit-remaining": "0",
            "x-ratelimit-reset": "1795000000",
            "retry-after": "17",
        ]
        let body: String = #"{"errors": [{"code": "10011", "title": "Too many requests"}]}"#
        let client: RecordingClient = RecordingClient(status: .tooManyRequests, headers: headers, body: body)
        let error: TelnyxError = try await #require(throws: TelnyxError.self) {
            _ = try await Fixture.messaging(client).send(TelnyxOutboundMessage(to: "+15550100199", text: "Hi"))
        }
        let rateLimit: TelnyxRateLimit = try #require(error.rateLimit)
        #expect(rateLimit == TelnyxRateLimit(limit: "100", remaining: "0", reset: "1795000000", retryAfter: "17"))
        #expect(rateLimit.retryAfterSeconds == 17)
        #expect(error.hasCode(.rateLimitExceeded))
        #expect(error.isRateLimited)
        #expect(error.status == .serviceUnavailable)
    }

    @Test("rate-limit headers are only attached to 429")
    func rateLimitOnlyFor429() async throws {
        let client: RecordingClient = RecordingClient(
            status: .unauthorized,
            headers: ["x-ratelimit-remaining": "5"],
            body: #"{"errors": [{"code": "10009", "title": "Authentication failed"}]}"#
        )
        let error: TelnyxError = try await #require(throws: TelnyxError.self) {
            _ = try await Fixture.numbers(client).getNumberOrder(id: "x")
        }
        #expect(error.rateLimit == nil)
        #expect(error.hasCode(.authenticationFailed))
    }

    @Test("a non-JSON error body becomes .invalidResponse with a bounded, key-free snippet")
    func nonJSONError() async throws {
        let html: String = "<html>Bad gateway \(Fixture.apiKey) " + String(repeating: "x", count: 2000) + "</html>"
        let client: RecordingClient = RecordingClient(
            status: .badGateway,
            headers: ["content-type": "text/html"],
            body: html
        )
        let error: TelnyxError = try await #require(throws: TelnyxError.self) {
            _ = try await Fixture.numbers(client).listPhoneNumbers()
        }
        guard case .invalidResponse(let status, let snippet, let reason, _) = error else {
            Issue.record("expected .invalidResponse, got \(error)")
            return
        }
        #expect(status == .badGateway)
        #expect(reason == nil)
        #expect(snippet.hasPrefix("<html>Bad gateway <redacted> xxx"))
        #expect(snippet.utf8.count <= TelnyxError.maximumSnippetLength)
        #expect(!snippet.contains(Fixture.apiKey))
        #expect(!String(describing: error).contains(Fixture.apiKey))
        #expect(!String(describing: error).contains("Bad gateway"))
        #expect(error.errors.isEmpty)
    }

    @Test("a JSON error body without errors[] is .invalidResponse")
    func undocumentedJSONError() async throws {
        let client: RecordingClient = RecordingClient(status: .internalServerError, body: #"{"message": "boom"}"#)
        let error: TelnyxError = try await #require(throws: TelnyxError.self) {
            _ = try await Fixture.numbers(client).listPhoneNumbers()
        }
        guard case .invalidResponse(let status, let snippet, _, _) = error else {
            Issue.record("expected .invalidResponse, got \(error)")
            return
        }
        #expect(status == .internalServerError)
        #expect(snippet == #"{"message": "boom"}"#)
    }

    @Test("an undecodable 2xx body is .invalidResponse with a reason naming the path")
    func undecodableSuccess() async throws {
        let client: RecordingClient = RecordingClient(body: #"{"data": {"id": 42}}"#)
        let error: TelnyxError = try await #require(throws: TelnyxError.self) {
            _ = try await Fixture.numbers(client).getPhoneNumber(id: "1")
        }
        guard case .invalidResponse(let status, _, let reason, _) = error else {
            Issue.record("expected .invalidResponse, got \(error)")
            return
        }
        #expect(status == .ok)
        #expect(reason == "type mismatch at data.id")
    }

    @Test("an empty 2xx body is .invalidResponse")
    func emptySuccess() async throws {
        let client: RecordingClient = RecordingClient(body: "")
        await #expect(throws: TelnyxError.self) {
            _ = try await Fixture.numbers(client).deletePhoneNumber(id: "1")
        }
    }
}

@Suite("Core")
struct CoreTests {
    @Test("ISO 8601 with and without fractional seconds and offsets")
    func dates() throws {
        let base: Double = 1_795_341_600 // 2026-11-22T10:00:00Z
        #expect(TelnyxDate.parse("2026-11-22T10:00:00Z")?.timeIntervalSince1970 == base)
        #expect(TelnyxDate.parse("2026-11-22T10:00:00.000Z")?.timeIntervalSince1970 == base)
        #expect(TelnyxDate.parse("2026-11-22T10:00:00.250Z")?.timeIntervalSince1970 == base + 0.25)
        #expect(abs((TelnyxDate.parse("2026-11-22T10:00:00.123456Z")?.timeIntervalSince1970 ?? 0) - (base + 0.123456)) < 0.000_001)
        #expect(TelnyxDate.parse("2026-11-22T12:00:00+02:00")?.timeIntervalSince1970 == base)
        #expect(TelnyxDate.parse("2026-11-22T05:00:00-0500")?.timeIntervalSince1970 == base)
        #expect(TelnyxDate.parse("2026-11-22T10:00:00.000+00:00")?.timeIntervalSince1970 == base)
        #expect(TelnyxDate.parse("2026-11-22") == nil)
        #expect(TelnyxDate.parse("2026-11-22T10:00:00") == nil)
        #expect(TelnyxDate.parse("2026-13-22T10:00:00Z") == nil)
        #expect(TelnyxDate.parse("2026-11-22T10:00:00.Z") == nil)
        #expect(TelnyxDate.format(Date(timeIntervalSince1970: base + 0.9)) == "2026-11-22T10:00:00Z")
        #expect(TelnyxDate.format(Date(timeIntervalSince1970: 951_782_400)) == "2000-02-29T00:00:00Z")
    }

    @Test("query encoding leaves only unreserved characters bare")
    func percentEncoding() {
        #expect(TelnyxQuery.percentEncode("filter[phone_number][starts_with]") == "filter%5Bphone_number%5D%5Bstarts_with%5D")
        #expect(TelnyxQuery.percentEncode("+1 555&x=y/é") == "%2B1%20555%26x%3Dy%2F%C3%A9")
        #expect(TelnyxQuery.percentEncode("a-b.c_d~e") == "a-b.c_d~e")
    }

    @Test("unknown enum values decode and round-trip")
    func openEnums() throws {
        let decoder: JSONDecoder = TelnyxJSON.makeDecoder()
        let status: TelnyxPhoneNumberStatus = try decoder.decode(TelnyxPhoneNumberStatus.self, from: Data(#""brand-new-status""#.utf8))
        #expect(status.rawValue == "brand-new-status")
        #expect(status != .active)
        let known: TelnyxPhoneNumberStatus = try decoder.decode(TelnyxPhoneNumberStatus.self, from: Data(#""active""#.utf8))
        #expect(known == .active)
        let delivery: TelnyxMessageDeliveryStatus = try decoder.decode(TelnyxMessageDeliveryStatus.self, from: Data(#""carrier_rejected""#.utf8))
        #expect(delivery.rawValue == "carrier_rejected")
        let encoded: String = String(decoding: try JSONEncoder().encode([TelnyxNumberFeature.hdVoice, "new_one"]), as: UTF8.self)
        #expect(encoded == #"["hd_voice","new_one"]"#)
        #expect("\(TelnyxPhoneNumberType.tollFree)" == "toll_free")
    }

    @Test("configuration never prints the API key")
    func configurationRedaction() {
        let configuration: TelnyxConfiguration = TelnyxConfiguration(apiKey: Fixture.apiKey, publicKey: "AAAA")
        #expect(!String(describing: configuration).contains(Fixture.apiKey))
        #expect(!String(reflecting: configuration).contains(Fixture.apiKey))
        var dumped: String = ""
        dump(configuration, to: &dumped)
        #expect(!dumped.contains(Fixture.apiKey))
        #expect(configuration.baseURL == "https://api.telnyx.com/v2")
        #expect(configuration.webhookTimestampTolerance == 300)
    }
}
