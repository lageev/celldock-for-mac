import Foundation

enum SMSWebhookPreset: String, Codable, CaseIterable, Identifiable {
    case custom
    case feishu
    case dingtalk
    case telegram
    case qqPrivate
    case qqGroup
    case wecom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom: return L10n.tr("自定义")
        case .feishu: return L10n.tr("飞书机器人")
        case .dingtalk: return L10n.tr("钉钉机器人")
        case .telegram: return "Telegram"
        case .qqPrivate: return L10n.tr("QQ 机器人（私聊）")
        case .qqGroup: return L10n.tr("QQ 机器人（群）")
        case .wecom: return L10n.tr("企业微信机器人")
        }
    }

    var urlPlaceholder: String {
        switch self {
        case .custom:
            return "https://example.com/webhook"
        case .feishu:
            return "https://open.feishu.cn/open-apis/bot/v2/hook/..."
        case .dingtalk:
            return "https://oapi.dingtalk.com/robot/send?access_token=..."
        case .telegram:
            return "https://api.telegram.org/bot<token>/sendMessage"
        case .qqPrivate:
            return "http://127.0.0.1:5700/send_private_msg"
        case .qqGroup:
            return "http://127.0.0.1:5700/send_group_msg"
        case .wecom:
            return "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=..."
        }
    }

    var requiresChatID: Bool {
        switch self {
        case .telegram, .qqPrivate, .qqGroup: return true
        default: return false
        }
    }

    var extraFieldTitle: String? {
        switch self {
        case .telegram: return L10n.tr("Chat ID")
        case .qqPrivate: return L10n.tr("QQ 号")
        case .qqGroup: return L10n.tr("群号")
        case .dingtalk: return L10n.tr("自定义关键词（可选）")
        default: return nil
        }
    }

    var usesSecret: Bool {
        switch self {
        case .custom, .qqPrivate, .qqGroup: return true
        default: return false
        }
    }

    var secretTitle: String {
        switch self {
        case .qqPrivate, .qqGroup: return L10n.tr("Access Token（可选）")
        default: return L10n.tr("密钥（可选）")
        }
    }

    var secretCaption: String {
        switch self {
        case .qqPrivate, .qqGroup:
            return L10n.tr("会随请求以 Authorization: Bearer 发送")
        default:
            return L10n.tr("会随请求以 X-CellDock-Secret 请求头发送")
        }
    }

    var defaultBodyTemplate: String {
        switch self {
        case .custom:
            return """
            {
              "event": "{{event}}",
              "id": "{{id}}",
              "sender": "{{sender}}",
              "body": "{{body}}",
              "text": "{{text}}",
              "timestamp": "{{timestamp}}",
              "received_at": "{{received_at}}",
              "module_id": "{{module_id}}",
              "verification_code": "{{verification_code}}"
            }
            """
        case .feishu:
            return """
            {
              "msg_type": "text",
              "content": {
                "text": "{{text}}"
              }
            }
            """
        case .dingtalk, .wecom:
            return """
            {
              "msgtype": "text",
              "text": {
                "content": "{{text}}"
              }
            }
            """
        case .telegram:
            return """
            {
              "chat_id": "{{chat_id}}",
              "text": "{{text}}"
            }
            """
        case .qqPrivate:
            return """
            {
              "user_id": {{chat_id}},
              "message": "{{text}}"
            }
            """
        case .qqGroup:
            return """
            {
              "group_id": {{chat_id}},
              "message": "{{text}}"
            }
            """
        }
    }
}

enum SMSWebhookEventKind: String, Codable, CaseIterable, Identifiable {
    case smsReceived = "sms.received"
    case callMissed = "call.missed"
    case callIncoming = "call.incoming"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smsReceived: return L10n.tr("新短信")
        case .callMissed: return L10n.tr("未接来电")
        case .callIncoming: return L10n.tr("来电")
        }
    }

    var detail: String {
        switch self {
        case .smsReceived: return L10n.tr("收到新短信后转发")
        case .callMissed: return L10n.tr("未接来电时转发")
        case .callIncoming: return L10n.tr("来电时转发到此渠道。IM 延迟较高，可能来不及接听。")
        }
    }
}

struct SMSWebhookHeader: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var value: String

    init(id: UUID = UUID(), name: String = "", value: String = "") {
        self.id = id
        self.name = name
        self.value = value
    }
}

struct SMSWebhookConfiguration: Codable, Equatable {
    var isEnabled: Bool
    var preset: SMSWebhookPreset
    var selectedPresets: Set<SMSWebhookPreset>
    var customHeaders: [SMSWebhookHeader]
    var urls: [SMSWebhookPreset: String]
    var extras: [SMSWebhookPreset: String]
    var secrets: [SMSWebhookPreset: String]
    var bodyTemplates: [SMSWebhookPreset: String]
    var forwardedEvents: Set<SMSWebhookEventKind>

    var url: String {
        get { urls[preset] ?? "" }
        set { urls[preset] = newValue }
    }

    var extra: String {
        get { extras[preset] ?? "" }
        set { extras[preset] = newValue }
    }

    var secret: String {
        get { secrets[preset] ?? "" }
        set { secrets[preset] = newValue }
    }

    var bodyTemplate: String {
        get { bodyTemplates[preset] ?? "" }
        set { bodyTemplates[preset] = newValue }
    }

    static let empty = SMSWebhookConfiguration()
    static let defaultForwardedEvents: Set<SMSWebhookEventKind> = [.smsReceived]

    init(
        isEnabled: Bool = false,
        preset: SMSWebhookPreset = .custom,
        url: String = "",
        secret: String = "",
        extra: String = "",
        bodyTemplate: String = "",
        customHeaders: [SMSWebhookHeader] = [],
        urls: [SMSWebhookPreset: String] = [:],
        extras: [SMSWebhookPreset: String] = [:],
        secrets: [SMSWebhookPreset: String] = [:],
        bodyTemplates: [SMSWebhookPreset: String] = [:],
        selectedPresets: Set<SMSWebhookPreset>? = nil,
        forwardedEvents: Set<SMSWebhookEventKind> = [.smsReceived]
    ) {
        self.isEnabled = isEnabled
        self.preset = preset
        self.selectedPresets = selectedPresets ?? [preset]
        self.customHeaders = customHeaders
        self.urls = urls
        self.extras = extras
        self.secrets = secrets
        self.bodyTemplates = bodyTemplates
        self.forwardedEvents = forwardedEvents
        if !url.isEmpty {
            self.urls[preset] = url
        }
        if !secret.isEmpty {
            self.secrets[preset] = secret
        }
        if !extra.isEmpty {
            self.extras[preset] = extra
        }
        if !bodyTemplate.isEmpty {
            self.bodyTemplates[preset] = bodyTemplate
        }
    }

    enum CodingKeys: String, CodingKey {
        case isEnabled, preset, selectedPresets, url, secret, extra, bodyTemplate
        case customHeaders, urls, extras, secrets, bodyTemplates, forwardedEvents
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        preset = try container.decodeIfPresent(SMSWebhookPreset.self, forKey: .preset) ?? .custom
        selectedPresets = try container.decodeIfPresent(
            Set<SMSWebhookPreset>.self,
            forKey: .selectedPresets
        ) ?? [preset]
        customHeaders = try container.decodeIfPresent(
            [SMSWebhookHeader].self,
            forKey: .customHeaders
        ) ?? []
        urls = try container.decodeIfPresent([SMSWebhookPreset: String].self, forKey: .urls) ?? [:]
        extras = try container.decodeIfPresent([SMSWebhookPreset: String].self, forKey: .extras) ?? [:]
        secrets = try container.decodeIfPresent([SMSWebhookPreset: String].self, forKey: .secrets) ?? [:]
        bodyTemplates = try container.decodeIfPresent(
            [SMSWebhookPreset: String].self,
            forKey: .bodyTemplates
        ) ?? [:]
        let legacyURL = try container.decodeIfPresent(String.self, forKey: .url) ?? ""
        if (urls[preset] ?? "").isEmpty, !legacyURL.isEmpty {
            urls[preset] = legacyURL
        }
        let legacySecret = try container.decodeIfPresent(String.self, forKey: .secret) ?? ""
        if (secrets[preset] ?? "").isEmpty, !legacySecret.isEmpty {
            secrets[preset] = legacySecret
        }
        let legacyExtra = try container.decodeIfPresent(String.self, forKey: .extra) ?? ""
        if (extras[preset] ?? "").isEmpty, !legacyExtra.isEmpty {
            extras[preset] = legacyExtra
        }
        let legacyBody = try container.decodeIfPresent(String.self, forKey: .bodyTemplate) ?? ""
        if (bodyTemplates[preset] ?? "").isEmpty, !legacyBody.isEmpty {
            bodyTemplates[preset] = legacyBody
        }
        forwardedEvents = try container.decodeIfPresent(
            Set<SMSWebhookEventKind>.self,
            forKey: .forwardedEvents
        ) ?? Self.defaultForwardedEvents
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(preset, forKey: .preset)
        try container.encode(selectedPresets, forKey: .selectedPresets)
        try container.encode(url, forKey: .url)
        try container.encode(secret, forKey: .secret)
        try container.encode(extra, forKey: .extra)
        try container.encode(bodyTemplate, forKey: .bodyTemplate)
        try container.encode(customHeaders, forKey: .customHeaders)
        try container.encode(urls, forKey: .urls)
        try container.encode(extras, forKey: .extras)
        try container.encode(secrets, forKey: .secrets)
        try container.encode(bodyTemplates, forKey: .bodyTemplates)
        try container.encode(forwardedEvents, forKey: .forwardedEvents)
    }

    var effectiveBodyTemplate: String {
        let trimmed = bodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? preset.defaultBodyTemplate : bodyTemplate
    }

    var trimmedExtra: String {
        extra.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedURL: URL? {
        SMSWebhookURLPolicy.resolvedURL(from: url)
    }

    var hasSendableDestination: Bool {
        hasSendableDestination(for: preset)
    }

    var sendablePresets: [SMSWebhookPreset] {
        SMSWebhookPreset.allCases.filter {
            selectedPresets.contains($0) && hasSendableDestination(for: $0)
        }
    }

    var canForward: Bool {
        isEnabled && !sendablePresets.isEmpty
    }

    func hasSendableDestination(for preset: SMSWebhookPreset) -> Bool {
        SMSWebhookURLPolicy.resolvedURL(from: urls[preset] ?? "") != nil
            && (!preset.requiresChatID
                || !(extras[preset] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func forwards(_ kind: SMSWebhookEventKind) -> Bool {
        forwardedEvents.contains(kind)
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

    static func incomingCall(
        number: String?,
        displayName: String?,
        moduleID: CellularModuleID?,
        now: Date = Date()
    ) -> Self {
        SMSWebhookEnvelope(
            event: SMSWebhookEventKind.callIncoming.rawValue,
            id: "call-incoming-\(moduleID?.rawValue ?? "unknown")",
            sender: displayName ?? number ?? L10n.tr("未知号码"),
            body: L10n.tr("蜂窝来电"),
            timestamp: now,
            receivedAt: now,
            moduleID: moduleID?.rawValue,
            verificationCode: nil
        )
    }

    static func missedCall(_ record: CallHistoryRecord, displayName: String?) -> Self {
        SMSWebhookEnvelope(
            event: SMSWebhookEventKind.callMissed.rawValue,
            id: record.id.uuidString,
            sender: displayName ?? record.number,
            body: L10n.tr("未接来电"),
            timestamp: record.endedAt,
            receivedAt: record.endedAt,
            moduleID: record.moduleID?.rawValue,
            verificationCode: nil
        )
    }

    static func test(now: Date = Date()) -> Self {
        SMSWebhookEnvelope(
            event: "notification.test",
            id: "celldock-webhook-test",
            sender: "CellDock",
            body: L10n.tr("这是一条 CellDock 通知转发测试消息。"),
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

enum SMSWebhookRedirectPolicy {
    static func redirectedRequest(from original: URLRequest?, proposed: URLRequest) -> URLRequest {
        var request = proposed
        guard let original else { return request }
        request.httpMethod = original.httpMethod
        request.httpBody = original.httpBody
        if let fields = original.allHTTPHeaderFields {
            for (name, value) in fields where request.value(forHTTPHeaderField: name) == nil {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }
        return request
    }
}

enum SMSWebhookHeaderPolicy {
    static func resolved(_ headers: [SMSWebhookHeader]) -> [(name: String, value: String)] {
        headers.compactMap { header in
            let name = header.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidName(name) else { return nil }
            return (
                name,
                header.value.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "!#$%&'*+-.^_`|~"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

enum SMSWebhookBodyError: Error {
    case invalidJSON
}

enum SMSWebhookDeliveryPolicy {
    static func shouldDeliver(
        _ message: SMSMessage,
        configuration: SMSWebhookConfiguration
    ) -> Bool {
        shouldDeliver(.smsReceived, configuration: configuration) && !message.isOutgoing
    }

    static func shouldDeliver(
        _ kind: SMSWebhookEventKind,
        configuration: SMSWebhookConfiguration
    ) -> Bool {
        configuration.canForward && configuration.forwards(kind)
    }

    static func make(
        statusCode: Int?,
        error: Error?,
        responseBody: Data? = nil,
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
        if let apiError = apiErrorDetail(from: responseBody) {
            return SMSWebhookDelivery(
                outcome: .failed,
                date: now,
                statusCode: statusCode,
                detail: apiError
            )
        }
        return SMSWebhookDelivery(
            outcome: .succeeded,
            date: now,
            statusCode: statusCode,
            detail: nil
        )
    }

    static func apiErrorDetail(from data: Data?) -> String? {
        guard let data, !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let ok = object["ok"] as? Bool, ok == false {
            return stringValue(object["description"])
                ?? stringValue(object["error"])
                ?? "ok=false"
        }
        if let errcode = intValue(object["errcode"]), errcode != 0 {
            return stringValue(object["errmsg"]) ?? "errcode=\(errcode)"
        }
        if let code = intValue(object["code"]), code != 0 {
            return stringValue(object["msg"])
                ?? stringValue(object["message"])
                ?? "code=\(code)"
        }
        if let statusCode = intValue(object["StatusCode"]), statusCode != 0 {
            return stringValue(object["StatusMessage"]) ?? "StatusCode=\(statusCode)"
        }
        if let status = object["status"] as? String, status.lowercased() == "failed" {
            return stringValue(object["message"])
                ?? stringValue(object["wording"])
                ?? "status=failed"
        }
        if let retcode = intValue(object["retcode"]), retcode != 0 {
            return stringValue(object["wording"])
                ?? stringValue(object["message"])
                ?? "retcode=\(retcode)"
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum SMSWebhookPayloadBuilder {
    static var placeholderHelpItems: [(key: String, detail: String)] {
        [
            ("event", L10n.tr("sms.received、call.incoming、call.missed；测试为 notification.test")),
            ("id", L10n.tr("记录 ID")),
            ("sender", L10n.tr("发件人或来电方")),
            ("body", L10n.tr("原文；来电时为事件名称")),
            ("text", L10n.tr("带发件人的完整文本")),
            ("timestamp", L10n.tr("事件时间（北京时间）")),
            ("received_at", L10n.tr("本机收到时间（北京时间）")),
            ("module_id", L10n.tr("模组 ID")),
            ("verification_code", L10n.tr("验证码，没有则为空")),
            ("chat_id", L10n.tr("Chat ID 或 QQ 号/群号"))
        ]
    }

    static var placeholderKeys: [String] {
        placeholderHelpItems.map(\.key)
    }

    static func templateValues(
        for envelope: SMSWebhookEnvelope,
        configuration: SMSWebhookConfiguration
    ) -> [String: String] {
        var text: String
        switch envelope.event {
        case SMSWebhookEventKind.callIncoming.rawValue:
            text = "\(L10n.tr("蜂窝来电"))\n来自 \(envelope.sender)"
        case SMSWebhookEventKind.callMissed.rawValue:
            text = "\(L10n.tr("未接来电"))\n来自 \(envelope.sender)"
        default:
            text = "来自 \(envelope.sender)\n\(envelope.body)"
        }
        if configuration.preset == .dingtalk, !configuration.trimmedExtra.isEmpty {
            text = "\(configuration.trimmedExtra)\n\(text)"
        }
        return [
            "event": envelope.event,
            "id": envelope.id,
            "sender": envelope.sender,
            "body": envelope.body,
            "text": text,
            "timestamp": iso8601.string(from: envelope.timestamp),
            "received_at": iso8601.string(from: envelope.receivedAt),
            "module_id": envelope.moduleID ?? "",
            "verification_code": envelope.verificationCode ?? "",
            "chat_id": configuration.trimmedExtra
        ]
    }

    static func jsonEscape(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.append(Character(scalar))
                }
            }
        }
        return result
    }

    static func render(_ template: String, values: [String: String]) throws -> Data {
        var rendered = template
        for key in values.keys.sorted(by: { $0.count > $1.count }) {
            rendered = rendered.replacingOccurrences(
                of: "{{\(key)}}",
                with: jsonEscape(values[key] ?? "")
            )
        }
        guard let data = rendered.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw SMSWebhookBodyError.invalidJSON
        }
        return data
    }

    static func bodyData(
        for envelope: SMSWebhookEnvelope,
        configuration: SMSWebhookConfiguration
    ) throws -> Data {
        try render(
            configuration.effectiveBodyTemplate,
            values: templateValues(for: envelope, configuration: configuration)
        )
    }

    static func request(
        url: URL,
        configuration: SMSWebhookConfiguration,
        body: Data
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("CellDock", forHTTPHeaderField: "User-Agent")
        if configuration.preset == .custom {
            for header in SMSWebhookHeaderPolicy.resolved(configuration.customHeaders) {
                request.setValue(header.value, forHTTPHeaderField: header.name)
            }
        }
        let secret = configuration.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty {
            switch configuration.preset {
            case .qqPrivate, .qqGroup:
                request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            case .custom:
                request.setValue(secret, forHTTPHeaderField: "X-CellDock-Secret")
            default:
                break
            }
        }
        request.httpBody = body
        return request
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
            ?? TimeZone(secondsFromGMT: 8 * 3600)
        return formatter
    }()
}
