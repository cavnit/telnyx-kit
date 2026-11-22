import Foundation

/// A number owned by the account (`/phone_numbers`).
public struct TelnyxPhoneNumber: Decodable, Sendable, Hashable {
    /// The resource id: a numeric string such as `"1293384261075731499"`, not the E.164 number.
    public let id: String?
    public let recordType: String?
    /// The number in E.164 form.
    public let phoneNumber: String?
    public let countryISOAlpha2: String?
    public let status: TelnyxPhoneNumberStatus?
    public let tags: [String]?
    public let externalPin: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let purchasedAt: Date?
    public let activatedAt: Date?
    public let phoneNumberType: TelnyxPhoneNumberType?
    /// When `true`, `DELETE` is refused.
    public let deletionLockEnabled: Bool?
    public let connectionID: String?
    public let connectionName: String?
    /// The assigned messaging profile. Telnyx may send the literal string `"UNAVAILABLE"` here.
    public let messagingProfileID: String?
    public let messagingProfileName: String?
    public let billingGroupID: String?
    public let customerReference: String?
    public let emergencyEnabled: Bool?
    public let hdVoiceEnabled: Bool?
    public let sourceType: TelnyxPhoneNumberSource?

    enum CodingKeys: String, CodingKey {
        case id
        case recordType = "record_type"
        case phoneNumber = "phone_number"
        case countryISOAlpha2 = "country_iso_alpha2"
        case status
        case tags
        case externalPin = "external_pin"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case purchasedAt = "purchased_at"
        case activatedAt = "activated_at"
        case phoneNumberType = "phone_number_type"
        case deletionLockEnabled = "deletion_lock_enabled"
        case connectionID = "connection_id"
        case connectionName = "connection_name"
        case messagingProfileID = "messaging_profile_id"
        case messagingProfileName = "messaging_profile_name"
        case billingGroupID = "billing_group_id"
        case customerReference = "customer_reference"
        case emergencyEnabled = "emergency_enabled"
        case hdVoiceEnabled = "hd_voice_enabled"
        case sourceType = "source_type"
    }
}

/// Paging, sorting and filters for `GET /phone_numbers`. `nil` values are not sent.
public struct TelnyxPhoneNumberListQuery: Sendable, Hashable {
    /// `page[number]`, 1-based. Telnyx defaults to 1.
    public var pageNumber: Int?
    /// `page[size]`. Telnyx defaults to 20; the maximum is 250.
    public var pageSize: Int?
    /// `sort`.
    public var sort: TelnyxPhoneNumberSort?
    /// `filter[phone_number]`.
    public var phoneNumber: String?
    /// `filter[status]`.
    public var status: TelnyxPhoneNumberStatus?
    /// `filter[connection_id]`.
    public var connectionID: String?
    /// `filter[tag]`.
    public var tag: String?
    /// `filter[customer_reference]`.
    public var customerReference: String?
    /// `filter[country_iso_alpha2]`.
    public var countryISOAlpha2: String?
    /// `filter[source]`.
    public var source: TelnyxPhoneNumberSource?
    /// Any other filter, sent as `filter[<key>]=<value>` in key order.
    public var additionalFilters: [String: String]

    /// The largest page size Telnyx accepts.
    public static let maximumPageSize: Int = 250

    public init(
        pageNumber: Int? = nil,
        pageSize: Int? = nil,
        sort: TelnyxPhoneNumberSort? = nil,
        phoneNumber: String? = nil,
        status: TelnyxPhoneNumberStatus? = nil,
        connectionID: String? = nil,
        tag: String? = nil,
        customerReference: String? = nil,
        countryISOAlpha2: String? = nil,
        source: TelnyxPhoneNumberSource? = nil,
        additionalFilters: [String: String] = [:]
    ) {
        self.pageNumber = pageNumber
        self.pageSize = pageSize
        self.sort = sort
        self.phoneNumber = phoneNumber
        self.status = status
        self.connectionID = connectionID
        self.tag = tag
        self.customerReference = customerReference
        self.countryISOAlpha2 = countryISOAlpha2
        self.source = source
        self.additionalFilters = additionalFilters
    }

    var query: TelnyxQuery {
        var query: TelnyxQuery = TelnyxQuery()
        query.add("page[number]", pageNumber)
        query.add("page[size]", pageSize)
        query.add("sort", sort)
        query.add("filter[phone_number]", phoneNumber)
        query.add("filter[status]", status)
        query.add("filter[connection_id]", connectionID)
        query.add("filter[tag]", tag)
        query.add("filter[customer_reference]", customerReference)
        query.add("filter[country_iso_alpha2]", countryISOAlpha2)
        query.add("filter[source]", source)
        for key: String in additionalFilters.keys.sorted() {
            query.add("filter[\(key)]", additionalFilters[key])
        }
        return query
    }
}

/// One page of a paginated Telnyx list.
public struct TelnyxPage<Item: Decodable & Sendable>: Decodable, Sendable {
    public let data: [Item]
    public let meta: Meta?

    public struct Meta: Decodable, Sendable, Hashable {
        public let totalPages: Int?
        public let totalResults: Int?
        public let pageNumber: Int?
        public let pageSize: Int?

        enum CodingKeys: String, CodingKey {
            case totalPages = "total_pages"
            case totalResults = "total_results"
            case pageNumber = "page_number"
            case pageSize = "page_size"
        }
    }

    enum CodingKeys: String, CodingKey {
        case data
        case meta
    }

    public init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decodeIfPresent([Item].self, forKey: .data) ?? []
        self.meta = try container.decodeIfPresent(Meta.self, forKey: .meta)
    }
}

/// The body of `PATCH /phone_numbers/{id}`. Only non-`nil` fields are sent.
public struct TelnyxPhoneNumberUpdate: Encodable, Sendable {
    /// Replaces the number's tags.
    public var tags: [String]?
    public var externalPin: String?
    public var hdVoiceEnabled: Bool?
    public var customerReference: String?
    public var addressID: String?
    /// The voice connection: `nil` leaves it unchanged (the key is omitted), `.value(id)` assigns,
    /// `.null` sends an explicit JSON `null`.
    ///
    /// Telnyx's reference does not say which value unassigns a connection. Sending `.null` is the
    /// likely candidate but is unverified; check the number afterwards.
    public var connectionID: TelnyxNullable<String>?
    public var billingGroupID: String?

    public init(
        tags: [String]? = nil,
        externalPin: String? = nil,
        hdVoiceEnabled: Bool? = nil,
        customerReference: String? = nil,
        addressID: String? = nil,
        connectionID: TelnyxNullable<String>? = nil,
        billingGroupID: String? = nil
    ) {
        self.tags = tags
        self.externalPin = externalPin
        self.hdVoiceEnabled = hdVoiceEnabled
        self.customerReference = customerReference
        self.addressID = addressID
        self.connectionID = connectionID
        self.billingGroupID = billingGroupID
    }

    enum CodingKeys: String, CodingKey {
        case tags
        case externalPin = "external_pin"
        case hdVoiceEnabled = "hd_voice_enabled"
        case customerReference = "customer_reference"
        case addressID = "address_id"
        case connectionID = "connection_id"
        case billingGroupID = "billing_group_id"
    }
}
