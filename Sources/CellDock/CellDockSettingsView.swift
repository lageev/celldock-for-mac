import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct CellDockSettingsView: View {
    private enum Category: String, CaseIterable {
        case general = "通用"
        case communications = "蜂窝与通信"
        case webhook = "通知转发"
        case permissions = "通知与权限"
        case updates = "软件更新"

        var title: String { L10n.tr(rawValue) }

        var systemImage: String {
            switch self {
            case .general: return "gearshape"
            case .communications: return "antenna.radiowaves.left.and.right"
            case .webhook: return "paperplane"
            case .permissions: return "bell.badge"
            case .updates: return "arrow.triangle.2.circlepath"
            }
        }

        var detail: String {
            switch self {
            case .general: return L10n.tr("启动、外观与菜单栏行为")
            case .communications: return L10n.tr("查看模块状态并管理通话与短信处理")
            case .webhook: return L10n.tr("配置出站渠道，并选择要转发的通知")
            case .permissions: return L10n.tr("检查 CellDock 的系统访问权限")
            case .updates: return L10n.tr("检查版本并选择更新频道")
            }
        }

        var sidebarDetail: String {
            switch self {
            case .general: return L10n.tr("外观、语言与启动")
            case .communications: return L10n.tr("声音、通话与短信")
            case .webhook: return L10n.tr("渠道与通知类型")
            case .permissions: return L10n.tr("通知与系统访问权限")
            case .updates: return L10n.tr("版本与更新频道")
            }
        }
    }

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var contacts = SystemContactStore.shared
    @ObservedObject private var alertSounds = AlertSoundService.shared
    @ObservedObject private var languageController = AppLanguageController.shared
    @ObservedObject private var updaterManager = UpdaterManager.shared
    @ObservedObject private var smsWebhook = SMSWebhookService.shared
    @ObservedObject private var autoAnswerGreeting = AutoAnswerGreetingStore.shared
    @Binding private var sidebarWidth: CGFloat
    private let focusFirstItemRequest: Bool
    private let didHandleFocusFirstItemRequest: () -> Void
    @AppStorage(AppAppearanceMode.defaultsKey) private var appearanceModeRawValue =
        AppAppearanceMode.system.rawValue
    @AppStorage("CallRecordingConsentAcknowledged.v1") private var recordingConsent = false
    @State private var selectedCategory: Category = .general
    @State private var didResolveInitialCategory = false
    @State private var isConfirmingVerificationAutoDelete = false
    @State private var isConfirmingAutomaticRecording = false
    @State private var soundImportError: String?
    @State private var isWebhookVariableHelpPresented = false
    @State private var microphoneAuthorizationStatus =
        AVCaptureDevice.authorizationStatus(for: .audio)
    @FocusState private var listFocused: Bool

    init(
        sidebarWidth: Binding<CGFloat> = .constant(CommunicationUI.sidebarWidth),
        focusFirstItemRequest: Bool = false,
        didHandleFocusFirstItemRequest: @escaping () -> Void = {}
    ) {
        _sidebarWidth = sidebarWidth
        self.focusFirstItemRequest = focusFirstItemRequest
        self.didHandleFocusFirstItemRequest = didHandleFocusFirstItemRequest
    }

    var body: some View {
        ResizableCommunicationSplit(sidebarWidth: $sidebarWidth) {
            settingsSidebar
        } detail: {
            settingsContent
        }
        .frame(
            minWidth: 560,
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .onAppear {
            refreshSettingsState()
            resolveInitialSettingsCategoryIfNeeded()
            handleFocusFirstItemRequest()
        }
        .onChange(of: focusFirstItemRequest) { _, requested in
            if requested { handleFocusFirstItemRequest() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            refreshSystemPermissionState()
        }
        .alert("开启验证码自动删除？", isPresented: $isConfirmingVerificationAutoDelete) {
            Button("取消", role: .cancel) { }
            Button("开启", role: .destructive) {
                appState.setAutoDeleteReadVerificationMessages(true)
            }
        } message: {
            Text("验证码短信被标记已读 30 分钟后，将从模块/SIM 和本地永久删除，无法撤销。")
        }
        .alert("开启通话自动录音？", isPresented: $isConfirmingAutomaticRecording) {
            Button("取消", role: .cancel) { }
            Button("同意并开启") {
                recordingConsent = true
                appState.setAutomaticallyRecordCalls(true)
            }
        } message: {
            Text("通话接通后会自动录制双方的声音。请先确认已取得通话参与者同意，并遵守所在地法律法规。录音仅保存在这台 Mac。")
        }
        .alert(
            "无法使用音频文件",
            isPresented: Binding(
                get: { soundImportError != nil },
                set: { if !$0 { soundImportError = nil } }
            )
        ) {
            Button("好", role: .cancel) { soundImportError = nil }
        } message: {
            Text(soundImportError ?? L10n.tr("请选择其他音频文件。"))
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.tr("设置"))
                        .font(.title2.bold())
                        .padding(.horizontal, 14)

                    settingsSidebarGroup(
                        L10n.tr("偏好设置"),
                        categories: [.general, .communications, .webhook]
                    )
                    settingsSidebarGroup(
                        L10n.tr("系统"),
                        categories: [.permissions, .updates]
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
            }
            .communicationSidebarScrollEdgeEffect()

            Text(verbatim: "CellDock · \(updaterManager.currentVersion)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .accessibilityLabel("CellDock \(updaterManager.currentVersion)")
        }
        .communicationInitialListFocus($listFocused)
        .communicationSidebarColumnStyle()
    }

    private func settingsSidebarGroup(
        _ title: String,
        categories: [Category]
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)

            VStack(spacing: 2) {
                ForEach(categories, id: \.self) { category in
                    settingsSidebarRow(category)
                }
            }
        }
    }

    private func settingsSidebarRow(_ category: Category) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            selectSettingsCategory(category)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.body.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    Text(category.sidebarDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if category == .permissions, allSettingsPermissionsAllowed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 0.7)
                    }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectSettingsCategory(_ category: Category) {
        didResolveInitialCategory = true
        selectedCategory = category
        if category == .communications {
            appState.refresh()
        } else if category == .permissions {
            refreshSystemPermissionState()
        }
    }

    private func handleFocusFirstItemRequest() {
        guard focusFirstItemRequest else { return }
        resolveInitialSettingsCategoryIfNeeded()
        didHandleFocusFirstItemRequest()
        listFocused = false
        DispatchQueue.main.async {
            listFocused = true
        }
    }

    private func resolveInitialSettingsCategoryIfNeeded() {
        guard !didResolveInitialCategory else { return }
        selectedCategory = .general
        didResolveInitialCategory = true
    }

    private var settingsContent: some View {
        ScrollView {
            AdaptiveGlassContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 20) {
                    settingsHeader
                    settingsCards
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .communicationDetailColumnStyle()
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(selectedCategory.title)
                .font(.largeTitle.bold())
            Text(selectedCategory.detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var settingsCards: some View {
        switch selectedCategory {
        case .general:
            generalSettings
        case .communications:
            communicationSettings
        case .webhook:
            webhookSettings
        case .permissions:
            permissionSettings
        case .updates:
            updateSettings
        }
    }

    private var generalSettings: some View {
        VStack(spacing: 16) {
            settingsSection(title: L10n.tr("隐私保护")) {
                VStack(spacing: 12) {
                    settingRow(
                        title: L10n.tr("演示隐私保护"),
                        status: appState.isPresentationPrivacyEnabled ? L10n.tr("已开启") : nil,
                        statusColor: .green,
                        detail: L10n.tr("在界面与系统通知中隐藏联系人、电话号码、短信内容和验证码")
                    ) {
                        Toggle("演示隐私保护", isOn: Binding(
                            get: { appState.isPresentationPrivacyEnabled },
                            set: { appState.setPresentationPrivacyEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.adaptiveGlass)
                    }

                    if appState.isPresentationPrivacyEnabled {
                        inlineCallout(
                            L10n.tr("原始数据不会被修改；复制、导出、在访达中显示和编辑联系人暂不可用。"),
                            systemImage: "checkmark.shield.fill",
                            color: .green
                        )
                    }
                }
                .padding(16)
            }

            settingsSection(title: L10n.tr("外观与语言")) {
                VStack(spacing: 0) {
                    settingRow(
                        title: L10n.tr("主题模式")
                    ) {
                        Picker("主题模式", selection: appearanceModeBinding) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(mode.title)
                                    .lineLimit(1)
                                    .tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 276)
                    }
                    .padding(16)

                    Divider().padding(.horizontal, 16)

                    settingRow(
                        title: L10n.tr("应用语言"),
                        detail: L10n.tr("切换后立即应用，无需重新启动")
                    ) {
                        Picker("应用语言", selection: languageBinding) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(verbatim: language.nativeName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 142)
                    }
                    .padding(16)
                }
            }

            settingsSection(title: L10n.tr("启动与菜单栏")) {
                VStack(spacing: 0) {
                    settingRow(
                        title: L10n.tr("登录时启动"),
                        detail: launchAtLoginDetail
                    ) {
                        if appState.isChangingLaunchAtLogin {
                            ProgressView().controlSize(.small)
                        } else {
                            Toggle("登录时启动", isOn: Binding(
                                get: { appState.launchAtLoginStatus.isRegistered },
                                set: { appState.setLaunchAtLogin($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.adaptiveGlass)
                            .disabled(appState.launchAtLoginStatus == .unavailable)
                        }
                    }
                    .padding(16)

                    if let error = appState.launchAtLoginError {
                        inlineMessage(
                            error,
                            systemImage: "exclamationmark.triangle.fill",
                            color: .red
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                    }

                    Divider().padding(.horizontal, 16)

                    settingRow(
                        title: L10n.tr("未连接模块时隐藏菜单栏图标"),
                        detail: appState.hideMenuBarIconWhenDisconnected
                            ? L10n.tr("重新连接模块后自动显示")
                            : L10n.tr("模块断开后继续显示状态图标")
                    ) {
                        Toggle("未连接模块时隐藏菜单栏图标", isOn: Binding(
                            get: { appState.hideMenuBarIconWhenDisconnected },
                            set: { appState.setHideMenuBarIconWhenDisconnected($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.adaptiveGlass)
                    }
                    .padding(16)
                }
            }

            settingsSection(title: L10n.tr("应用操作")) {
                settingRow(
                    title: L10n.tr("完全退出 CellDock"),
                    detail: L10n.tr("关闭窗口不会停止短信、来电和模块监测")
                ) {
                    Button(role: .destructive) {
                        appState.quit()
                    } label: {
                        Label("完全退出 CellDock", systemImage: "power")
                    }
                    .adaptiveGlassButton()
                    .tint(.red)
                    .help("完全退出 CellDock，并停止后台短信、来电和模块监测")
                }
                .padding(16)
            }
        }
    }

    private var updateSettings: some View {
        VStack(spacing: 16) {
            settingsSection(title: L10n.tr("软件更新")) {
                VStack(spacing: 0) {
                    settingRow(
                        title: L10n.tr("自动检查更新"),
                        detail: updaterManager.currentVersion
                    ) {
                        Toggle("自动检查更新", isOn: Binding(
                            get: { updaterManager.automaticallyChecksForUpdates },
                            set: { updaterManager.automaticallyChecksForUpdates = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.adaptiveGlass)
                    }
                    .padding(16)

                    Divider().padding(.horizontal, 16)

                    settingRow(
                        title: L10n.tr("更新频道"),
                        detail: updaterManager.channel == .stable
                            ? L10n.tr("仅接收经过验证的正式版本")
                            : L10n.tr("提前体验新功能，可能不够稳定")
                    ) {
                        Picker("更新频道", selection: $updaterManager.channel) {
                            ForEach(UpdateChannel.allCases) { channel in
                                Text(channel.title).tag(channel)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(16)

                    Divider().padding(.horizontal, 16)

                    settingRow(
                        title: L10n.tr("立即检查"),
                        detail: L10n.tr("从 CellDock 官方服务器检查并验证更新")
                    ) {
                        Button("检查更新…") {
                            updaterManager.checkForUpdates()
                        }
                        .adaptiveGlassButton()
                        .disabled(!updaterManager.canCheckForUpdates)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var communicationSettings: some View {
        VStack(spacing: 16) {
            moduleStatusStrip

            settingsSection(title: L10n.tr("声音")) {
                VStack(spacing: 0) {
                    soundSettingRow(.message)
                        .padding(16)

                    Divider().padding(.horizontal, 16)

                    soundSettingRow(.incomingCall)
                        .padding(16)
                }
            }

            settingsSection(title: L10n.tr("来电")) {
                VStack(alignment: .leading, spacing: 12) {
                    settingRow(
                        title: L10n.tr("来电自动接通"),
                        detail: L10n.tr("检测到来电后自动接听，无需手动点接听")
                    ) {
                        Toggle("来电自动接通", isOn: Binding(
                            get: { appState.automaticallyAnswerIncomingCalls },
                            set: { appState.setAutomaticallyAnswerIncomingCalls($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.adaptiveGlass)
                    }

                    if microphoneAuthorizationStatus != .authorized {
                        inlineCallout(
                            L10n.tr("自动接通不检查麦克风权限。未允许时对方可能听不到你说话。"),
                            systemImage: "mic.slash",
                            color: .orange
                        )
                    }

                    Divider()

                    settingRow(
                        title: L10n.tr("应答语音"),
                        detail: autoAnswerGreetingDetail
                    ) {
                        Picker("应答语音", selection: Binding(
                            get: { autoAnswerGreeting.source },
                            set: { autoAnswerGreeting.setSource($0) }
                        )) {
                            ForEach(AutoAnswerGreetingSource.allCases) { source in
                                Text(source.title).tag(source)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 160)
                    }

                    if autoAnswerGreeting.source == .text {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(
                                L10n.tr("接通后向对方播放的文字"),
                                text: Binding(
                                    get: { autoAnswerGreeting.text },
                                    set: { autoAnswerGreeting.setText($0) }
                                ),
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2 ... 4)

                            HStack {
                                Spacer(minLength: 0)
                                greetingPreviewButton
                            }
                        }
                    } else if autoAnswerGreeting.source == .recording {
                        HStack(spacing: 8) {
                            Button("选择…") {
                                chooseGreetingRecording()
                            }
                            .adaptiveGlassButton()
                            .controlSize(.small)

                            Button(
                                autoAnswerGreeting.isRecording
                                    ? L10n.tr("停止录制")
                                    : L10n.tr("开始录制")
                            ) {
                                toggleGreetingRecording()
                            }
                            .adaptiveGlassButton()
                            .controlSize(.small)

                            greetingPreviewButton

                            Button("清除") {
                                autoAnswerGreeting.clearRecording()
                            }
                            .adaptiveGlassButton()
                            .controlSize(.small)
                            .disabled(
                                autoAnswerGreeting.recordingDisplayName == nil &&
                                    !autoAnswerGreeting.isRecording
                            )
                        }
                    }
                }
                .padding(16)
            }

            settingsSection(title: L10n.tr("通话录音")) {
                settingRow(
                    title: L10n.tr("通话时自动录音"),
                    detail: L10n.tr("通话接通且音频就绪后自动开始，录音仅保存在这台 Mac")
                ) {
                    Toggle("通话时自动录音", isOn: Binding(
                        get: { appState.automaticallyRecordCalls },
                        set: { enabled in
                            if enabled, !recordingConsent {
                                isConfirmingAutomaticRecording = true
                            } else {
                                appState.setAutomaticallyRecordCalls(enabled)
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.adaptiveGlass)
                }
                .padding(16)
            }

            settingsSection(title: L10n.tr("短信处理")) {
                VStack(spacing: 12) {
                    settingRow(
                        title: L10n.tr("已读验证码自动删除"),
                        detail: L10n.tr("标记已读 30 分钟后，从模块/SIM 与本地永久删除")
                    ) {
                        Toggle("已读验证码自动删除", isOn: Binding(
                            get: { appState.autoDeleteReadVerificationMessages },
                            set: { enabled in
                                if enabled {
                                    isConfirmingVerificationAutoDelete = true
                                } else {
                                    appState.setAutoDeleteReadVerificationMessages(false)
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.adaptiveGlass)
                    }

                    inlineCallout(
                        L10n.tr("删除后无法恢复，开启时需要确认。"),
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                .padding(16)
            }
        }
    }

    private var webhookSettings: some View {
        VStack(spacing: 16) {
            settingsSection(title: L10n.tr("转发哪些通知")) {
                VStack(alignment: .leading, spacing: 12) {
                    settingRow(
                        title: L10n.tr("启用通知转发"),
                        status: smsWebhook.configuration.isEnabled ? L10n.tr("已开启") : nil,
                        statusColor: .green,
                        detail: L10n.tr("将勾选的通知 POST JSON 到指定地址")
                    ) {
                        Toggle("启用通知转发", isOn: Binding(
                            get: { smsWebhook.configuration.isEnabled },
                            set: { smsWebhook.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.adaptiveGlass)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(SMSWebhookEventKind.allCases) { kind in
                            Divider()
                            settingRow(
                                title: kind.title,
                                detail: kind.detail
                            ) {
                                Toggle(kind.title, isOn: Binding(
                                    get: { smsWebhook.configuration.forwards(kind) },
                                    set: { smsWebhook.setEvent(kind, enabled: $0) }
                                ))
                                .labelsHidden()
                                .toggleStyle(.adaptiveGlass)
                            }
                        }
                    }
                    .padding(.leading, 20)
                    .disabled(!smsWebhook.configuration.isEnabled)

                    if smsWebhook.configuration.isEnabled,
                       smsWebhook.configuration.forwardedEvents.isEmpty {
                        inlineCallout(
                            L10n.tr("请至少勾选一种要转发的通知。"),
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    }
                }
                .padding(16)
            }

            settingsSection(title: L10n.tr("出站渠道")) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.tr("Webhook 类型"))
                            .font(.headline)
                        Text(L10n.tr("可多选。点选渠道后填写该渠道的地址；请求体会按类型填入，可再自行修改。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        WrappingHStack(spacing: 8) {
                            ForEach(SMSWebhookPreset.allCases) { preset in
                                webhookPresetChip(preset)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.tr("Webhook 地址"))
                            .font(.headline)
                        TextField(
                            smsWebhook.configuration.preset.urlPlaceholder,
                            text: Binding(
                                get: { smsWebhook.configuration.url },
                                set: { smsWebhook.setURL($0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                    }

                    if let extraTitle = smsWebhook.configuration.preset.extraFieldTitle {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(extraTitle)
                                .font(.headline)
                            TextField(
                                extraTitle,
                                text: Binding(
                                    get: { smsWebhook.configuration.extra },
                                    set: { smsWebhook.setExtra($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    if smsWebhook.configuration.preset.usesSecret {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(smsWebhook.configuration.preset.secretTitle)
                                .font(.headline)
                            SecureField(
                                smsWebhook.configuration.preset.secretTitle,
                                text: Binding(
                                    get: { smsWebhook.configuration.secret },
                                    set: { smsWebhook.setSecret($0) }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            Text(smsWebhook.configuration.preset.secretCaption)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if smsWebhook.configuration.preset == .custom {
                        webhookCustomHeaders
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(L10n.tr("请求体"))
                                .font(.headline)
                            Button {
                                isWebhookVariableHelpPresented = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.tr("查看可用变量"))
                            .accessibilityLabel(L10n.tr("查看可用变量"))
                            .popover(
                                isPresented: $isWebhookVariableHelpPresented,
                                arrowEdge: .bottom
                            ) {
                                webhookVariableHelpPopover
                            }
                            Spacer(minLength: 0)
                        }
                        TextEditor(
                            text: Binding(
                                get: { smsWebhook.configuration.effectiveBodyTemplate },
                                set: { smsWebhook.setBodyTemplate($0) }
                            )
                        )
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 132, maxHeight: 220)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                    }

                    HStack {
                        Spacer(minLength: 0)
                        if smsWebhook.inFlightCount > 0 {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button(L10n.tr("发送测试请求")) {
                                smsWebhook.deliverTest()
                            }
                            .adaptiveGlassButton()
                            .controlSize(.small)
                            .disabled(smsWebhook.configuration.sendablePresets.isEmpty)
                        }
                    }

                    if smsWebhook.configuration.isEnabled,
                       smsWebhook.configuration.selectedPresets.isEmpty {
                        inlineCallout(
                            L10n.tr("请至少选择一个出站渠道。"),
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    } else if smsWebhook.configuration.isEnabled,
                              smsWebhook.configuration.selectedPresets.contains(
                                smsWebhook.configuration.preset
                              ),
                              smsWebhook.configuration.resolvedURL == nil {
                        inlineCallout(
                            L10n.tr("请填写有效的 http 或 https 地址。"),
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    } else if smsWebhook.configuration.isEnabled,
                              smsWebhook.configuration.selectedPresets.contains(
                                smsWebhook.configuration.preset
                              ),
                              smsWebhook.configuration.preset.requiresChatID,
                              smsWebhook.configuration.trimmedExtra.isEmpty {
                        inlineCallout(
                            L10n.tr("请填写 Chat ID 或 QQ 号。"),
                            systemImage: "exclamationmark.triangle.fill",
                            color: .orange
                        )
                    }

                    inlineCallout(
                        L10n.tr("通知内容会发送到你配置的地址，请只填写受信任的接收端。"),
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                .padding(16)
            }
        }
    }

    private var webhookVariableHelpPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("可用变量"))
                .font(.headline)
            Text(L10n.tr("在请求体中写成 {{event}} 这种形式，发送时会替换成实际内容。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            ForEach(SMSWebhookPayloadBuilder.placeholderHelpItems, id: \.key) { item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("{{\(item.key)}}")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(width: 158, alignment: .leading)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(width: 420)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("可用变量"))
    }

    private var webhookCustomHeaders: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("请求头"))
                .font(.headline)
            ForEach(smsWebhook.configuration.customHeaders) { header in
                HStack(spacing: 8) {
                    TextField(
                        L10n.tr("名称"),
                        text: webhookHeaderBinding(header, \.name)
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    TextField(
                        L10n.tr("值"),
                        text: webhookHeaderBinding(header, \.value)
                    )
                    .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) {
                        var headers = smsWebhook.configuration.customHeaders
                        headers.removeAll { $0.id == header.id }
                        smsWebhook.setCustomHeaders(headers)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.tr("删除请求头"))
                }
            }
            Button(L10n.tr("添加请求头"), systemImage: "plus") {
                var headers = smsWebhook.configuration.customHeaders
                headers.append(SMSWebhookHeader())
                smsWebhook.setCustomHeaders(headers)
            }
            .adaptiveGlassButton()
            .controlSize(.small)
            Text(L10n.tr("会随 POST 请求一起发送，可覆盖默认的 Content-Type 和 User-Agent。"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func webhookPresetChip(_ preset: SMSWebhookPreset) -> some View {
        let selected = smsWebhook.configuration.selectedPresets.contains(preset)
        let focused = smsWebhook.configuration.preset == preset
        return Button {
            smsWebhook.setPreset(preset)
        } label: {
            Text(preset.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            focused
                                ? Color.accentColor
                                : selected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.10),
                            lineWidth: focused ? 1.5 : 1
                        )
                }
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func webhookHeaderBinding(
        _ header: SMSWebhookHeader,
        _ keyPath: WritableKeyPath<SMSWebhookHeader, String>
    ) -> Binding<String> {
        Binding(
            get: {
                smsWebhook.configuration.customHeaders.first(where: { $0.id == header.id })?[keyPath: keyPath]
                    ?? header[keyPath: keyPath]
            },
            set: { value in
                var headers = smsWebhook.configuration.customHeaders
                guard let index = headers.firstIndex(where: { $0.id == header.id }) else { return }
                headers[index][keyPath: keyPath] = value
                smsWebhook.setCustomHeaders(headers)
            }
        )
    }

    private func soundSettingRow(_ kind: AlertSoundKind) -> some View {
        settingRow(
            title: kind.title,
            detail: alertSounds.displayName(for: kind)
        ) {
            HStack(spacing: 8) {
                Button {
                    previewSound(kind)
                } label: {
                    Label(
                        alertSounds.previewingKind == kind ? L10n.tr("停止") : L10n.tr("试听"),
                        systemImage: alertSounds.previewingKind == kind
                            ? "stop.fill"
                            : "play.fill"
                    )
                }
                .adaptiveGlassButton()
                .controlSize(.small)

                Button("选择…") {
                    chooseCustomSound(kind)
                }
                .adaptiveGlassButton()
                .controlSize(.small)

                if !alertSounds.isUsingDefault(kind) {
                    Button {
                        alertSounds.restoreDefault(for: kind)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .adaptiveGlassButton()
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .help("恢复默认")
                    .accessibilityLabel(L10n.tr("恢复默认%@", kind.title))
                }
            }
        }
    }

    private func previewSound(_ kind: AlertSoundKind) {
        do {
            try alertSounds.togglePreview(for: kind)
        } catch {
            soundImportError = error.localizedDescription
        }
    }

    private func chooseCustomSound(_ kind: AlertSoundKind) {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择%@", kind.title)
        panel.prompt = L10n.tr("选择")
        panel.message = L10n.tr("音频将复制到 CellDock 的应用支持目录，原文件可以安全移动或删除。")
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let sourceURL = panel.url else { return }
            Task { @MainActor in
                do {
                    try alertSounds.installCustomSound(from: sourceURL, for: kind)
                } catch {
                    soundImportError = error.localizedDescription
                }
            }
        }
    }

    private var moduleStatusStrip: some View {
        HStack(spacing: 14) {
            Text(cellularSummary)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer(minLength: 12)

            HStack(spacing: 7) {
                Circle()
                    .fill(moduleStatusColor)
                    .frame(width: 8, height: 8)
                Text(moduleStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(moduleStatusColor)
            }
        }
        .adaptiveGlassSurface(
            cornerRadius: 18,
            padding: 16,
            treatment: .clear,
            tint: moduleStatusColor.opacity(0.045)
        )
        .accessibilityElement(children: .combine)
    }

    private var permissionSettings: some View {
        VStack(spacing: 16) {
            settingsSection(title: L10n.tr("通知")) {
                settingRow(
                    title: L10n.tr("系统通知"),
                    status: notificationPermissionStatus.text,
                    statusColor: notificationPermissionStatus.color,
                    detail: L10n.tr("用于来电、新短信和未接来电提醒")
                ) {
                    notificationPermissionAccessory
                }
                .padding(16)
            }

            settingsSection(title: L10n.tr("隐私权限")) {
                VStack(spacing: 0) {
                    settingRow(
                        title: L10n.tr("麦克风"),
                        status: microphonePermissionStatus.text,
                        statusColor: microphonePermissionStatus.color,
                        detail: L10n.tr("用于通话时传输本机音频")
                    ) {
                        Button(microphonePermissionButtonTitle) {
                            handleMicrophonePermissionAction()
                        }
                        .adaptiveGlassButton()
                        .controlSize(.small)
                        .frame(width: 112)
                    }
                    .padding(16)

                    Divider().padding(.horizontal, 16)

                    settingRow(
                        title: L10n.tr("通讯录"),
                        status: contactPermissionStatus.text,
                        statusColor: contactPermissionStatus.color,
                        detail: L10n.tr("用于识别来电、短信联系人和拨号")
                    ) {
                        Button(contactPermissionButtonTitle) {
                            handleContactPermissionAction()
                        }
                        .adaptiveGlassButton()
                        .controlSize(.small)
                        .frame(width: 112)
                    }
                    .padding(16)
                }
            }

            inlineMessage(
                L10n.tr("权限由 macOS 管理，可随时在系统设置中更改。"),
                systemImage: "checkmark.shield",
                color: .secondary
            )
            .padding(4)
            .adaptiveGlassSurface(
                cornerRadius: 18,
                padding: 13,
                treatment: .clear
            )
        }
    }

    @ViewBuilder
    private var notificationPermissionAccessory: some View {
        if appState.isRequestingNotificationAuthorization ||
            appState.notificationAuthorizationStatus == .unknown {
            ProgressView()
                .controlSize(.small)
                .frame(width: 112)
        } else {
            Button(notificationPermissionButtonTitle) {
                if appState.notificationAuthorizationStatus == .notDetermined {
                    appState.requestNotificationAuthorization()
                } else {
                    appState.openNotificationSettings()
                }
            }
            .adaptiveGlassButton()
            .controlSize(.small)
            .frame(width: 112)
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider().padding(.horizontal, 16)
            content()
        }
        .adaptiveGlassSurface(
            cornerRadius: 18,
            treatment: .regular
        )
    }

    private func settingRow<Accessory: View>(
        title: String,
        status: String? = nil,
        statusColor: Color = .secondary,
        detail: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    if let status {
                        Text(status)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor)
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 16)
            accessory()
        }
    }

    private func inlineMessage(
        _ text: String,
        systemImage: String,
        color: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(color)
    }

    private func inlineCallout(
        _ text: String,
        systemImage: String,
        color: Color
    ) -> some View {
        inlineMessage(text, systemImage: systemImage, color: color)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .adaptiveGlassSurface(
                cornerRadius: 10,
                treatment: .clear,
                tint: color.opacity(0.08)
            )
    }

    private var selectedAppearanceMode: AppAppearanceMode {
        AppAppearanceMode(rawValue: appearanceModeRawValue) ?? .system
    }

    private var appearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { selectedAppearanceMode },
            set: { mode in
                appearanceModeRawValue = mode.rawValue
                mode.apply()
            }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { languageController.selectedLanguage },
            set: { languageController.select($0) }
        )
    }

    private var launchAtLoginDetail: String {
        switch appState.launchAtLoginStatus {
        case .disabled: return L10n.tr("登录 Mac 后可在后台自动运行 CellDock")
        case .enabled: return L10n.tr("登录 Mac 后在后台运行 CellDock")
        case .unavailable: return L10n.tr("当前应用位置或用户会话不支持登录启动")
        }
    }

    private var cellularSummary: String {
        guard appState.modem.isConnected else { return L10n.tr("SIM 1 · 模块未连接") }
        return (["SIM 1", appState.modem.operatorName, appState.modem.accessTechnology]
            .compactMap { $0 })
            .joined(separator: " · ")
    }

    private var moduleStatusText: String {
        switch appState.modem.operationalState {
        case .absent: return L10n.tr("模块未连接")
        case .enumerating: return L10n.tr("USB 枚举中")
        case .initializing: return L10n.tr("模块初始化中")
        case .configurationRequired: return L10n.tr("模块需要配置")
        case .ready: return L10n.tr("模块已连接")
        case .restarting: return L10n.tr("模块正在重启")
        case .reconnecting: return L10n.tr("模块重新连接中")
        case .failed: return L10n.tr("模块异常")
        }
    }

    private var moduleStatusColor: Color {
        switch appState.modem.operationalState {
        case .ready: return .green
        case .configurationRequired: return .orange
        case .failed: return .red
        case .enumerating, .initializing, .restarting, .reconnecting: return .blue
        case .absent: return .secondary
        }
    }

    private var notificationPermissionStatus: (text: String, color: Color) {
        switch appState.notificationAuthorizationStatus {
        case .unknown: return (L10n.tr("读取中"), .secondary)
        case .notDetermined: return (L10n.tr("未请求"), .secondary)
        case .denied: return (L10n.tr("未允许"), .orange)
        case .authorized: return (L10n.tr("已允许"), .green)
        }
    }

    private var allSettingsPermissionsAllowed: Bool {
        appState.notificationAuthorizationStatus == .authorized &&
            microphoneAuthorizationStatus == .authorized &&
            contacts.authorizationState == .authorized
    }

    private var notificationPermissionButtonTitle: String {
        appState.notificationAuthorizationStatus == .notDetermined
            ? L10n.tr("允许通知")
            : L10n.tr("通知设置…")
    }

    private var microphonePermissionStatus: (text: String, color: Color) {
        switch microphoneAuthorizationStatus {
        case .notDetermined: return (L10n.tr("未请求"), .secondary)
        case .restricted: return (L10n.tr("受限制"), .orange)
        case .denied: return (L10n.tr("未允许"), .orange)
        case .authorized: return (L10n.tr("已允许"), .green)
        @unknown default: return (L10n.tr("未知"), .secondary)
        }
    }

    private var microphonePermissionButtonTitle: String {
        microphoneAuthorizationStatus == .notDetermined
            ? L10n.tr("请求权限")
            : L10n.tr("系统设置…")
    }

    private var contactPermissionStatus: (text: String, color: Color) {
        switch contacts.authorizationState {
        case .notDetermined: return (L10n.tr("未请求"), .secondary)
        case .authorized: return (L10n.tr("已允许"), .green)
        case .denied: return (L10n.tr("未允许"), .orange)
        case .restricted: return (L10n.tr("受限制"), .orange)
        }
    }

    private var contactPermissionButtonTitle: String {
        contacts.authorizationState == .notDetermined
            ? L10n.tr("请求权限")
            : L10n.tr("系统设置…")
    }

    private var autoAnswerGreetingDetail: String {
        switch autoAnswerGreeting.source {
        case .none:
            return L10n.tr("接通后不播放应答")
        case .text:
            return L10n.tr("接通后向对方播放文字语音")
        case .recording:
            return autoAnswerGreeting.recordingDisplayName ?? L10n.tr("尚未选择录音")
        }
    }

    private var greetingPreviewButton: some View {
        Button {
            do {
                try autoAnswerGreeting.togglePreview()
            } catch {
                soundImportError = error.localizedDescription
            }
        } label: {
            Label(
                autoAnswerGreeting.isPreviewing ? L10n.tr("停止") : L10n.tr("试听"),
                systemImage: autoAnswerGreeting.isPreviewing ? "stop.fill" : "play.fill"
            )
        }
        .adaptiveGlassButton()
        .controlSize(.small)
        .disabled(
            autoAnswerGreeting.isRecording ||
                (autoAnswerGreeting.source == .text &&
                    autoAnswerGreeting.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ||
                (autoAnswerGreeting.source == .recording &&
                    autoAnswerGreeting.recordingDisplayName == nil)
        )
    }

    private func chooseGreetingRecording() {
        let panel = NSOpenPanel()
        panel.title = L10n.tr("选择录音…")
        panel.prompt = L10n.tr("选择")
        panel.message = L10n.tr("音频将复制到 CellDock 的应用支持目录，原文件可以安全移动或删除。")
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { response in
            guard response == .OK, let sourceURL = panel.url else { return }
            Task { @MainActor in
                do {
                    try autoAnswerGreeting.installRecording(from: sourceURL)
                } catch {
                    soundImportError = error.localizedDescription
                }
            }
        }
    }

    private func toggleGreetingRecording() {
        if autoAnswerGreeting.isRecording {
            do {
                try autoAnswerGreeting.stopRecording()
            } catch {
                soundImportError = error.localizedDescription
            }
            return
        }
        let start = {
            do {
                try autoAnswerGreeting.startRecording()
            } catch {
                soundImportError = error.localizedDescription
            }
        }
        if microphoneAuthorizationStatus == .notDetermined {
            requestMicrophoneAccess { granted in
                if granted { start() }
            }
        } else if microphoneAuthorizationStatus == .authorized {
            start()
        } else {
            soundImportError = L10n.tr("需要麦克风权限才能录制应答语音。")
        }
    }

    private func handleMicrophonePermissionAction() {
        if microphoneAuthorizationStatus == .notDetermined {
            requestMicrophoneAccess { _ in }
        } else {
            openPrivacySettings(anchor: "Privacy_Microphone")
        }
    }

    private func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                microphoneAuthorizationStatus =
                    AVCaptureDevice.authorizationStatus(for: .audio)
                completion(granted)
            }
        }
    }

    private func handleContactPermissionAction() {
        if contacts.authorizationState == .notDetermined {
            contacts.requestAccess()
        } else {
            contacts.openPrivacySettings()
        }
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func refreshSettingsState() {
        appState.refresh()
        refreshSystemPermissionState()
    }

    private func refreshSystemPermissionState() {
        appState.refreshSystemSettingsStatus()
        contacts.reload()
        microphoneAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    }
}

private struct WrappingHStack: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        for item in arrange(
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
            subviews: subviews
        ).items {
            subviews[item.index].place(
                at: CGPoint(x: bounds.minX + item.origin.x, y: bounds.minY + item.origin.y),
                proposal: ProposedViewSize(item.size)
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, items: [(index: Int, origin: CGPoint, size: CGSize)]) {
        let maxWidth = proposal.width ?? .infinity
        var items: [(index: Int, origin: CGPoint, size: CGSize)] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            items.append((index, CGPoint(x: x, y: y), size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            width = max(width, x - spacing)
        }
        return (CGSize(width: width, height: y + rowHeight), items)
    }
}
