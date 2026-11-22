import Foundation
import Synchronization
import Testing
import Vapor
@testable import TelnyxKit

/// A `Client` that records every request and answers from a queue of canned responses.
final class RecordingClient: Client, Sendable {
    struct Stub: Sendable {
        let status: HTTPResponseStatus
        let headers: HTTPHeaders
        let body: String
    }

    struct State {
        var requests: [ClientRequest] = []
        var stubs: [Stub] = []
    }

    let eventLoop: any EventLoop
    private let state: Mutex<State>

    init(_ stubs: [Stub]) {
        self.eventLoop = MultiThreadedEventLoopGroup.singleton.any()
        self.state = Mutex(State(requests: [], stubs: stubs))
    }

    convenience init(status: HTTPResponseStatus = .ok, headers: HTTPHeaders = [:], body: String) {
        self.init([Stub(status: status, headers: headers, body: body)])
    }

    var requests: [ClientRequest] {
        state.withLock { (state: inout State) -> [ClientRequest] in state.requests }
    }

    var lastRequest: ClientRequest? {
        requests.last
    }

    func delegating(to eventLoop: any EventLoop) -> any Client {
        self
    }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        let stub: Stub? = state.withLock { (state: inout State) -> Stub? in
            state.requests.append(request)
            return state.stubs.isEmpty ? nil : state.stubs.removeFirst()
        }
        guard let stub: Stub = stub else {
            return eventLoop.makeFailedFuture(Abort(.internalServerError, reason: "RecordingClient: no stub left"))
        }
        var headers: HTTPHeaders = stub.headers
        if !headers.contains(name: .contentType) {
            headers.add(name: .contentType, value: "application/json")
        }
        let response: ClientResponse = ClientResponse(
            status: stub.status,
            headers: headers,
            body: ByteBuffer(string: stub.body)
        )
        return eventLoop.makeSucceededFuture(response)
    }
}

enum Fixture {
    static let apiKey: String = "KEY_TEST_0123456789abcdef"

    static let configuration: TelnyxConfiguration = TelnyxConfiguration(apiKey: apiKey)

    static func logger() -> Logger {
        Logger(label: "telnyx-kit-tests")
    }

    static func numbers(_ client: RecordingClient) -> TelnyxNumbersClient {
        TelnyxNumbersClient(client: client, logger: logger(), configuration: configuration)
    }

    static func messaging(_ client: RecordingClient) -> TelnyxMessagingClient {
        TelnyxMessagingClient(client: client, logger: logger(), configuration: configuration)
    }

    /// The request body parsed as JSON, for order-independent comparison.
    static func jsonBody(_ request: ClientRequest?) throws -> TelnyxJSONValue {
        let buffer: ByteBuffer = try #require(request?.body)
        let data: Data = Data(buffer: buffer)
        return try JSONDecoder().decode(TelnyxJSONValue.self, from: data)
    }

    static func json(_ string: String) throws -> TelnyxJSONValue {
        try JSONDecoder().decode(TelnyxJSONValue.self, from: Data(string.utf8))
    }

    static func date(_ string: String) throws -> Date {
        try #require(TelnyxDate.parse(string))
    }

    static let phoneNumberJSON: String = """
    {
      "id": "1293384261075731499",
      "record_type": "phone_number",
      "phone_number": "+15550100123",
      "country_iso_alpha2": "US",
      "status": "active",
      "tags": ["support", "east"],
      "external_pin": "1234",
      "created_at": "2026-10-01T12:00:00.000Z",
      "updated_at": "2026-10-02T08:30:15Z",
      "purchased_at": "2026-10-01T12:00:01.123456Z",
      "activated_at": null,
      "phone_number_type": "local",
      "deletion_lock_enabled": false,
      "connection_id": "1494404757140276705",
      "connection_name": "Example connection",
      "messaging_profile_id": "UNAVAILABLE",
      "messaging_profile_name": null,
      "billing_group_id": null,
      "customer_reference": "example-ref-1",
      "emergency_enabled": false,
      "hd_voice_enabled": true,
      "source_type": "purchased"
    }
    """

    static func phoneNumberResponse(status: String = "active") -> String {
        "{\"data\": \(phoneNumberJSON.replacingOccurrences(of: "\"status\": \"active\"", with: "\"status\": \"\(status)\""))}"
    }

    static let messageJSON: String = """
    {
      "id": "40385f64-5717-4562-b3fc-2c963f66afa6",
      "record_type": "message",
      "direction": "outbound",
      "type": "SMS",
      "messaging_profile_id": "4000eba1-a0c0-4563-9925-b25e842a7cb6",
      "organization_id": "b448f9cc-a842-4784-98e9-03c1a5872950",
      "from": {"phone_number": "+15550100123", "carrier": "Example Carrier", "line_type": "Wireless"},
      "to": [{"phone_number": "+15550100199", "status": "queued", "carrier": "Example Carrier", "line_type": "Wireless"}],
      "text": "Hello from the tests",
      "subject": null,
      "media": [{"url": "https://example.com/a.png", "content_type": "image/png", "sha256": "abc123", "size": 2048}],
      "webhook_url": "https://example.com/webhooks/telnyx",
      "webhook_failover_url": null,
      "encoding": "GSM-7",
      "parts": 1,
      "tags": [],
      "cost": {"amount": "0.0040", "currency": "USD"},
      "received_at": "2026-11-22T10:00:00.000+00:00",
      "sent_at": null,
      "completed_at": null,
      "valid_until": "2026-11-22T11:00:00.000+00:00",
      "errors": []
    }
    """
}
