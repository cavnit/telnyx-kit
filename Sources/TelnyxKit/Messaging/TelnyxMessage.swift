import Foundation

/// A message type. Unlisted values decode as-is.
public struct TelnyxMessageType: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let sms: TelnyxMessageType = "SMS"
    public static let mms: TelnyxMessageType = "MMS"
}

/// A message direction. Unlisted values decode as-is.
public struct TelnyxMessageDirection: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let inbound: TelnyxMessageDirection = "inbound"
    public static let outbound: TelnyxMessageDirection = "outbound"
}

/// A message text encoding. Unlisted values decode as-is.
public struct TelnyxMessageEncoding: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let auto: TelnyxMessageEncoding = "auto"
    public static let gsm7: TelnyxMessageEncoding = "gsm7"
    public static let ucs2: TelnyxMessageEncoding = "ucs2"
}

/// The delivery status of one recipient (`to[].status`). Unlisted values decode as-is.
public struct TelnyxMessageDeliveryStatus: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let queued: TelnyxMessageDeliveryStatus = "queued"
    public static let sending: TelnyxMessageDeliveryStatus = "sending"
    public static let sent: TelnyxMessageDeliveryStatus = "sent"
    public static let expired: TelnyxMessageDeliveryStatus = "expired"
    public static let sendingFailed: TelnyxMessageDeliveryStatus = "sending_failed"
    public static let deliveryUnconfirmed: TelnyxMessageDeliveryStatus = "delivery_unconfirmed"
    public static let delivered: TelnyxMessageDeliveryStatus = "delivered"
    public static let deliveryFailed: TelnyxMessageDeliveryStatus = "delivery_failed"
    public static let read: TelnyxMessageDeliveryStatus = "read"
}

/// The body of `POST /messages`. Only non-`nil` fields are sent.
public struct TelnyxOutboundMessage: Encodable, Sendable, Hashable {
    /// The recipient in E.164 form. Required.
    public var to: String
    /// The sending number, alphanumeric sender id or short code.
    public var from: String?
    public var messagingProfileID: String?
    public var text: String?
    public var subject: String?
    public var mediaURLs: [String]?
    public var webhookURL: String?
    public var webhookFailoverURL: String?
    public var useProfileWebhooks: Bool?
    public var type: TelnyxMessageType?
    public var autoDetect: Bool?
    /// When to send; encoded as ISO 8601 UTC (`2026-01-01T12:00:00Z`).
    public var sendAt: Date?
    public var encoding: TelnyxMessageEncoding?

    public init(
        to: String,
        from: String? = nil,
        messagingProfileID: String? = nil,
        text: String? = nil,
        subject: String? = nil,
        mediaURLs: [String]? = nil,
        webhookURL: String? = nil,
        webhookFailoverURL: String? = nil,
        useProfileWebhooks: Bool? = nil,
        type: TelnyxMessageType? = nil,
        autoDetect: Bool? = nil,
        sendAt: Date? = nil,
        encoding: TelnyxMessageEncoding? = nil
    ) {
        self.to = to
        self.from = from
        self.messagingProfileID = messagingProfileID
        self.text = text
        self.subject = subject
        self.mediaURLs = mediaURLs
        self.webhookURL = webhookURL
        self.webhookFailoverURL = webhookFailoverURL
        self.useProfileWebhooks = useProfileWebhooks
        self.type = type
        self.autoDetect = autoDetect
        self.sendAt = sendAt
        self.encoding = encoding
    }

    enum CodingKeys: String, CodingKey {
        case to
        case from
        case messagingProfileID = "messaging_profile_id"
        case text
        case subject
        case mediaURLs = "media_urls"
        case webhookURL = "webhook_url"
        case webhookFailoverURL = "webhook_failover_url"
        case useProfileWebhooks = "use_profile_webhooks"
        case type
        case autoDetect = "auto_detect"
        case sendAt = "send_at"
        case encoding
    }
}

/// A message, as returned by `POST /messages` and carried by `message.*` webhooks.
public struct TelnyxMessage: Decodable, Sendable, Hashable {
    public let id: String?
    /// `"message"`.
    public let recordType: String?
    public let direction: TelnyxMessageDirection?
    public let type: TelnyxMessageType?
    public let messagingProfileID: String?
    public let organizationID: String?
    public let from: Endpoint?
    public let to: [Recipient]?
    public let text: String?
    public let subject: String?
    public let media: [Media]?
    public let webhookURL: String?
    public let webhookFailoverURL: String?
    public let encoding: TelnyxMessageEncoding?
    public let parts: Int?
    public let tags: [String]?
    public let cost: Cost?
    public let receivedAt: Date?
    public let sentAt: Date?
    public let completedAt: Date?
    public let validUntil: Date?
    /// Errors reported for the message; assumed to share the API error entry shape.
    public let errors: [TelnyxAPIError]?

    /// The sending side.
    public struct Endpoint: Decodable, Sendable, Hashable {
        public let phoneNumber: String?
        public let carrier: String?
        public let lineType: String?

        enum CodingKeys: String, CodingKey {
            case phoneNumber = "phone_number"
            case carrier
            case lineType = "line_type"
        }
    }

    /// One recipient and its delivery status.
    public struct Recipient: Decodable, Sendable, Hashable {
        public let phoneNumber: String?
        public let status: TelnyxMessageDeliveryStatus?
        public let carrier: String?
        public let lineType: String?

        enum CodingKeys: String, CodingKey {
            case phoneNumber = "phone_number"
            case status
            case carrier
            case lineType = "line_type"
        }
    }

    /// An attached media item.
    public struct Media: Decodable, Sendable, Hashable {
        public let url: String?
        public let contentType: String?
        public let sha256: String?
        public let size: Int?

        enum CodingKeys: String, CodingKey {
            case url
            case contentType = "content_type"
            case sha256
            case size
        }
    }

    /// The price, with `amount` as a decimal string.
    public struct Cost: Decodable, Sendable, Hashable {
        public let amount: String?
        public let currency: String?
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recordType = "record_type"
        case direction
        case type
        case messagingProfileID = "messaging_profile_id"
        case organizationID = "organization_id"
        case from
        case to
        case text
        case subject
        case media
        case webhookURL = "webhook_url"
        case webhookFailoverURL = "webhook_failover_url"
        case encoding
        case parts
        case tags
        case cost
        case receivedAt = "received_at"
        case sentAt = "sent_at"
        case completedAt = "completed_at"
        case validUntil = "valid_until"
        case errors
    }
}
