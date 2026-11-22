# TelnyxKit

A Vapor client for the [Telnyx](https://developers.telnyx.com) v2 API. One package, one configuration, three areas:

- **Numbers**: search available numbers, order them, list, update and release owned numbers, set a number's messaging profile.
- **Messaging**: send SMS and MMS, with optional idempotency keys.
- **Webhooks**: verify Ed25519 webhook signatures and decode events into typed payloads.

Errors from the API come back as a `TelnyxError` that carries the HTTP status, Telnyx's `errors` array and, for 429, the rate-limit headers.

## Requirements

- Swift 6.1+
- macOS 15.0+ or Linux

## Installation

Add TelnyxKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/cavnit/telnyx-kit.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "App",
        dependencies: [
            .product(name: "TelnyxKit", package: "telnyx-kit"),
        ]
    ),
]
```

## Configuration

```swift
import TelnyxKit

func configure(_ app: Application) throws {
    app.telnyx.configuration = TelnyxConfiguration(
        apiKey: Environment.get("TELNYX_API_KEY")!,
        publicKey: Environment.get("TELNYX_PUBLIC_KEY")
    )
}
```

| Environment Variable | Description                                                            |
|----------------------|------------------------------------------------------------------------|
| `TELNYX_API_KEY`     | Telnyx API key, sent as `Authorization: Bearer <key>`                  |
| `TELNYX_PUBLIC_KEY`  | Base64 webhook signing public key from the Telnyx portal (webhooks only) |

The base URL defaults to `https://api.telnyx.com/v2`. Pass `baseURL: TelnyxConfiguration.sandboxBaseURL` to use the sandbox. Webhook timestamps more than 300 seconds away from the current time are rejected; change that with `webhookTimestampTolerance:`.

Clients are available from the application (`app.telnyx.numbers.client`, `app.telnyx.messaging.client`) and from a request (`req.telnyx.numbers.client`, `req.telnyx.messaging.client`), which uses the request's logger.

## Numbers

Search for a number, order it, then assign it to a voice connection and a messaging profile:

```swift
let numbers = req.telnyx.numbers.client

let results = try await numbers.searchAvailableNumbers(
    TelnyxAvailableNumberSearch(
        countryCode: "US",
        nationalDestinationCode: "555", // the area code
        phoneNumberType: .local,
        features: [.sms, .voice],
        limit: 5
    )
)
guard let candidate = results.data.first?.phoneNumber else {
    throw Abort(.notFound)
}

let order = try await numbers.createNumberOrder(
    TelnyxNumberOrderRequest(phoneNumbers: [candidate], customerReference: "example-ref-1")
)
// Orders can stay `pending` for a while; poll with getNumberOrder(id:) until `.success`.

if let owned = try await numbers.findPhoneNumber(e164: candidate), let id = owned.id {
    _ = try await numbers.assignConnection(phoneNumberID: id, connectionID: "1494404757140276705")
    _ = try await numbers.setMessagingProfile(
        phoneNumberID: id,
        messagingProfileID: "4000eba1-a0c0-4563-9925-b25e842a7cb6"
    )
}
```

The `/phone_numbers/{id}` endpoints take the numeric resource id (such as `"1293384261075731499"`), not the E.164 number; `findPhoneNumber(e164:)` looks the id up. Use `listPhoneNumbers(_:)` for one page or `listAllPhoneNumbers(_:)` to walk every page. `TelnyxPhoneNumberUpdate.connectionID` is three-state: `nil` leaves it alone, `.value(id)` assigns, `.null` sends JSON `null`.

## Messaging

```swift
let message = try await req.telnyx.messaging.client.send(
    TelnyxOutboundMessage(
        to: "+15550100199",
        from: "+15550100123",
        text: "Your code is 123456"
    ),
    idempotencyKey: "signup-42"
)
```

The idempotency key must be 1–255 letters, digits, `-` or `_`; a malformed key throws before anything is sent.

## Webhooks

Verify and decode in a route. The helper reads the raw body bytes and the `telnyx-signature-ed25519` and `telnyx-timestamp` headers, and throws `TelnyxWebhookError` (an `AbortError`: 401 for a bad signature or timestamp, 400 for a missing or invalid body):

```swift
app.post("webhooks", "telnyx") { req async throws -> HTTPStatus in
    let event = try await req.telnyx.webhooks.verifiedEvent()

    switch event.payload {
    case .callInitiated(let call):
        req.logger.info("call initiated", metadata: ["callControlID": "\(call.callControlID ?? "")"])
    case .messageReceived(let message):
        // handle the inbound message
        _ = message
    case .messageSent, .messageFinalized:
        break
    case .unknown(let eventType, _):
        req.logger.debug("unhandled Telnyx event", metadata: ["eventType": "\(eventType)"])
    }
    return .ok
}
```

Event types this package does not model decode as `.unknown(eventType:payload:)` with the raw JSON payload, rather than failing.

Outside a route, use the pure form, which takes the body bytes and header values and an injectable `now`:

```swift
let verifier = try TelnyxWebhookVerifier(base64PublicKey: publicKey)
let event = try verifier.verifiedEvent(
    body: bodyBytes,
    signature: signatureHeader,
    timestamp: timestampHeader,
    now: Date()
)
```

## Errors

```swift
do {
    _ = try await numbers.createNumberOrder(order)
} catch let error as TelnyxError {
    if error.hasCode(.numbersNoLongerAvailable) {
        // search again
    } else if error.isRateLimited {
        let wait = error.rateLimit?.retryAfterSeconds
    }
}
```

`TelnyxError.api` holds the status, the decoded `errors` and, for 429, a `TelnyxRateLimit` with `x-ratelimit-limit`, `x-ratelimit-remaining`, `x-ratelimit-reset` and `retry-after` as raw strings. A response that is not in Telnyx's documented shape becomes `TelnyxError.invalidResponse` with the status and at most 512 bytes of the body (the API key is redacted from it). As an `AbortError`, `TelnyxError` maps to 502 (503 when rate limited), so an unhandled Telnyx 401 or 404 does not reach your own API's callers as theirs.

Status, type and event-type values are string-backed structs with constants for the documented values (`status == .active`); a value Telnyx adds later still decodes.

TelnyxKit logs at debug level only (method, path and status), plus a warning with status and error codes when a request fails. It never logs the API key, message text, request or response bodies, or query strings.

## Status

This package was written from Telnyx's published API reference and has not yet been run against the live API. Points the reference does not settle, and how the package handles them:

- **Array filters on number search.** `filter[features]` is sent as repeated `filter[features][]=` parameters. The reference does not specify the array encoding.
- **Unassigning a connection.** The reference does not say what value of `connection_id` unassigns a number's connection. `TelnyxPhoneNumberUpdate` can send a string, an explicit `null`, or omit the field; `.null` is the likely candidate.
- **E.164 as a resource id.** The reference documents `/phone_numbers/{id}` with the resource id only, so the client takes the id and offers `findPhoneNumber(e164:)`, built on the `filter[phone_number]` list filter. How that filter matches a full E.164 value with its leading `+` is also unverified; the helper sends the number as given and keeps only an exact match.
- **Webhook public key form.** Telnyx's examples disagree on whether the portal key is the raw 32-byte Ed25519 key or a 44-byte SPKI (X.509 DER) wrapper. Both are accepted.

## License

Apache License 2.0. See [LICENSE](LICENSE).
