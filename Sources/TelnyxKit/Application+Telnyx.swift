import Vapor

extension Application {
    /// TelnyxKit's entry point on `Application`: `app.telnyx`.
    public struct Telnyx {
        let application: Application

        struct ConfigurationKey: StorageKey {
            typealias Value = TelnyxConfiguration
        }

        /// The configuration shared by every area. Set it once in `configure.swift`.
        ///
        /// Reading it before it has been set is a programmer error and stops the process.
        public var configuration: TelnyxConfiguration {
            get {
                guard let config: TelnyxConfiguration = application.storage[ConfigurationKey.self] else {
                    fatalError("TelnyxKit not configured. Use app.telnyx.configuration = ...")
                }
                return config
            }
            nonmutating set {
                application.storage[ConfigurationKey.self] = newValue
            }
        }

        /// Phone number search, ordering and management.
        public var numbers: Numbers { .init(application: application) }
        /// Sending messages.
        public var messaging: Messaging { .init(application: application) }
        /// Webhook verification.
        public var webhooks: Webhooks { .init(application: application) }

        /// `app.telnyx.numbers`.
        public struct Numbers {
            let application: Application

            /// The shared configuration (set it through `app.telnyx.configuration`).
            public var configuration: TelnyxConfiguration {
                application.telnyx.configuration
            }

            public var client: TelnyxNumbersClient {
                .init(
                    client: application.client,
                    logger: application.logger,
                    configuration: configuration
                )
            }
        }

        /// `app.telnyx.messaging`.
        public struct Messaging {
            let application: Application

            /// The shared configuration (set it through `app.telnyx.configuration`).
            public var configuration: TelnyxConfiguration {
                application.telnyx.configuration
            }

            public var client: TelnyxMessagingClient {
                .init(
                    client: application.client,
                    logger: application.logger,
                    configuration: configuration
                )
            }
        }

        /// `app.telnyx.webhooks`.
        public struct Webhooks {
            let application: Application

            /// The shared configuration (set it through `app.telnyx.configuration`).
            public var configuration: TelnyxConfiguration {
                application.telnyx.configuration
            }

            /// A verifier built from the configured public key and tolerance.
            ///
            /// Throws ``TelnyxWebhookError/publicKeyNotConfigured`` or
            /// ``TelnyxWebhookError/invalidPublicKey``.
            public var verifier: TelnyxWebhookVerifier {
                get throws {
                    try TelnyxWebhookVerifier(configuration: configuration)
                }
            }
        }
    }

    /// TelnyxKit's clients and configuration.
    public var telnyx: Telnyx {
        .init(application: self)
    }
}

extension Request {
    /// TelnyxKit's entry point on `Request`: `req.telnyx`. Clients use the request's client and logger.
    public struct Telnyx {
        let request: Request

        public var numbers: Numbers { .init(request: request) }
        public var messaging: Messaging { .init(request: request) }
        public var webhooks: Webhooks { .init(request: request) }

        /// `req.telnyx.numbers`.
        public struct Numbers {
            let request: Request

            public var client: TelnyxNumbersClient {
                let config: TelnyxConfiguration = request.application.telnyx.configuration
                return .init(
                    client: request.client,
                    logger: request.logger,
                    configuration: config
                )
            }
        }

        /// `req.telnyx.messaging`.
        public struct Messaging {
            let request: Request

            public var client: TelnyxMessagingClient {
                let config: TelnyxConfiguration = request.application.telnyx.configuration
                return .init(
                    client: request.client,
                    logger: request.logger,
                    configuration: config
                )
            }
        }

        /// `req.telnyx.webhooks`.
        public struct Webhooks {
            let request: Request

            /// Verifies this request as a Telnyx webhook and decodes its event.
            ///
            /// Throws ``TelnyxWebhookError`` (an `AbortError`: 401 for a bad signature or timestamp).
            public func verifiedEvent(now: Date = Date()) async throws -> TelnyxWebhookEvent {
                let verifier: TelnyxWebhookVerifier = try request.application.telnyx.webhooks.verifier
                return try await verifier.verifiedEvent(from: request, now: now)
            }
        }
    }

    /// TelnyxKit's clients for this request.
    public var telnyx: Telnyx {
        .init(request: self)
    }
}
