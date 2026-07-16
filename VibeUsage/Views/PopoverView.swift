import SwiftUI

/// Main dashboard content hosted inside the standard application window.
struct PopoverView: View {
    @Environment(AppState.self) private var appState
    @State private var deviceFlowState: DeviceFlowUIState = .idle
    @State private var pendingUserCode: String?
    @State private var setupError: String?
    @State private var deviceFlowTask: Task<Void, Never>?

    enum DeviceFlowUIState {
        case idle
        case awaitingApproval
    }

    var body: some View {
        VStack(spacing: 0) {
            if !appState.isConfigured {
                unconfiguredView
            } else {
                DashboardShellView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.windowBackground)
    }

    // MARK: - Unconfigured State

    private var unconfiguredView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title
            HStack(spacing: 6) {
                Text("Vibe Usage")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppTheme.primaryText)
                if AppConfig.isDev {
                    Text("DEBUG")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(3)
                }
            }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .background(AppTheme.separator)

            VStack(alignment: .leading, spacing: 16) {
                if let pendingUserCode {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)
                        Text("请确认浏览器中显示的验证码与下方一致")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.subtleSurface)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.separator, lineWidth: 1))
                    .cornerRadius(4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("验证码")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppTheme.secondaryText)
                            .textCase(.uppercase)
                        Text(pendingUserCode)
                            .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppTheme.primaryText)
                            .tracking(3)
                    }
                }

                if let setupError {
                    Text(setupError)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                Button {
                    let task = Task { await runDeviceFlow() }
                    deviceFlowTask = task
                } label: {
                    HStack(spacing: 6) {
                        if deviceFlowState == .awaitingApproval {
                            ProgressView()
                                .controlSize(.small)
                                .tint(AppTheme.windowBackground)
                        }
                        Text(deviceFlowState == .awaitingApproval ? "等待浏览器确认…" : "登录并链接数据")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryText)
                .foregroundStyle(AppTheme.windowBackground)
                .disabled(deviceFlowState == .awaitingApproval)

                if deviceFlowState == .awaitingApproval {
                    Button {
                        cancelDeviceFlow()
                    } label: {
                        Text("取消，重新开始")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.secondaryText)
                }
            }
            .padding(16)
        }
    }


    private func runDeviceFlow() async {
        setupError = nil
        deviceFlowState = .awaitingApproval
        pendingUserCode = nil
        defer { deviceFlowState = .idle }

        let baseURL = AppConfig.defaultApiUrl
        let hostname = Host.current().localizedName?.replacingOccurrences(of: ".local", with: "")
        let device: DeviceCodeResponse
        do {
            device = try await requestDeviceCode(baseURL: baseURL, clientName: "Vibe Usage.app", hostname: hostname)
        } catch {
            setupError = "无法连接服务端：\(error.localizedDescription)"
            return
        }

        pendingUserCode = device.userCode
        if let url = URL(string: device.verificationUriComplete) {
            NSWorkspace.shared.open(url)
        }

        let intervalNs = UInt64(max(device.interval, 1)) * 1_000_000_000
        let deadline = Date().addingTimeInterval(TimeInterval(device.expiresIn))

        while Date() < deadline {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: intervalNs)
            if Task.isCancelled { return }
            let res: DevicePollResponse
            do {
                res = try await pollDeviceCode(baseURL: baseURL, deviceCode: device.deviceCode)
            } catch {
                continue
            }
            if let apiKey = res.apiKey {
                pendingUserCode = nil
                appState.configure(apiKey: apiKey, apiUrl: res.apiUrl ?? baseURL)
                await appState.fetchUsageData()
                return
            }
            switch res.error {
            case "authorization_pending", nil:
                continue
            case "access_denied":
                setupError = DeviceFlowError.denied.localizedDescription
                pendingUserCode = nil
                return
            case "expired_token":
                setupError = DeviceFlowError.expired.localizedDescription
                pendingUserCode = nil
                return
            default:
                setupError = "服务端返回未知错误：\(res.error ?? "unknown")"
                pendingUserCode = nil
                return
            }
        }
        setupError = DeviceFlowError.expired.localizedDescription
        pendingUserCode = nil
    }

    /// Abort an in-flight device flow so the user can re-link immediately
    /// instead of waiting out the 15-minute timeout. Cancelling the task makes
    /// runDeviceFlow() return at its next checkpoint; its `defer` resets the
    /// UI state back to idle.
    private func cancelDeviceFlow() {
        deviceFlowTask?.cancel()
        deviceFlowTask = nil
        pendingUserCode = nil
        setupError = nil
        deviceFlowState = .idle
    }

}
