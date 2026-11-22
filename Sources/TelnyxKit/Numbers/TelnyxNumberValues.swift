/// A phone number type (`phone_number_type`). Unlisted values decode as-is.
public struct TelnyxPhoneNumberType: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let local: TelnyxPhoneNumberType = "local"
    public static let tollFree: TelnyxPhoneNumberType = "toll_free"
    public static let mobile: TelnyxPhoneNumberType = "mobile"
    public static let national: TelnyxPhoneNumberType = "national"
    public static let sharedCost: TelnyxPhoneNumberType = "shared_cost"
}

/// A phone number feature, used in searches and in search results. Unlisted values decode as-is.
public struct TelnyxNumberFeature: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let sms: TelnyxNumberFeature = "sms"
    public static let mms: TelnyxNumberFeature = "mms"
    public static let voice: TelnyxNumberFeature = "voice"
    public static let fax: TelnyxNumberFeature = "fax"
    public static let emergency: TelnyxNumberFeature = "emergency"
    public static let hdVoice: TelnyxNumberFeature = "hd_voice"
    public static let internationalSMS: TelnyxNumberFeature = "international_sms"
    public static let localCalling: TelnyxNumberFeature = "local_calling"
}

/// The kind of region in an available number's `region_information`. Unlisted values decode as-is.
public struct TelnyxRegionType: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let countryCode: TelnyxRegionType = "country_code"
    public static let rateCenter: TelnyxRegionType = "rate_center"
    public static let state: TelnyxRegionType = "state"
    public static let location: TelnyxRegionType = "location"
}

/// The status of a number order, or of one number within it. Unlisted values decode as-is.
public struct TelnyxNumberOrderStatus: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let pending: TelnyxNumberOrderStatus = "pending"
    public static let success: TelnyxNumberOrderStatus = "success"
    public static let failure: TelnyxNumberOrderStatus = "failure"
}

/// The status of an owned phone number. Unlisted values decode as-is.
public struct TelnyxPhoneNumberStatus: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let purchasePending: TelnyxPhoneNumberStatus = "purchase-pending"
    public static let purchaseFailed: TelnyxPhoneNumberStatus = "purchase-failed"
    public static let portPending: TelnyxPhoneNumberStatus = "port-pending"
    public static let portFailed: TelnyxPhoneNumberStatus = "port-failed"
    public static let active: TelnyxPhoneNumberStatus = "active"
    public static let deleted: TelnyxPhoneNumberStatus = "deleted"
    public static let emergencyOnly: TelnyxPhoneNumberStatus = "emergency-only"
    public static let portedOut: TelnyxPhoneNumberStatus = "ported-out"
    public static let portOutPending: TelnyxPhoneNumberStatus = "port-out-pending"
    public static let requirementInfoPending: TelnyxPhoneNumberStatus = "requirement-info-pending"
    public static let requirementInfoUnderReview: TelnyxPhoneNumberStatus = "requirement-info-under-review"
    public static let requirementInfoException: TelnyxPhoneNumberStatus = "requirement-info-exception"
    public static let provisionPending: TelnyxPhoneNumberStatus = "provision-pending"
}

/// A sort order for listing phone numbers (`sort`). Unlisted values are sent as-is.
public struct TelnyxPhoneNumberSort: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let purchasedAt: TelnyxPhoneNumberSort = "purchased_at"
    public static let phoneNumber: TelnyxPhoneNumberSort = "phone_number"
    public static let connectionName: TelnyxPhoneNumberSort = "connection_name"
    public static let usagePaymentMethod: TelnyxPhoneNumberSort = "usage_payment_method"
}

/// How a number came to the account (`filter[source]`, and assumed for `source_type`). Unlisted values decode as-is.
public struct TelnyxPhoneNumberSource: TelnyxOpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let ported: TelnyxPhoneNumberSource = "ported"
    public static let purchased: TelnyxPhoneNumberSource = "purchased"
}
