import Vapor

/// Searches, orders and manages phone numbers.
///
/// Get one from `app.telnyx.numbers.client` or `req.telnyx.numbers.client`. Every method throws
/// ``TelnyxError`` for a Telnyx error response.
public struct TelnyxNumbersClient: Sendable {
    let client: any Client
    let logger: Logger
    let configuration: TelnyxConfiguration

    /// Creates a client. Usually obtained from `app.telnyx.numbers.client` instead.
    public init(client: any Client, logger: Logger, configuration: TelnyxConfiguration) {
        self.client = client
        self.logger = logger
        self.configuration = configuration
    }

    private var http: TelnyxHTTP {
        TelnyxHTTP(client: client, logger: logger, configuration: configuration)
    }

    /// Searches for numbers that can be ordered (`GET /available_phone_numbers`). The endpoint is not paginated.
    public func searchAvailableNumbers(_ search: TelnyxAvailableNumberSearch) async throws -> TelnyxAvailableNumberSearchResult {
        try await http.sendRaw(
            .GET,
            path: "/available_phone_numbers",
            query: search.query,
            decoding: TelnyxAvailableNumberSearchResult.self
        )
    }

    /// Orders numbers (`POST /number_orders`). The order may still be `pending` when this returns.
    public func createNumberOrder(_ order: TelnyxNumberOrderRequest) async throws -> TelnyxNumberOrder {
        try await http.send(.POST, path: "/number_orders", body: order, decoding: TelnyxNumberOrder.self)
    }

    /// Fetches a number order (`GET /number_orders/{id}`), for example to poll a pending order.
    public func getNumberOrder(id: String) async throws -> TelnyxNumberOrder {
        try await http.send(
            .GET,
            path: "/number_orders/\(TelnyxHTTP.pathSegment(id))",
            decoding: TelnyxNumberOrder.self
        )
    }

    /// Lists one page of owned numbers (`GET /phone_numbers`).
    public func listPhoneNumbers(_ query: TelnyxPhoneNumberListQuery = TelnyxPhoneNumberListQuery()) async throws -> TelnyxPage<TelnyxPhoneNumber> {
        try await http.sendRaw(.GET, path: "/phone_numbers", query: query.query, decoding: TelnyxPage<TelnyxPhoneNumber>.self)
    }

    /// Lists every owned number matching `query` by walking the pages.
    ///
    /// Starts at `query.pageNumber` (default 1) and uses `query.pageSize` (default
    /// ``TelnyxPhoneNumberListQuery/maximumPageSize``). Stops after the page whose
    /// `meta.page_number` reaches `meta.total_pages`, on an empty page, or after `maximumPages`
    /// requests, whichever comes first.
    public func listAllPhoneNumbers(
        _ query: TelnyxPhoneNumberListQuery = TelnyxPhoneNumberListQuery(),
        maximumPages: Int = 1000
    ) async throws -> [TelnyxPhoneNumber] {
        var pageQuery: TelnyxPhoneNumberListQuery = query
        pageQuery.pageNumber = query.pageNumber ?? 1
        pageQuery.pageSize = query.pageSize ?? TelnyxPhoneNumberListQuery.maximumPageSize

        var numbers: [TelnyxPhoneNumber] = []
        var requests: Int = 0
        while requests < maximumPages {
            let page: TelnyxPage<TelnyxPhoneNumber> = try await listPhoneNumbers(pageQuery)
            requests += 1
            numbers.append(contentsOf: page.data)

            let current: Int = page.meta?.pageNumber ?? pageQuery.pageNumber ?? 1
            guard !page.data.isEmpty,
                  let totalPages: Int = page.meta?.totalPages,
                  current < totalPages
            else {
                break
            }
            pageQuery.pageNumber = current + 1
        }
        return numbers
    }

    /// Fetches an owned number by its resource id (`GET /phone_numbers/{id}`).
    ///
    /// `id` is the numeric resource id, not the E.164 number. Use ``findPhoneNumber(e164:)`` to
    /// look a number up by E.164.
    public func getPhoneNumber(id: String) async throws -> TelnyxPhoneNumber {
        try await http.send(.GET, path: phoneNumberPath(id), decoding: TelnyxPhoneNumber.self)
    }

    /// Finds an owned number by its E.164 form using the `filter[phone_number]` list filter,
    /// returning the first result whose `phone_number` matches exactly, or `nil`.
    public func findPhoneNumber(e164: String) async throws -> TelnyxPhoneNumber? {
        let query: TelnyxPhoneNumberListQuery = TelnyxPhoneNumberListQuery(
            pageSize: TelnyxPhoneNumberListQuery.maximumPageSize,
            phoneNumber: e164
        )
        let page: TelnyxPage<TelnyxPhoneNumber> = try await listPhoneNumbers(query)
        return page.data.first { (number: TelnyxPhoneNumber) -> Bool in number.phoneNumber == e164 }
    }

    /// Updates an owned number (`PATCH /phone_numbers/{id}`) and returns it.
    public func updatePhoneNumber(id: String, _ update: TelnyxPhoneNumberUpdate) async throws -> TelnyxPhoneNumber {
        try await http.send(.PATCH, path: phoneNumberPath(id), body: update, decoding: TelnyxPhoneNumber.self)
    }

    /// Assigns an owned number to a voice connection. Shorthand for ``updatePhoneNumber(id:_:)``.
    public func assignConnection(phoneNumberID: String, connectionID: String) async throws -> TelnyxPhoneNumber {
        try await updatePhoneNumber(id: phoneNumberID, TelnyxPhoneNumberUpdate(connectionID: .value(connectionID)))
    }

    /// Releases an owned number (`DELETE /phone_numbers/{id}`) and returns it with status `deleted`.
    ///
    /// Telnyx refuses this while `deletion_lock_enabled` is set.
    public func deletePhoneNumber(id: String) async throws -> TelnyxPhoneNumber {
        try await http.send(.DELETE, path: phoneNumberPath(id), decoding: TelnyxPhoneNumber.self)
    }

    /// Updates a number's messaging settings (`PATCH /phone_numbers/{id}/messaging`).
    public func updateMessagingSettings(
        phoneNumberID: String,
        _ update: TelnyxMessagingSettingsUpdate
    ) async throws -> TelnyxPhoneNumberMessagingSettings {
        try await http.send(
            .PATCH,
            path: "\(phoneNumberPath(phoneNumberID))/messaging",
            body: update,
            decoding: TelnyxPhoneNumberMessagingSettings.self
        )
    }

    /// Sets a number's messaging profile. Pass `nil` to unassign the current profile.
    public func setMessagingProfile(
        phoneNumberID: String,
        messagingProfileID: String?
    ) async throws -> TelnyxPhoneNumberMessagingSettings {
        let profile: TelnyxMessagingSettingsUpdate.Profile = messagingProfileID.map {
            (id: String) -> TelnyxMessagingSettingsUpdate.Profile in .assign(id)
        } ?? .unassign
        return try await updateMessagingSettings(
            phoneNumberID: phoneNumberID,
            TelnyxMessagingSettingsUpdate(messagingProfile: profile)
        )
    }

    private func phoneNumberPath(_ id: String) -> String {
        "/phone_numbers/\(TelnyxHTTP.pathSegment(id))"
    }
}
