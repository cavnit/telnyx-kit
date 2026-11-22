import Foundation
import Testing
import Vapor
@testable import TelnyxKit

@Suite("Numbers client")
struct NumbersClientTests {
    @Test("search sends bracketed, percent-encoded filters and decodes results")
    func searchAvailableNumbers() async throws {
        let body: String = """
        {
          "data": [{
            "record_type": "available_phone_number",
            "phone_number": "+15550100123",
            "vanity_format": null,
            "best_effort": false,
            "quickship": true,
            "reservable": true,
            "region_information": [
              {"region_type": "country_code", "region_name": "US"},
              {"region_type": "rate_center", "region_name": "EXAMPLEVILLE"},
              {"region_type": "state", "region_name": "IL"},
              {"region_type": "metro_area", "region_name": "Example Metro"}
            ],
            "cost_information": {"upfront_cost": "1.00", "monthly_cost": "1.50", "currency": "USD"},
            "features": [{"name": "sms"}, {"name": "voice"}, {"name": "brand_new_feature"}]
          }],
          "meta": {"total_results": 1, "best_effort_results": 0}
        }
        """
        let client: RecordingClient = RecordingClient(body: body)
        let search: TelnyxAvailableNumberSearch = TelnyxAvailableNumberSearch(
            countryCode: "US",
            nationalDestinationCode: "555",
            locality: "Example City",
            phoneNumberStartsWith: "+1555",
            phoneNumberType: .local,
            features: [.sms, .voice],
            limit: 5,
            bestEffort: false,
            excludeHeldNumbers: true
        )

        let result: TelnyxAvailableNumberSearchResult = try await Fixture.numbers(client).searchAvailableNumbers(search)

        let request: ClientRequest = try #require(client.lastRequest)
        #expect(request.method == .GET)
        #expect(request.url.string == "https://api.telnyx.com/v2/available_phone_numbers"
            + "?filter%5Bcountry_code%5D=US"
            + "&filter%5Bnational_destination_code%5D=555"
            + "&filter%5Blocality%5D=Example%20City"
            + "&filter%5Bphone_number%5D%5Bstarts_with%5D=%2B1555"
            + "&filter%5Bphone_number_type%5D=local"
            + "&filter%5Bfeatures%5D%5B%5D=sms"
            + "&filter%5Bfeatures%5D%5B%5D=voice"
            + "&filter%5Blimit%5D=5"
            + "&filter%5Bbest_effort%5D=false"
            + "&filter%5Bexclude_held_numbers%5D=true")
        #expect(request.headers.first(name: .authorization) == "Bearer \(Fixture.apiKey)")
        #expect(request.headers.first(name: .accept) == "application/json")
        #expect(request.body == nil)

        #expect(result.meta?.totalResults == 1)
        #expect(result.meta?.bestEffortResults == 0)
        let number: TelnyxAvailableNumber = try #require(result.data.first)
        #expect(number.phoneNumber == "+15550100123")
        #expect(number.quickship == true)
        #expect(number.vanityFormat == nil)
        #expect(number.costInformation?.monthlyCost == "1.50")
        #expect(number.regionInformation?.map { (region: TelnyxAvailableNumber.Region) -> TelnyxRegionType? in region.regionType }
            == [.countryCode, .rateCenter, .state, TelnyxRegionType(rawValue: "metro_area")])
        #expect(number.has(.sms))
        #expect(number.has(.voice))
        #expect(!number.has(.mms))
        #expect(number.features?.last?.name?.rawValue == "brand_new_feature")
    }

    @Test("an empty search sends no query string")
    func emptySearch() async throws {
        let client: RecordingClient = RecordingClient(body: "{\"data\": []}")
        let result: TelnyxAvailableNumberSearchResult = try await Fixture.numbers(client)
            .searchAvailableNumbers(TelnyxAvailableNumberSearch())
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/available_phone_numbers")
        #expect(result.data.isEmpty)
        #expect(result.meta == nil)
    }

    static let numberOrderResponse: String = """
    {
      "data": {
        "id": "12ade33a-21c0-473b-b055-b3c836e1c292",
        "record_type": "number_order",
        "phone_numbers_count": 1,
        "connection_id": "1494404757140276705",
        "messaging_profile_id": null,
        "billing_group_id": null,
        "customer_reference": "example-ref-1",
        "created_at": "2026-11-22T09:00:00.000Z",
        "updated_at": "2026-11-22T09:00:00Z",
        "requirements_met": true,
        "sub_number_orders_ids": ["7ecd5f3c-8e1a-4b2b-9b16-0b8b3e0f0a11"],
        "status": "pending",
        "phone_numbers": [{
          "id": "dc8e4d67-33a0-4cbb-af74-7b58f05bd494",
          "phone_number": "+15550100123",
          "country_iso_alpha2": "US",
          "country_code": "US",
          "phone_number_type": "local",
          "bundle_id": null,
          "requirements_met": true,
          "requirements_status": "approved",
          "regulatory_requirements": [{"requirement_id": "r-1", "field_type": "address"}],
          "status": "on-hold"
        }]
      }
    }
    """

    @Test("create number order posts the documented body")
    func createNumberOrder() async throws {
        let client: RecordingClient = RecordingClient(body: NumbersClientTests.numberOrderResponse)
        let order: TelnyxNumberOrderRequest = TelnyxNumberOrderRequest(
            phoneNumbers: [
                TelnyxNumberOrderRequest.PhoneNumber(phoneNumber: "+15550100123", requirementGroupID: "rg-1"),
                TelnyxNumberOrderRequest.PhoneNumber(phoneNumber: "+15550100124"),
            ],
            connectionID: "1494404757140276705",
            customerReference: "example-ref-1"
        )

        let created: TelnyxNumberOrder = try await Fixture.numbers(client).createNumberOrder(order)

        let request: ClientRequest = try #require(client.lastRequest)
        #expect(request.method == .POST)
        #expect(request.url.string == "https://api.telnyx.com/v2/number_orders")
        #expect(request.headers.first(name: .contentType) == "application/json")
        #expect(request.headers.bearerAuthorization?.token == Fixture.apiKey)
        let expected: TelnyxJSONValue = try Fixture.json("""
        {
          "phone_numbers": [
            {"phone_number": "+15550100123", "requirement_group_id": "rg-1"},
            {"phone_number": "+15550100124"}
          ],
          "connection_id": "1494404757140276705",
          "customer_reference": "example-ref-1"
        }
        """)
        #expect(try Fixture.jsonBody(request) == expected)

        #expect(created.id == "12ade33a-21c0-473b-b055-b3c836e1c292")
        #expect(created.status == .pending)
        #expect(created.phoneNumbersCount == 1)
        #expect(created.requirementsMet == true)
        #expect(created.subNumberOrdersIDs == ["7ecd5f3c-8e1a-4b2b-9b16-0b8b3e0f0a11"])
        #expect(created.createdAt == (try Fixture.date("2026-11-22T09:00:00Z")))
        let ordered: TelnyxNumberOrder.PhoneNumber = try #require(created.phoneNumbers?.first)
        #expect(ordered.phoneNumber == "+15550100123")
        #expect(ordered.phoneNumberType == .local)
        #expect(ordered.status?.rawValue == "on-hold")
        #expect(ordered.regulatoryRequirements?.first?["field_type"] == .string("address"))
    }

    @Test("get number order")
    func getNumberOrder() async throws {
        let client: RecordingClient = RecordingClient(body: NumbersClientTests.numberOrderResponse)
        let order: TelnyxNumberOrder = try await Fixture.numbers(client).getNumberOrder(id: "12ade33a-21c0-473b-b055-b3c836e1c292")
        #expect(client.lastRequest?.method == .GET)
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/number_orders/12ade33a-21c0-473b-b055-b3c836e1c292")
        #expect(order.recordType == "number_order")
    }

    @Test("list one page with paging, sort and filters")
    func listPhoneNumbers() async throws {
        let body: String = """
        {"data": [\(Fixture.phoneNumberJSON)], "meta": {"total_pages": 3, "total_results": 41, "page_number": 2, "page_size": 20}}
        """
        let client: RecordingClient = RecordingClient(body: body)
        let query: TelnyxPhoneNumberListQuery = TelnyxPhoneNumberListQuery(
            pageNumber: 2,
            pageSize: 20,
            sort: .purchasedAt,
            phoneNumber: "+15550100123",
            status: .active,
            tag: "support",
            source: .purchased,
            additionalFilters: ["voice.usage_payment_method": "pay-per-minute", "emergency_address_id": "42"]
        )

        let page: TelnyxPage<TelnyxPhoneNumber> = try await Fixture.numbers(client).listPhoneNumbers(query)

        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/phone_numbers"
            + "?page%5Bnumber%5D=2&page%5Bsize%5D=20&sort=purchased_at"
            + "&filter%5Bphone_number%5D=%2B15550100123"
            + "&filter%5Bstatus%5D=active"
            + "&filter%5Btag%5D=support"
            + "&filter%5Bsource%5D=purchased"
            + "&filter%5Bemergency_address_id%5D=42"
            + "&filter%5Bvoice.usage_payment_method%5D=pay-per-minute")
        #expect(page.meta?.totalPages == 3)
        #expect(page.meta?.totalResults == 41)
        #expect(page.meta?.pageNumber == 2)
        #expect(page.meta?.pageSize == 20)

        let number: TelnyxPhoneNumber = try #require(page.data.first)
        #expect(number.id == "1293384261075731499")
        #expect(number.phoneNumber == "+15550100123")
        #expect(number.status == .active)
        #expect(number.tags == ["support", "east"])
        #expect(number.phoneNumberType == .local)
        #expect(number.messagingProfileID == "UNAVAILABLE")
        #expect(number.messagingProfileName == nil)
        #expect(number.activatedAt == nil)
        #expect(number.hdVoiceEnabled == true)
        #expect(number.sourceType == .purchased)
        let purchased: Date = try #require(number.purchasedAt)
        #expect(abs(purchased.timeIntervalSince1970 - ((try Fixture.date("2026-10-01T12:00:01Z")).timeIntervalSince1970 + 0.123456)) < 0.000_01)
    }

    @Test("list all walks every page until total_pages")
    func listAllPhoneNumbers() async throws {
        func page(_ number: Int, ids: [String]) -> RecordingClient.Stub {
            let items: String = ids.map { (id: String) -> String in
                "{\"id\": \"\(id)\", \"phone_number\": \"+1555010\(id)\", \"status\": \"active\"}"
            }.joined(separator: ",")
            return RecordingClient.Stub(
                status: .ok,
                headers: [:],
                body: "{\"data\": [\(items)], \"meta\": {\"total_pages\": 3, \"total_results\": 5, \"page_number\": \(number), \"page_size\": 2}}"
            )
        }
        let client: RecordingClient = RecordingClient([
            page(1, ids: ["0101", "0102"]),
            page(2, ids: ["0103", "0104"]),
            page(3, ids: ["0105"]),
        ])

        let all: [TelnyxPhoneNumber] = try await Fixture.numbers(client)
            .listAllPhoneNumbers(TelnyxPhoneNumberListQuery(pageSize: 2, tag: "support"))

        #expect(all.compactMap { (number: TelnyxPhoneNumber) -> String? in number.id } == ["0101", "0102", "0103", "0104", "0105"])
        #expect(client.requests.map { (request: ClientRequest) -> String in request.url.string } == [
            "https://api.telnyx.com/v2/phone_numbers?page%5Bnumber%5D=1&page%5Bsize%5D=2&filter%5Btag%5D=support",
            "https://api.telnyx.com/v2/phone_numbers?page%5Bnumber%5D=2&page%5Bsize%5D=2&filter%5Btag%5D=support",
            "https://api.telnyx.com/v2/phone_numbers?page%5Bnumber%5D=3&page%5Bsize%5D=2&filter%5Btag%5D=support",
        ])
    }

    @Test("list all defaults to the maximum page size and stops on an empty page")
    func listAllStopsOnEmptyPage() async throws {
        let client: RecordingClient = RecordingClient([
            RecordingClient.Stub(status: .ok, headers: [:], body: "{\"data\": [], \"meta\": {\"total_pages\": 9, \"page_number\": 1}}"),
        ])
        let all: [TelnyxPhoneNumber] = try await Fixture.numbers(client).listAllPhoneNumbers()
        #expect(all.isEmpty)
        #expect(client.requests.count == 1)
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/phone_numbers?page%5Bnumber%5D=1&page%5Bsize%5D=250")
    }

    @Test("list all respects maximumPages")
    func listAllMaximumPages() async throws {
        let stub: RecordingClient.Stub = RecordingClient.Stub(
            status: .ok,
            headers: [:],
            body: "{\"data\": [{\"id\": \"1\"}], \"meta\": {\"total_pages\": 100}}"
        )
        let client: RecordingClient = RecordingClient([stub, stub, stub])
        let all: [TelnyxPhoneNumber] = try await Fixture.numbers(client).listAllPhoneNumbers(maximumPages: 2)
        #expect(all.count == 2)
        #expect(client.requests.count == 2)
    }

    @Test("get, find by E.164 and delete one number")
    func getFindDelete() async throws {
        let client: RecordingClient = RecordingClient([
            RecordingClient.Stub(status: .ok, headers: [:], body: Fixture.phoneNumberResponse()),
            RecordingClient.Stub(status: .ok, headers: [:], body: "{\"data\": [{\"id\": \"9\", \"phone_number\": \"+155501001234\"}, \(Fixture.phoneNumberJSON)], \"meta\": {\"total_pages\": 1}}"),
            RecordingClient.Stub(status: .ok, headers: [:], body: "{\"data\": [], \"meta\": {\"total_pages\": 0}}"),
            RecordingClient.Stub(status: .ok, headers: [:], body: Fixture.phoneNumberResponse(status: "deleted")),
        ])
        let numbers: TelnyxNumbersClient = Fixture.numbers(client)

        let fetched: TelnyxPhoneNumber = try await numbers.getPhoneNumber(id: "1293384261075731499")
        #expect(client.lastRequest?.method == .GET)
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/phone_numbers/1293384261075731499")
        #expect(fetched.connectionID == "1494404757140276705")

        let found: TelnyxPhoneNumber? = try await numbers.findPhoneNumber(e164: "+15550100123")
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/phone_numbers?page%5Bsize%5D=250&filter%5Bphone_number%5D=%2B15550100123")
        #expect(found?.id == "1293384261075731499")

        let missing: TelnyxPhoneNumber? = try await numbers.findPhoneNumber(e164: "+15550100999")
        #expect(missing == nil)

        let deleted: TelnyxPhoneNumber = try await numbers.deletePhoneNumber(id: "1293384261075731499")
        #expect(client.lastRequest?.method == .DELETE)
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/phone_numbers/1293384261075731499")
        #expect(client.lastRequest?.body == nil)
        #expect(deleted.status == .deleted)
    }

    @Test("ids are percent-encoded as one path segment")
    func pathSegmentEncoding() async throws {
        let client: RecordingClient = RecordingClient(body: Fixture.phoneNumberResponse())
        _ = try await Fixture.numbers(client).getPhoneNumber(id: "a/b c")
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/phone_numbers/a%2Fb%20c")
    }

    @Test("update sends only the fields that are set")
    func updatePhoneNumber() async throws {
        let client: RecordingClient = RecordingClient(body: Fixture.phoneNumberResponse())
        let update: TelnyxPhoneNumberUpdate = TelnyxPhoneNumberUpdate(
            tags: ["support"],
            customerReference: "example-ref-2",
            connectionID: .value("1494404757140276705")
        )

        let updated: TelnyxPhoneNumber = try await Fixture.numbers(client).updatePhoneNumber(id: "1293384261075731499", update)

        #expect(client.lastRequest?.method == .PATCH)
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/phone_numbers/1293384261075731499")
        #expect(try Fixture.jsonBody(client.lastRequest) == (try Fixture.json("""
        {"tags": ["support"], "customer_reference": "example-ref-2", "connection_id": "1494404757140276705"}
        """)))
        #expect(updated.customerReference == "example-ref-1")
    }

    @Test("connection_id: omitted, explicit null, or a value")
    func connectionIDTriState() throws {
        let encoder: JSONEncoder = TelnyxJSON.makeEncoder()
        func encoded(_ update: TelnyxPhoneNumberUpdate) throws -> String {
            String(decoding: try encoder.encode(update), as: UTF8.self)
        }
        #expect(try encoded(TelnyxPhoneNumberUpdate(tags: []))
            == #"{"tags":[]}"#)
        #expect(try encoded(TelnyxPhoneNumberUpdate(connectionID: .null))
            == #"{"connection_id":null}"#)
        #expect(try encoded(TelnyxPhoneNumberUpdate(connectionID: .value("1494404757140276705")))
            == #"{"connection_id":"1494404757140276705"}"#)
        #expect(try encoded(TelnyxPhoneNumberUpdate())
            == "{}")
    }

    @Test("assignConnection is a PATCH with connection_id")
    func assignConnection() async throws {
        let client: RecordingClient = RecordingClient(body: Fixture.phoneNumberResponse())
        _ = try await Fixture.numbers(client).assignConnection(phoneNumberID: "1293384261075731499", connectionID: "777")
        #expect(client.lastRequest?.method == .PATCH)
        #expect(try Fixture.jsonBody(client.lastRequest) == (try Fixture.json(#"{"connection_id": "777"}"#)))
    }

    @Test("messaging settings: assign, unassign, keep")
    func messagingSettings() async throws {
        let response: String = """
        {
          "data": {
            "record_type": "messaging_settings",
            "id": "1293384261075731499",
            "phone_number": "+15550100123",
            "messaging_profile_id": "4000eba1-a0c0-4563-9925-b25e842a7cb6",
            "messaging_product": "P2P",
            "traffic_type": "P2P",
            "country_code": "US",
            "type": "long-code",
            "features": {"sms": {"domestic_two_way": true}, "mms": null},
            "tags": ["support"],
            "created_at": "2026-10-01T12:00:00Z",
            "updated_at": "2026-11-22T09:00:00.5Z",
            "eligible_messaging_products": ["A2P"]
          }
        }
        """
        let stub: RecordingClient.Stub = RecordingClient.Stub(status: .ok, headers: [:], body: response)
        let client: RecordingClient = RecordingClient([stub, stub, stub])
        let numbers: TelnyxNumbersClient = Fixture.numbers(client)

        let assigned: TelnyxPhoneNumberMessagingSettings = try await numbers.setMessagingProfile(
            phoneNumberID: "1293384261075731499",
            messagingProfileID: "4000eba1-a0c0-4563-9925-b25e842a7cb6"
        )
        #expect(client.lastRequest?.method == .PATCH)
        #expect(client.lastRequest?.url.string == "https://api.telnyx.com/v2/phone_numbers/1293384261075731499/messaging")
        #expect(try Fixture.jsonBody(client.lastRequest) == (try Fixture.json(#"{"messaging_profile_id": "4000eba1-a0c0-4563-9925-b25e842a7cb6"}"#)))
        #expect(assigned.messagingProfileID == "4000eba1-a0c0-4563-9925-b25e842a7cb6")
        #expect(assigned.features?.sms?["domestic_two_way"] == .bool(true))
        #expect(assigned.features?.mms == nil || assigned.features?.mms == .null)
        #expect(assigned.tags == ["support"])

        _ = try await numbers.setMessagingProfile(phoneNumberID: "1293384261075731499", messagingProfileID: nil)
        #expect(try Fixture.jsonBody(client.lastRequest) == (try Fixture.json(#"{"messaging_profile_id": ""}"#)))

        _ = try await numbers.updateMessagingSettings(
            phoneNumberID: "1293384261075731499",
            TelnyxMessagingSettingsUpdate(messagingProduct: "A2P", tags: ["x"])
        )
        #expect(try Fixture.jsonBody(client.lastRequest) == (try Fixture.json(#"{"messaging_product": "A2P", "tags": ["x"]}"#)))
    }

    @Test("a custom base URL is used without a doubled slash")
    func customBaseURL() async throws {
        let client: RecordingClient = RecordingClient(body: "{\"data\": []}")
        let configuration: TelnyxConfiguration = TelnyxConfiguration(apiKey: Fixture.apiKey, baseURL: TelnyxConfiguration.sandboxBaseURL + "/")
        let numbers: TelnyxNumbersClient = TelnyxNumbersClient(client: client, logger: Fixture.logger(), configuration: configuration)
        _ = try await numbers.searchAvailableNumbers(TelnyxAvailableNumberSearch(countryCode: "US"))
        #expect(client.lastRequest?.url.string == "https://api-sandbox.telnyx.com/v2/available_phone_numbers?filter%5Bcountry_code%5D=US")
    }
}
