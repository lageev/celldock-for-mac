import Combine
import Foundation
import OSLog

private let smsWebhookLogger = Logger(subsystem: "app.celldock.mac", category: "SMSWebhook")

private struct SMSWebhookPersistedState: Codable, Equatable {
    var configuration: SMSWebhookConfiguration
    var lastDelivery: SMSWebhookDelivery?
}

private final class SMSWebhookSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
final class SMSWebhookService: ObservableObject {
    static let shared = SMSWebhookService()

    @Published private(set) var configuration: SMSWebhookConfiguration
    @Published private(set) var lastDelivery: SMSWebhookDelivery?
    @Published private(set) var inFlightCount = 0

    private let defaults: UserDefaults
    private let key: String
    private let sessionDelegate = SMSWebhookSessionDelegate()
    private let session: URLSession

    init(
        defaults: UserDefaults = .standard,
        key: String = "SMSWebhookState.v1"
    ) {
        self.defaults = defaults
        self.key = key
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.timeoutIntervalForRequest = 10
        sessionConfiguration.timeoutIntervalForResource = 10
        sessionConfiguration.httpShouldSetCookies = false
        sessionConfiguration.waitsForConnectivity = false
        session = URLSession(
            configuration: sessionConfiguration,
            delegate: sessionDelegate,
            delegateQueue: nil
        )

        if let data = defaults.data(forKey: key),
           let state = try? JSONDecoder().decode(SMSWebhookPersistedState.self, from: data) {
            configuration = state.configuration
            lastDelivery = state.lastDelivery
        } else {
            configuration = .empty
            lastDelivery = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard configuration.isEnabled != enabled else { return }
        configuration.isEnabled = enabled
        persist()
    }

    func setURL(_ url: String) {
        guard configuration.url != url else { return }
        configuration.url = url
        persist()
    }

    func setSecret(_ secret: String) {
        guard configuration.secret != secret else { return }
        configuration.secret = secret
        persist()
    }

    func deliver(_ messages: [SMSMessage]) {
        let configuration = self.configuration
        guard let url = configuration.resolvedURL else { return }
        for message in messages where SMSWebhookDeliveryPolicy.shouldDeliver(
            message,
            configuration: configuration
        ) {
            send(SMSWebhookEnvelope.received(message), url: url, secret: configuration.secret)
        }
    }

    func deliverTest() {
        guard let url = configuration.resolvedURL else { return }
        send(SMSWebhookEnvelope.test(), url: url, secret: configuration.secret)
    }

    private func send(_ envelope: SMSWebhookEnvelope, url: URL, secret: String) {
        guard let body = try? SMSWebhookPayloadBuilder.jsonData(for: envelope) else {
            smsWebhookLogger.error("Failed to encode webhook payload")
            return
        }
        let request = SMSWebhookPayloadBuilder.request(url: url, secret: secret, body: body)
        inFlightCount += 1
        smsWebhookLogger.info("Posting SMS webhook event=\(envelope.event, privacy: .public)")
        session.dataTask(with: request) { [weak self] _, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let delivery = SMSWebhookDeliveryPolicy.make(statusCode: statusCode, error: error)
            Task { @MainActor in
                self?.finish(delivery)
            }
        }.resume()
    }

    private func finish(_ delivery: SMSWebhookDelivery) {
        inFlightCount = max(0, inFlightCount - 1)
        lastDelivery = delivery
        persist()
        switch delivery.outcome {
        case .succeeded:
            smsWebhookLogger.info(
                "SMS webhook succeeded status=\(delivery.statusCode ?? 0, privacy: .public)"
            )
        case .failed:
            smsWebhookLogger.error(
                "SMS webhook failed status=\(delivery.statusCode ?? 0, privacy: .public) detail=\(delivery.detail ?? "", privacy: .public)"
            )
        }
    }

    private func persist() {
        let state = SMSWebhookPersistedState(
            configuration: configuration,
            lastDelivery: lastDelivery
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }
}
