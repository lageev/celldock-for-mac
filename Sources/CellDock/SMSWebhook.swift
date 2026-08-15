import Foundation

struct SMSWebhookConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var url: String
    var secret: String

    static let empty = SMSWebhookConfiguration(isEnabled: false, url: "", secret: "")

    var resolvedURL: URL? {
        SMSWebhookURLPolicy.resolvedURL(from: url)
    }

    var canForward: Bool {
        isEnabled && resolvedURL != nil
    }
}

struct SMSWebhookDelivery: Codable, Equatable {
    enum Outcome: String, Codable {
        case succeeded
        case failed
    }

    var outcome: Outcome
    var date: Date
    var statusCode: Int?
    var detail: String?
}

struct SMSWebhookEnvelope: Equatable {
    var event: String
    var id: String
    var sender: String
    var body: String
    var timestamp: Date
    var receivedAt: Date
    var moduleID: String?
    var verificationCode: String?

    static func received(_ message: SMSMessage) -> Self {
        SMSWebhookEnvelope(
            event: "sms.received",
            id: message.id,
            sender: message.sender,
            body: message.body,
            timestamp: message.timestamp,
            receivedAt: message.firstSeenAt,
            moduleID: message.moduleID?.rawValue,
            verificationCode: message.verificationCode
        )
    }

    static func test(now: Date = Date()) -> Self {
        SMSWebhookEnvelope(
            event: "sms.test",
            id: "celldock-webhook-test",
            sender: "CellDock",
            body: "CellDock webhook test",
            timestamp: now,
            receivedAt: now,
            moduleID: nil,
            verificationCode: nil
        )
    }
}

enum SMSWebhookURLPolicy {
    static func resolvedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }
}

enum SMSWebhookDeliveryPolicy {
    static func shouldDeliver(
        _ message: SMSMessage,
        configuration: SMSWebhookConfiguration
    ) -> Bool {
        configuration.canForward && !message.isOutgoing
    }

    static func make(
        statusCode: Int?,
        error: Error?,
        now: Date = Date()
    ) -> SMSWebhookDelivery {
        if let error {
            return SMSWebhookDelivery(
                outcome: .failed,
                date: now,
                statusCode: statusCode,
                detail: error.localizedDescription
            )
        }
        guard let statusCode, (200..<300).contains(statusCode) else {
            return SMSWebhookDelivery(
                outcome: .failed,
                date: now,
                statusCode: statusCode,
                detail: statusCode.map { "HTTP \($0)" }
            )
        }
        return SMSWebhookDelivery(
            outcome: .succeeded,
            date: now,
            statusCode: statusCode,
            detail: nil
        )
    }
}

enum SMSWebhookPayloadBuilder {
    static func jsonObject(for envelope: SMSWebhookEnvelope) -> [String: Any] {
        var object: [String: Any] = [
            "event": envelope.event,
            "id": envelope.id,
            "sender": envelope.sender,
            "body": envelope.body,
            "timestamp": iso8601.string(from: envelope.timestamp),
            "received_at": iso8601.string(from: envelope.receivedAt)
        ]
        if let moduleID = envelope.moduleID {
            object["module_id"] = moduleID
        }
        if let verificationCode = envelope.verificationCode {
            object["verification_code"] = verificationCode
        }
        return object
    }

    static func jsonData(for envelope: SMSWebhookEnvelope) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: jsonObject(for: envelope),
            options: [.sortedKeys]
        )
    }

    static func request(url: URL, secret: String, body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CellDock", forHTTPHeaderField: "User-Agent")
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSecret.isEmpty {
            request.setValue(trimmedSecret, forHTTPHeaderField: "X-CellDock-Secret")
        }
        request.httpBody = body
        return request
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
