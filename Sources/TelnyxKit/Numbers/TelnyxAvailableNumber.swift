/// Filters for `GET /available_phone_numbers`. Every filter is optional; `nil` filters are not sent.
public struct TelnyxAvailableNumberSearch: Sendable, Hashable {
    /// `filter[country_code]`, such as `"US"`.
    public var countryCode: String?
    /// `filter[national_destination_code]`: the area code (Telnyx has no separate area-code filter).
    public var nationalDestinationCode: String?
    /// `filter[locality]`, a city name.
    public var locality: String?
    /// `filter[administrative_area]`, such as a state.
    public var administrativeArea: String?
    /// `filter[rate_center]`.
    public var rateCenter: String?
    /// `filter[phone_number][starts_with]`.
    public var phoneNumberStartsWith: String?
    /// `filter[phone_number][ends_with]`.
    public var phoneNumberEndsWith: String?
    /// `filter[phone_number][contains]`.
    public var phoneNumberContains: String?
    /// `filter[phone_number_type]`.
    public var phoneNumberType: TelnyxPhoneNumberType?
    /// `filter[features]`: numbers must have all of these.
    ///
    /// Sent as repeated `filter[features][]=` parameters. Telnyx's reference does not specify how
    /// the array is encoded, so this encoding is unverified.
    public var features: [TelnyxNumberFeature]
    /// `filter[limit]`.
    public var limit: Int?
    /// `filter[best_effort]`.
    public var bestEffort: Bool?
    /// `filter[quickship]`.
    public var quickship: Bool?
    /// `filter[reservable]`.
    public var reservable: Bool?
    /// `filter[exclude_held_numbers]`.
    public var excludeHeldNumbers: Bool?

    public init(
        countryCode: String? = nil,
        nationalDestinationCode: String? = nil,
        locality: String? = nil,
        administrativeArea: String? = nil,
        rateCenter: String? = nil,
        phoneNumberStartsWith: String? = nil,
        phoneNumberEndsWith: String? = nil,
        phoneNumberContains: String? = nil,
        phoneNumberType: TelnyxPhoneNumberType? = nil,
        features: [TelnyxNumberFeature] = [],
        limit: Int? = nil,
        bestEffort: Bool? = nil,
        quickship: Bool? = nil,
        reservable: Bool? = nil,
        excludeHeldNumbers: Bool? = nil
    ) {
        self.countryCode = countryCode
        self.nationalDestinationCode = nationalDestinationCode
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.rateCenter = rateCenter
        self.phoneNumberStartsWith = phoneNumberStartsWith
        self.phoneNumberEndsWith = phoneNumberEndsWith
        self.phoneNumberContains = phoneNumberContains
        self.phoneNumberType = phoneNumberType
        self.features = features
        self.limit = limit
        self.bestEffort = bestEffort
        self.quickship = quickship
        self.reservable = reservable
        self.excludeHeldNumbers = excludeHeldNumbers
    }

    var query: TelnyxQuery {
        var query: TelnyxQuery = TelnyxQuery()
        query.add("filter[country_code]", countryCode)
        query.add("filter[national_destination_code]", nationalDestinationCode)
        query.add("filter[locality]", locality)
        query.add("filter[administrative_area]", administrativeArea)
        query.add("filter[rate_center]", rateCenter)
        query.add("filter[phone_number][starts_with]", phoneNumberStartsWith)
        query.add("filter[phone_number][ends_with]", phoneNumberEndsWith)
        query.add("filter[phone_number][contains]", phoneNumberContains)
        query.add("filter[phone_number_type]", phoneNumberType)
        for feature: TelnyxNumberFeature in features {
            // Unverified: the reference does not say how array filters are encoded.
            query.add("filter[features][]", feature)
        }
        query.add("filter[limit]", limit)
        query.add("filter[best_effort]", bestEffort)
        query.add("filter[quickship]", quickship)
        query.add("filter[reservable]", reservable)
        query.add("filter[exclude_held_numbers]", excludeHeldNumbers)
        return query
    }
}

/// The response of `GET /available_phone_numbers`.
public struct TelnyxAvailableNumberSearchResult: Decodable, Sendable {
    public let data: [TelnyxAvailableNumber]
    public let meta: Meta?

    public struct Meta: Decodable, Sendable, Hashable {
        public let totalResults: Int?
        public let bestEffortResults: Int?

        enum CodingKeys: String, CodingKey {
            case totalResults = "total_results"
            case bestEffortResults = "best_effort_results"
        }
    }

    enum CodingKeys: String, CodingKey {
        case data
        case meta
    }

    public init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        self.data = try container.decodeIfPresent([TelnyxAvailableNumber].self, forKey: .data) ?? []
        self.meta = try container.decodeIfPresent(Meta.self, forKey: .meta)
    }
}

/// A number that can be ordered.
public struct TelnyxAvailableNumber: Decodable, Sendable, Hashable {
    /// `"available_phone_number"`.
    public let recordType: String?
    /// The number in E.164 form.
    public let phoneNumber: String?
    public let vanityFormat: String?
    public let bestEffort: Bool?
    public let quickship: Bool?
    public let reservable: Bool?
    public let regionInformation: [Region]?
    public let costInformation: Cost?
    public let features: [Feature]?

    public struct Region: Decodable, Sendable, Hashable {
        public let regionType: TelnyxRegionType?
        public let regionName: String?

        enum CodingKeys: String, CodingKey {
            case regionType = "region_type"
            case regionName = "region_name"
        }
    }

    /// Prices as decimal strings, as Telnyx sends them.
    public struct Cost: Decodable, Sendable, Hashable {
        public let upfrontCost: String?
        public let monthlyCost: String?
        public let currency: String?

        enum CodingKeys: String, CodingKey {
            case upfrontCost = "upfront_cost"
            case monthlyCost = "monthly_cost"
            case currency
        }
    }

    public struct Feature: Decodable, Sendable, Hashable {
        public let name: TelnyxNumberFeature?
    }

    enum CodingKeys: String, CodingKey {
        case recordType = "record_type"
        case phoneNumber = "phone_number"
        case vanityFormat = "vanity_format"
        case bestEffort = "best_effort"
        case quickship
        case reservable
        case regionInformation = "region_information"
        case costInformation = "cost_information"
        case features
    }

    /// Whether `features` lists `feature`.
    public func has(_ feature: TelnyxNumberFeature) -> Bool {
        features?.contains { (item: Feature) -> Bool in item.name == feature } ?? false
    }
}
