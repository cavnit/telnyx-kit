import Foundation

/// The body of `POST /number_orders`.
public struct TelnyxNumberOrderRequest: Encodable, Sendable, Hashable {
    /// One number to order.
    public struct PhoneNumber: Encodable, Sendable, Hashable {
        /// The E.164 number, as returned by a search. Required.
        public var phoneNumber: String
        public var requirementGroupID: String?
        public var bundleID: String?

        public init(phoneNumber: String, requirementGroupID: String? = nil, bundleID: String? = nil) {
            self.phoneNumber = phoneNumber
            self.requirementGroupID = requirementGroupID
            self.bundleID = bundleID
        }

        enum CodingKeys: String, CodingKey {
            case phoneNumber = "phone_number"
            case requirementGroupID = "requirement_group_id"
            case bundleID = "bundle_id"
        }
    }

    public var phoneNumbers: [PhoneNumber]
    /// The voice connection to assign the numbers to.
    public var connectionID: String?
    /// The messaging profile to assign the numbers to.
    public var messagingProfileID: String?
    public var billingGroupID: String?
    public var customerReference: String?

    public init(
        phoneNumbers: [PhoneNumber],
        connectionID: String? = nil,
        messagingProfileID: String? = nil,
        billingGroupID: String? = nil,
        customerReference: String? = nil
    ) {
        self.phoneNumbers = phoneNumbers
        self.connectionID = connectionID
        self.messagingProfileID = messagingProfileID
        self.billingGroupID = billingGroupID
        self.customerReference = customerReference
    }

    /// Orders the given E.164 numbers with no per-number options.
    public init(
        phoneNumbers: [String],
        connectionID: String? = nil,
        messagingProfileID: String? = nil,
        billingGroupID: String? = nil,
        customerReference: String? = nil
    ) {
        self.init(
            phoneNumbers: phoneNumbers.map { (number: String) -> PhoneNumber in PhoneNumber(phoneNumber: number) },
            connectionID: connectionID,
            messagingProfileID: messagingProfileID,
            billingGroupID: billingGroupID,
            customerReference: customerReference
        )
    }

    enum CodingKeys: String, CodingKey {
        case phoneNumbers = "phone_numbers"
        case connectionID = "connection_id"
        case messagingProfileID = "messaging_profile_id"
        case billingGroupID = "billing_group_id"
        case customerReference = "customer_reference"
    }
}

/// A number order, as returned by `POST /number_orders` and `GET /number_orders/{id}`.
public struct TelnyxNumberOrder: Decodable, Sendable, Hashable {
    public let id: String?
    /// `"number_order"`.
    public let recordType: String?
    public let phoneNumbersCount: Int?
    public let connectionID: String?
    public let messagingProfileID: String?
    public let billingGroupID: String?
    public let customerReference: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let requirementsMet: Bool?
    public let subNumberOrdersIDs: [String]?
    public let status: TelnyxNumberOrderStatus?
    public let phoneNumbers: [PhoneNumber]?

    /// One number within an order.
    public struct PhoneNumber: Decodable, Sendable, Hashable {
        public let id: String?
        public let phoneNumber: String?
        public let countryISOAlpha2: String?
        public let countryCode: String?
        public let phoneNumberType: TelnyxPhoneNumberType?
        public let bundleID: String?
        public let requirementsMet: Bool?
        public let requirementsStatus: String?
        /// Kept as raw JSON: the reference does not describe the element shape.
        public let regulatoryRequirements: [TelnyxJSONValue]?
        public let status: TelnyxNumberOrderStatus?

        enum CodingKeys: String, CodingKey {
            case id
            case phoneNumber = "phone_number"
            case countryISOAlpha2 = "country_iso_alpha2"
            case countryCode = "country_code"
            case phoneNumberType = "phone_number_type"
            case bundleID = "bundle_id"
            case requirementsMet = "requirements_met"
            case requirementsStatus = "requirements_status"
            case regulatoryRequirements = "regulatory_requirements"
            case status
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recordType = "record_type"
        case phoneNumbersCount = "phone_numbers_count"
        case connectionID = "connection_id"
        case messagingProfileID = "messaging_profile_id"
        case billingGroupID = "billing_group_id"
        case customerReference = "customer_reference"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case requirementsMet = "requirements_met"
        case subNumberOrdersIDs = "sub_number_orders_ids"
        case status
        case phoneNumbers = "phone_numbers"
    }
}
