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
        completionHandler(
            SMSWebhookRedirectPolicy.redirectedRequest(
                from: task.originalRequest,
                proposed: request
            )
        )
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

    func setPreset(_ preset: SMSWebhookPreset) {
        var selected = configuration.selectedPresets
        if selected.contains(preset) {
            if configuration.preset == preset {
                selected.remove(preset)
                configuration.selectedPresets = selected
                if let next = SMSWebhookPreset.allCases.first(where: { selected.contains($0) }) {
                    configuration.preset = next
                }
            } else {
                configuration.preset = preset
            }
        } else {
            selected.insert(preset)
            configuration.selectedPresets = selected
            configuration.preset = preset
        }
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

    func setExtra(_ extra: String) {
        guard configuration.extra != extra else { return }
        configuration.extra = extra
        persist()
    }

    func setBodyTemplate(_ bodyTemplate: String) {
        guard configuration.bodyTemplate != bodyTemplate else { return }
        configuration.bodyTemplate = bodyTemplate
        persist()
    }

    func setCustomHeaders(_ headers: [SMSWebhookHeader]) {
        guard configuration.customHeaders != headers else { return }
        configuration.customHeaders = headers
        persist()
    }

    func setEvent(_ kind: SMSWebhookEventKind, enabled: Bool) {
        var events = configuration.forwardedEvents
        if enabled {
            events.insert(kind)
        } else {
            events.remove(kind)
        }
        guard configuration.forwardedEvents != events else { return }
        configuration.forwardedEvents = events
        persist()
    }

    func deliver(_ messages: [SMSMessage]) {
        let configuration = self.configuration
        for message in messages where SMSWebhookDeliveryPolicy.shouldDeliver(
            message,
            configuration: configuration
        ) {
            send(SMSWebhookEnvelope.received(message), configuration: configuration)
        }
    }

    func deliverIncomingCall(
        number: String?,
        displayName: String?,
        moduleID: CellularModuleID?
    ) {
        let configuration = self.configuration
        guard SMSWebhookDeliveryPolicy.shouldDeliver(.callIncoming, configuration: configuration) else {
            return
        }
        send(
            SMSWebhookEnvelope.incomingCall(
                number: number,
                displayName: displayName,
                moduleID: moduleID
            ),
            configuration: configuration
        )
    }

    func deliverMissedCall(_ record: CallHistoryRecord, displayName: String?) {
        let configuration = self.configuration
        guard SMSWebhookDeliveryPolicy.shouldDeliver(.callMissed, configuration: configuration) else {
            return
        }
        send(SMSWebhookEnvelope.missedCall(record, displayName: displayName), configuration: configuration)
    }

    func deliverTest() {
        send(SMSWebhookEnvelope.test(), configuration: configuration)
    }

    private func send(
        _ envelope: SMSWebhookEnvelope,
        configuration: SMSWebhookConfiguration
    ) {
        let presets = configuration.sendablePresets
        guard !presets.isEmpty else { return }
        for preset in presets {
            var snapshot = configuration
            snapshot.preset = preset
            post(envelope, configuration: snapshot)
        }
    }

    private func post(
        _ envelope: SMSWebhookEnvelope,
        configuration: SMSWebhookConfiguration
    ) {
        guard let url = configuration.resolvedURL else { return }
        if configuration.preset.requiresChatID, configuration.trimmedExtra.isEmpty {
            finish(
                SMSWebhookDelivery(
                    outcome: .failed,
                    date: Date(),
                    statusCode: nil,
                    detail: L10n.tr("请填写 Chat ID 或 QQ 号。")
                )
            )
            return
        }
        let body: Data
        do {
            body = try SMSWebhookPayloadBuilder.bodyData(
                for: envelope,
                configuration: configuration
            )
        } catch {
            finish(
                SMSWebhookDelivery(
                    outcome: .failed,
                    date: Date(),
                    statusCode: nil,
                    detail: L10n.tr("请求体不是有效 JSON。")
                )
            )
            return
        }
        let request = SMSWebhookPayloadBuilder.request(
            url: url,
            configuration: configuration,
            body: body
        )
        inFlightCount += 1
        smsWebhookLogger.info(
            "Posting webhook preset=\(configuration.preset.rawValue, privacy: .public) event=\(envelope.event, privacy: .public)"
        )
        session.dataTask(with: request) { [weak self] data, response, error in
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let delivery = SMSWebhookDeliveryPolicy.make(
                statusCode: statusCode,
                error: error,
                responseBody: data
            )
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
                "webhook succeeded status=\(delivery.statusCode ?? 0, privacy: .public)"
            )
        case .failed:
            smsWebhookLogger.error(
                "webhook failed status=\(delivery.statusCode ?? 0, privacy: .public) detail=\(delivery.detail ?? "", privacy: .public)"
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
