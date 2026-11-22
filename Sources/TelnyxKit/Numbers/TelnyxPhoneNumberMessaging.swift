import Foundation

/// The body of `PATCH /phone_numbers/{id}/messaging`. `nil` fields are not sent.
public struct TelnyxMessagingSettingsUpdate: Encodable, Sendable, Hashable {
    /// What to do with the number's messaging profile.
    public enum Profile: Sendable, Hashable {
        /// Assign the profile with this id.
        case assign(String)
        /// Remove the current profile (sent as `""`).
        case unassign
    }

    /// `nil` keeps the current profile (the key is omitted).
    public var messagingProfile: Profile?
    public var messagingProduct: String?
    public var tags: [String]?

    public init(messagingProfile: Profile? = nil, messagingProduct: String? = nil, tags: [String]? = nil) {
        self.messagingProfile = messagingProfile
        self.messagingProduct = messagingProduct
        self.tags = tags
    }

    enum CodingKeys: String, CodingKey {
        case messagingProfileID = "messaging_profile_id"
        case messagingProduct = "messaging_product"
        case tags
    }

    public func encode(to encoder: any Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        switch messagingProfile {
        case .assign(let id):
            try container.encode(id, forKey: .messagingProfileID)
        case .unassign:
            try container.encode("", forKey: .messagingProfileID)
        case nil:
            break
        }
        try container.encodeIfPresent(messagingProduct, forKey: .messagingProduct)
        try container.encodeIfPresent(tags, forKey: .tags)
    }
}

/// A number's messaging settings, as returned by `PATCH /phone_numbers/{id}/messaging`.
public struct TelnyxPhoneNumberMessagingSettings: Decodable, Sendable, Hashable {
    public let recordType: String?
    public let id: String?
    public let phoneNumber: String?
    public let messagingProfileID: String?
    public let messagingProduct: String?
    public let trafficType: String?
    public let countryCode: String?
    public let type: String?
    public let features: Features?
    public let tags: [String]?
    public let createdAt: Date?
    public let updatedAt: Date?

    /// SMS and MMS capability. Kept as raw JSON: the reference does not describe their shape.
    public struct Features: Decodable, Sendable, Hashable {
        public let sms: TelnyxJSONValue?
        public let mms: TelnyxJSONValue?
    }

    enum CodingKeys: String, CodingKey {
        case recordType = "record_type"
        case id
        case phoneNumber = "phone_number"
        case messagingProfileID = "messaging_profile_id"
        case messagingProduct = "messaging_product"
        case trafficType = "traffic_type"
        case countryCode = "country_code"
        case type
        case features
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
