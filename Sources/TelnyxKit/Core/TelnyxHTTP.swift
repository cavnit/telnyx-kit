import Foundation
import Vapor

/// `{"data": ...}`, the wrapper around every single-resource Telnyx response.
struct TelnyxDataEnvelope<Value: Decodable>: Decodable {
    let data: Value
}

/// `{"errors": [...]}`, the documented Telnyx error body.
struct TelnyxErrorEnvelope: Decodable {
    let errors: [TelnyxAPIError]
}

/// The shared request path for every Telnyx client: builds the URL, adds auth, sends, maps errors.
///
/// Logging: one debug line per request with method, path (never the query, which can hold phone
/// numbers) and status; a warning on failure with status and error codes only. The API key, request
/// and response bodies are never logged.
struct TelnyxHTTP: Sendable {
    let client: any Client
    let logger: Logger
    let configuration: TelnyxConfiguration

    /// Percent-encodes one path segment (resource ids).
    static func pathSegment(_ value: String) -> String {
        TelnyxQuery.percentEncode(value)
    }

    func url(path: String, query: TelnyxQuery) -> String {
        let base: String = "\(configuration.baseURL)\(path)"
        return query.isEmpty ? base : "\(base)?\(query.encoded)"
    }

    /// Sends a request with an optional JSON body and decodes `{"data": Value}`.
    func send<Value: Decodable>(
        _ method: HTTPMethod,
        path: String,
        query: TelnyxQuery = TelnyxQuery(),
        body: (any Encodable)? = nil,
        headers extraHeaders: HTTPHeaders = [:],
        decoding: Value.Type
    ) async throws -> Value {
        let response: ClientResponse = try await perform(method, path: path, query: query, body: body, headers: extraHeaders)
        let envelope: TelnyxDataEnvelope<Value> = try decode(TelnyxDataEnvelope<Value>.self, from: response)
        return envelope.data
    }

    /// Sends a request and decodes the whole body as `Value`.
    func sendRaw<Value: Decodable>(
        _ method: HTTPMethod,
        path: String,
        query: TelnyxQuery = TelnyxQuery(),
        decoding: Value.Type
    ) async throws -> Value {
        let response: ClientResponse = try await perform(method, path: path, query: query, body: nil, headers: [:])
        return try decode(Value.self, from: response)
    }

    private func perform(
        _ method: HTTPMethod,
        path: String,
        query: TelnyxQuery,
        body: (any Encodable)?,
        headers extraHeaders: HTTPHeaders
    ) async throws -> ClientResponse {
        var headers: HTTPHeaders = extraHeaders
        headers.bearerAuthorization = BearerAuthorization(token: configuration.apiKey)
        headers.replaceOrAdd(name: .accept, value: "application/json")

        var bodyBuffer: ByteBuffer? = nil
        if let body: any Encodable = body {
            let encoder: JSONEncoder = TelnyxJSON.makeEncoder()
            let data: Data = try encoder.encode(body)
            bodyBuffer = ByteBuffer(data: data)
            headers.replaceOrAdd(name: .contentType, value: "application/json")
        }

        let request: ClientRequest = ClientRequest(
            method: method,
            url: URI(string: url(path: path, query: query)),
            headers: headers,
            body: bodyBuffer
        )

        logger.debug("Telnyx request", metadata: ["method": "\(method.rawValue)", "path": "\(path)"])
        let response: ClientResponse = try await client.send(request).get()
        logger.debug("Telnyx response", metadata: [
            "method": "\(method.rawValue)",
            "path": "\(path)",
            "status": "\(response.status.code)",
        ])

        guard (200..<300).contains(response.status.code) else {
            throw failure(for: response, method: method, path: path)
        }
        return response
    }

    private func failure(for response: ClientResponse, method: HTTPMethod, path: String) -> TelnyxError {
        let rateLimit: TelnyxRateLimit? = response.status == .tooManyRequests ? TelnyxRateLimit(headers: response.headers) : nil
        let bytes: Data = bodyData(response)

        if let envelope: TelnyxErrorEnvelope = try? TelnyxJSON.makeDecoder().decode(TelnyxErrorEnvelope.self, from: bytes) {
            let codes: String = envelope.errors
                .compactMap { (error: TelnyxAPIError) -> String? in error.code?.rawValue }
                .joined(separator: ",")
            logger.warning("Telnyx request failed", metadata: [
                "method": "\(method.rawValue)",
                "path": "\(path)",
                "status": "\(response.status.code)",
                "codes": "\(codes)",
            ])
            return .api(status: response.status, errors: envelope.errors, rateLimit: rateLimit)
        }

        logger.warning("Telnyx request failed with an undocumented body", metadata: [
            "method": "\(method.rawValue)",
            "path": "\(path)",
            "status": "\(response.status.code)",
        ])
        return .invalidResponse(status: response.status, bodySnippet: snippet(bytes), reason: nil, rateLimit: rateLimit)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from response: ClientResponse) throws -> Value {
        let bytes: Data = bodyData(response)
        do {
            return try TelnyxJSON.makeDecoder().decode(Value.self, from: bytes)
        } catch {
            logger.warning("Telnyx response could not be decoded", metadata: ["status": "\(response.status.code)"])
            throw TelnyxError.invalidResponse(
                status: response.status,
                bodySnippet: snippet(bytes),
                reason: TelnyxHTTP.describe(error),
                rateLimit: nil
            )
        }
    }

    private func bodyData(_ response: ClientResponse) -> Data {
        guard let buffer: ByteBuffer = response.body else {
            return Data()
        }
        return Data(buffer: buffer, byteTransferStrategy: .automatic)
    }

    /// A bounded, key-free excerpt of a response body.
    func snippet(_ bytes: Data) -> String {
        var text: String = String(decoding: bytes, as: UTF8.self)
        if !configuration.apiKey.isEmpty {
            text = text.replacingOccurrences(of: configuration.apiKey, with: "<redacted>")
        }
        var result: String = ""
        var length: Int = 0
        for character: Character in text {
            let size: Int = character.utf8.count
            guard length + size <= TelnyxError.maximumSnippetLength else {
                break
            }
            result.append(character)
            length += size
        }
        return result
    }

    /// A short description of a decoding error naming the coding path, never the values.
    static func describe(_ error: any Error) -> String {
        guard let decodingError: DecodingError = error as? DecodingError else {
            return String(describing: type(of: error))
        }
        func path(_ codingPath: [any CodingKey]) -> String {
            codingPath.map { (key: any CodingKey) -> String in key.intValue.map(String.init) ?? key.stringValue }
                .joined(separator: ".")
        }
        switch decodingError {
        case .typeMismatch(_, let context):
            return "type mismatch at \(path(context.codingPath))"
        case .valueNotFound(_, let context):
            return "missing value at \(path(context.codingPath))"
        case .keyNotFound(let key, let context):
            let prefix: String = path(context.codingPath)
            return "missing key \(prefix.isEmpty ? "" : prefix + ".")\(key.stringValue)"
        case .dataCorrupted(let context):
            return "invalid data at \(path(context.codingPath))"
        @unknown default:
            return "decoding failed"
        }
    }
}
