import Vapor

/// Sends SMS and MMS messages.
///
/// Get one from `app.telnyx.messaging.client` or `req.telnyx.messaging.client`.
public struct TelnyxMessagingClient: Sendable {
    let client: any Client
    let logger: Logger
    let configuration: TelnyxConfiguration

    /// Creates a client. Usually obtained from `app.telnyx.messaging.client` instead.
    public init(client: any Client, logger: Logger, configuration: TelnyxConfiguration) {
        self.client = client
        self.logger = logger
        self.configuration = configuration
    }

    /// Sends a message (`POST /messages`).
    ///
    /// - Parameters:
    ///   - message: The message. `to` must not be empty.
    ///   - idempotencyKey: Sent as `Idempotency-Key` so a retried request is not sent twice.
    ///     1–255 characters of letters, digits, `-` and `_`.
    /// - Throws: ``TelnyxError/invalidRequest(_:)`` for an empty `to` or a malformed key, before
    ///   anything is sent; otherwise ``TelnyxError`` for a Telnyx error response.
    public func send(_ message: TelnyxOutboundMessage, idempotencyKey: String? = nil) async throws -> TelnyxMessage {
        guard !message.to.isEmpty else {
            throw TelnyxError.invalidRequest("message recipient (to) is empty")
        }
        var headers: HTTPHeaders = [:]
        if let idempotencyKey: String = idempotencyKey {
            guard TelnyxMessagingClient.isValidIdempotencyKey(idempotencyKey) else {
                throw TelnyxError.invalidRequest("idempotency key must be 1-255 letters, digits, '-' or '_'")
            }
            headers.add(name: "Idempotency-Key", value: idempotencyKey)
        }
        let http: TelnyxHTTP = TelnyxHTTP(client: client, logger: logger, configuration: configuration)
        return try await http.send(.POST, path: "/messages", body: message, headers: headers, decoding: TelnyxMessage.self)
    }

    /// Whether `key` is 1–255 ASCII letters, digits, `-` or `_`.
    public static func isValidIdempotencyKey(_ key: String) -> Bool {
        let bytes: String.UTF8View = key.utf8
        guard (1...255).contains(bytes.count) else {
            return false
        }
        return bytes.allSatisfy { (byte: UInt8) -> Bool in
            (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
                || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x5F
        }
    }
}
