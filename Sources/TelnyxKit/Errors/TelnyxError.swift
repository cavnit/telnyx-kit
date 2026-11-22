import Vapor

/// An error returned by, or while talking to, the Telnyx API.
///
/// As an `AbortError` it maps to a generic upstream status (502, or 503 when rate limited) with a
/// reason that names the HTTP status and error codes only, so letting it propagate out of a route
/// does not forward Telnyx's own 401/404 or any error detail to your API's callers.
public enum TelnyxError: Error, Sendable {
    /// Telnyx answered with a non-2xx status and the documented `{"errors": [...]}` body.
    ///
    /// `rateLimit` is set when the status is 429.
    case api(status: HTTPResponseStatus, errors: [TelnyxAPIError], rateLimit: TelnyxRateLimit?)

    /// The response did not have the documented shape: a non-2xx status without a decodable
    /// `errors` array, or a 2xx body that could not be decoded.
    ///
    /// `bodySnippet` is at most ``TelnyxError/maximumSnippetLength`` bytes of the body (lossy UTF-8)
    /// with any occurrence of the API key replaced. `reason` describes the decoding failure, if any.
    /// `rateLimit` is set when the status is 429.
    case invalidResponse(status: HTTPResponseStatus, bodySnippet: String, reason: String?, rateLimit: TelnyxRateLimit?)

    /// The request was rejected before it was sent (for example a malformed idempotency key).
    case invalidRequest(String)

    /// The largest body snippet kept in ``invalidResponse(status:bodySnippet:reason:rateLimit:)``.
    public static let maximumSnippetLength: Int = 512

    /// The HTTP status Telnyx returned, if a response was received.
    public var httpStatus: HTTPResponseStatus? {
        switch self {
        case .api(let status, _, _), .invalidResponse(let status, _, _, _):
            return status
        case .invalidRequest:
            return nil
        }
    }

    /// The decoded `errors` array, empty when the response did not carry one.
    public var errors: [TelnyxAPIError] {
        guard case .api(_, let errors, _) = self else {
            return []
        }
        return errors
    }

    /// The rate-limit headers, present when Telnyx returned 429.
    public var rateLimit: TelnyxRateLimit? {
        switch self {
        case .api(_, _, let rateLimit), .invalidResponse(_, _, _, let rateLimit):
            return rateLimit
        case .invalidRequest:
            return nil
        }
    }

    /// Whether any decoded error carries `code`.
    public func hasCode(_ code: TelnyxErrorCode) -> Bool {
        errors.contains { (error: TelnyxAPIError) -> Bool in error.code == code }
    }

    /// Whether Telnyx refused the request for exceeding a rate limit (HTTP 429 or code 10011).
    public var isRateLimited: Bool {
        httpStatus == .tooManyRequests || hasCode(.rateLimitExceeded)
    }
}

extension TelnyxError: AbortError {
    public var status: HTTPResponseStatus {
        switch self {
        case .api, .invalidResponse:
            return isRateLimited ? .serviceUnavailable : .badGateway
        case .invalidRequest:
            return .badRequest
        }
    }

    public var reason: String {
        switch self {
        case .api(let status, let errors, _):
            let codes: [String] = errors.compactMap { (error: TelnyxAPIError) -> String? in error.code?.rawValue }
            let codeText: String = codes.isEmpty ? "" : ", codes \(codes.joined(separator: ","))"
            return "Telnyx API request failed (status \(status.code)\(codeText))"
        case .invalidResponse(let status, _, _, _):
            return "Telnyx API returned an unexpected response (status \(status.code))"
        case .invalidRequest(let message):
            return "Invalid Telnyx request: \(message)"
        }
    }
}

extension TelnyxError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .api(let status, let errors, let rateLimit):
            // Only code and title: `detail` can name phone numbers.
            let details: String = errors.map { (error: TelnyxAPIError) -> String in
                "\(error.code?.rawValue ?? "?"): \(error.title ?? "")"
            }.joined(separator: "; ")
            let limit: String = rateLimit.map { (rate: TelnyxRateLimit) -> String in ", \(rate)" } ?? ""
            return "TelnyxError.api(status: \(status.code), errors: [\(details)]\(limit))"
        case .invalidResponse(let status, let snippet, let reason, _):
            // The snippet can contain phone numbers or message text, so it is left out of the
            // description (which loggers and Vapor's ErrorMiddleware print) and kept only in the case.
            return "TelnyxError.invalidResponse(status: \(status.code), reason: \(reason ?? "none"), bodySnippetBytes: \(snippet.utf8.count))"
        case .invalidRequest(let message):
            return "TelnyxError.invalidRequest(\(message))"
        }
    }
}

/// One entry of the `errors` array in a Telnyx error response.
public struct TelnyxAPIError: Codable, Hashable, Sendable {
    /// The Telnyx error code, such as `"10005"`.
    public let code: TelnyxErrorCode?
    public let title: String?
    public let detail: String?
    public let source: Source?
    public let meta: Meta?

    /// Where in the request the error was found.
    public struct Source: Codable, Hashable, Sendable {
        /// A JSON pointer into the request body, such as `/phone_numbers/0`.
        public let pointer: String?
        /// The query parameter at fault.
        public let parameter: String?

        public init(pointer: String? = nil, parameter: String? = nil) {
            self.pointer = pointer
            self.parameter = parameter
        }
    }

    /// Extra information about the error.
    public struct Meta: Codable, Hashable, Sendable {
        /// A documentation link for the error code.
        public let url: String?

        public init(url: String? = nil) {
            self.url = url
        }
    }

    public init(
        code: TelnyxErrorCode? = nil,
        title: String? = nil,
        detail: String? = nil,
        source: Source? = nil,
        meta: Meta? = nil
    ) {
        self.code = code
        self.title = title
        self.detail = detail
        self.source = source
        self.meta = meta
    }
}

/// A Telnyx error code. Codes are strings on the wire; unlisted codes decode as-is.
public struct TelnyxErrorCode: TelnyxOpenEnum {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// `10005`: resource not found.
    public static let notFound: TelnyxErrorCode = "10005"
    /// `10009`: authentication failed.
    public static let authenticationFailed: TelnyxErrorCode = "10009"
    /// `10010`: authorization failed.
    public static let authorizationFailed: TelnyxErrorCode = "10010"
    /// `10011`: too many requests.
    public static let rateLimitExceeded: TelnyxErrorCode = "10011"
    /// `85001`: the requested numbers are no longer available.
    public static let numbersNoLongerAvailable: TelnyxErrorCode = "85001"
}

/// The rate-limit headers from a 429 response.
///
/// Telnyx documents the format of `x-ratelimit-reset` as product-specific, so every value is kept
/// as the raw header string.
public struct TelnyxRateLimit: Hashable, Sendable, CustomStringConvertible {
    /// `x-ratelimit-limit`.
    public let limit: String?
    /// `x-ratelimit-remaining`.
    public let remaining: String?
    /// `x-ratelimit-reset`.
    public let reset: String?
    /// `retry-after`.
    public let retryAfter: String?

    public init(limit: String? = nil, remaining: String? = nil, reset: String? = nil, retryAfter: String? = nil) {
        self.limit = limit
        self.remaining = remaining
        self.reset = reset
        self.retryAfter = retryAfter
    }

    init(headers: HTTPHeaders) {
        self.init(
            limit: headers.first(name: "x-ratelimit-limit"),
            remaining: headers.first(name: "x-ratelimit-remaining"),
            reset: headers.first(name: "x-ratelimit-reset"),
            retryAfter: headers.first(name: "retry-after")
        )
    }

    /// `retry-after` as whole seconds, when it is a plain integer (the HTTP-date form is not parsed).
    public var retryAfterSeconds: Int? {
        guard let retryAfter: String = retryAfter else {
            return nil
        }
        return Int(retryAfter.trimmingCharacters(in: .whitespaces))
    }

    public var description: String {
        "rateLimit(limit: \(limit ?? "nil"), remaining: \(remaining ?? "nil"), reset: \(reset ?? "nil"), retryAfter: \(retryAfter ?? "nil"))"
    }
}
