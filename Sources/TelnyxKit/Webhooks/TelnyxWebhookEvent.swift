import Foundation

/// A webhook event type (`data.event_type`). Unlisted values decode as-is.
public struct TelnyxWebhookEventType: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let callInitiated: TelnyxWebhookEventType = "call.initiated"
    public static let messageReceived: TelnyxWebhookEventType = "message.received"
    public static let messageSent: TelnyxWebhookEventType = "message.sent"
    public static let messageFinalized: TelnyxWebhookEventType = "message.finalized"
}

/// A webhook delivery: the `{data: {...}, meta: {...}}` envelope with a typed payload.
///
/// `data.event_type` is the only required field: an envelope without it fails to decode.
public struct TelnyxWebhookEvent: Decodable, Sendable {
    /// The event id.
    public let id: String?
    /// `"event"`.
    public let recordType: String?
    public let eventType: TelnyxWebhookEventType
    public let occurredAt: Date?
    public let payload: TelnyxWebhookPayload
    public let meta: Meta?

    /// Delivery information.
    public struct Meta: Decodable, Sendable, Hashable {
        /// The delivery attempt, starting at 1.
        public let attempt: Int?
        /// The URL the webhook was sent to.
        public let deliveredTo: String?

        enum CodingKeys: String, CodingKey {
            case attempt
            case deliveredTo = "delivered_to"
        }
    }

    enum CodingKeys: String, CodingKey {
        case data
        case meta
    }

    enum DataKeys: String, CodingKey {
        case id
        case recordType = "record_type"
        case eventType = "event_type"
        case occurredAt = "occurred_at"
        case payload
    }

    public init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        let data: KeyedDecodingContainer<DataKeys> = try container.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        self.id = try data.decodeIfPresent(String.self, forKey: .id)
        self.recordType = try data.decodeIfPresent(String.self, forKey: .recordType)
        let eventType: TelnyxWebhookEventType = try data.decode(TelnyxWebhookEventType.self, forKey: .eventType)
        self.eventType = eventType
        self.occurredAt = try data.decodeIfPresent(Date.self, forKey: .occurredAt)
        self.meta = try container.decodeIfPresent(Meta.self, forKey: .meta)

        switch eventType {
        case .callInitiated:
            self.payload = .callInitiated(try data.decode(TelnyxCallInitiatedPayload.self, forKey: .payload))
        case .messageReceived:
            self.payload = .messageReceived(try data.decode(TelnyxMessage.self, forKey: .payload))
        case .messageSent:
            self.payload = .messageSent(try data.decode(TelnyxMessage.self, forKey: .payload))
        case .messageFinalized:
            self.payload = .messageFinalized(try data.decode(TelnyxMessage.self, forKey: .payload))
        default:
            let raw: TelnyxJSONValue = try data.decodeIfPresent(TelnyxJSONValue.self, forKey: .payload) ?? .null
            self.payload = .unknown(eventType: eventType.rawValue, payload: raw)
        }
    }
}

/// The typed payload of a webhook event.
public enum TelnyxWebhookPayload: Sendable {
    /// `call.initiated`.
    case callInitiated(TelnyxCallInitiatedPayload)
    /// `message.received`: an inbound message (`direction` is `inbound`).
    case messageReceived(TelnyxMessage)
    /// `message.sent`.
    case messageSent(TelnyxMessage)
    /// `message.finalized`: `to[].status` carries the terminal delivery status.
    case messageFinalized(TelnyxMessage)
    /// Any other event type, with its type string and the raw payload (`.null` if absent).
    case unknown(eventType: String, payload: TelnyxJSONValue)
}

/// A call direction. Unlisted values decode as-is.
public struct TelnyxCallDirection: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let incoming: TelnyxCallDirection = "incoming"
    /// Assumed counterpart of `incoming`; not listed in the reference used for this package.
    public static let outgoing: TelnyxCallDirection = "outgoing"
}

/// A call state. Unlisted values decode as-is.
public struct TelnyxCallState: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let parked: TelnyxCallState = "parked"
}

/// The payload of a `call.initiated` event.
public struct TelnyxCallInitiatedPayload: Decodable, Sendable, Hashable {
    public let callControlID: String?
    public let callLegID: String?
    public let callSessionID: String?
    public let connectionID: String?
    /// Base64 state set by your application, if any.
    public let clientState: String?
    public let from: String?
    public let to: String?
    public let direction: TelnyxCallDirection?
    public let state: TelnyxCallState?

    /// `clientState` base64-decoded, if present and valid base64.
    public var decodedClientState: Data? {
        clientState.flatMap { (state: String) -> Data? in Data(base64Encoded: state) }
    }

    enum CodingKeys: String, CodingKey {
        case callControlID = "call_control_id"
        case callLegID = "call_leg_id"
        case callSessionID = "call_session_id"
        case connectionID = "connection_id"
        case clientState = "client_state"
        case from
        case to
        case direction
        case state
    }
}
