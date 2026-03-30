import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var journalTrigger = 0
    @State private var homeTrigger = 0
    @State private var settingsTrigger = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            JournalTabView()
                .tabItem {
                    AnimatedTabItemLabel(
                        title: "Журнал",
                        systemImage: "lanyardcard",
                        selectedSystemImage: "lanyardcard.fill",
                        isSelected: selectedTab == .journal,
                        effect: .bounce,
                        trigger: journalTrigger
                    )
                }
                .tag(AppTab.journal)

            HomeTabView()
                .tabItem {
                    AnimatedTabItemLabel(
                        title: "Главная",
                        systemImage: "house",
                        selectedSystemImage: "house.fill",
                        isSelected: selectedTab == .home,
                        effect: .bounce,
                        trigger: homeTrigger
                    )
                }
                .tag(AppTab.home)

            SettingsTabView()
                .tabItem {
                    AnimatedTabItemLabel(
                        title: "Настройки",
                        systemImage: "gear",
                        selectedSystemImage: "gearshape.fill",
                        isSelected: selectedTab == .settings,
                        effect: .rotate,
                        trigger: settingsTrigger
                    )
                }
                .tag(AppTab.settings)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: selectedTab)
        .onAppear {
            homeTrigger += 1
        }
        .onChange(of: selectedTab, initial: false) { _, newValue in
            switch newValue {
            case .journal:
                journalTrigger += 1
            case .home:
                homeTrigger += 1
            case .settings:
                settingsTrigger += 1
            }
        }
    }
}

enum AppTab: Hashable {
    case journal
    case home
    case settings
}

private enum TabItemEffect {
    case bounce
    case rotate
}

private struct AnimatedTabItemLabel: View {
    let title: String
    let systemImage: String
    let selectedSystemImage: String
    let isSelected: Bool
    let effect: TabItemEffect
    let trigger: Int

    var body: some View {
        VStack(spacing: 4) {
            symbol
            Text(title)
        }
    }

    @ViewBuilder
    private var symbol: some View {
        let image = Image(systemName: isSelected ? selectedSystemImage : systemImage)

        switch effect {
        case .bounce:
            image.symbolEffect(.bounce, value: trigger)
        case .rotate:
            image.symbolEffect(.rotate.clockwise.byLayer, value: trigger)
        }
    }
}

struct MainDashboardView: View {
    @Environment(NetworkMonitor.self) private var monitor
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppBackgroundView(colorScheme: colorScheme)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HeaderBlock()

                    StatusHero(
                        snapshot: monitor.lastSnapshot,
                        isChecking: monitor.isChecking
                    )

                    PullRefreshHeader(isChecking: monitor.isChecking)

#if DEBUG
                    DebugDetailsSection(
                        monitor: monitor,
                        openEndpoint: openEndpoint
                    )
#endif
                }
                .padding(.horizontal, 20)
                .padding(.top, 34)
                .padding(.bottom, 32)
            }
            .refreshable {
                await monitor.performUserInitiatedRefresh()
            }
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .bottom) {
            if monitor.notificationStatus == .denied {
                NotificationPermissionBanner(openSettings: openNotificationSettings)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }
        }
        .task {
            await monitor.handleViewAppeared()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else {
            return
        }
        openURL(url)
    }

    private func openEndpoint(_ endpoint: MonitoredEndpoint) {
        guard let url = URL(string: endpoint.urlString) else {
            return
        }
        openURL(url)
    }
}

struct AppBackgroundView: View {
    let colorScheme: ColorScheme

    var body: some View {
        let palette = backgroundPalette

        ZStack {
            LinearGradient(
                colors: palette.background,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: palette.halo,
                center: .top,
                startRadius: 30,
                endRadius: 340
            )
            .scaleEffect(1.2)
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .fill(palette.ridge)
                .frame(width: 300, height: 120)
                .rotationEffect(.degrees(-14))
                .blur(radius: 12)
                .offset(x: 110, y: -120)

            RoundedRectangle(cornerRadius: 96, style: .continuous)
                .fill(palette.accent)
                .frame(width: 240, height: 150)
                .rotationEffect(.degrees(20))
                .blur(radius: 18)
                .offset(x: -145, y: 160)

            RadialGradient(
                colors: [palette.vignette, .clear],
                center: .bottom,
                startRadius: 40,
                endRadius: 460
            )
            .ignoresSafeArea()
        }
    }

    private var backgroundPalette: BackgroundPalette {
        switch colorScheme {
        case .dark:
            BackgroundPalette(
                background: [Color(red: 0.06, green: 0.10, blue: 0.16), Color(red: 0.10, green: 0.16, blue: 0.24)],
                ridge: Color(red: 0.92, green: 0.52, blue: 0.28).opacity(0.28),
                halo: [
                    Color(red: 0.22, green: 0.30, blue: 0.52).opacity(0.84),
                    Color(red: 0.12, green: 0.46, blue: 0.76).opacity(0.52),
                    Color(red: 0.10, green: 0.64, blue: 0.56).opacity(0.32),
                    Color.clear
                ],
                accent: Color(red: 0.94, green: 0.76, blue: 0.36).opacity(0.20),
                vignette: Color.black.opacity(0.34)
            )
        default:
            BackgroundPalette(
                background: [Color(red: 0.96, green: 0.98, blue: 1.0), Color(red: 0.84, green: 0.91, blue: 0.99)],
                ridge: Color(red: 1.0, green: 0.71, blue: 0.44).opacity(0.34),
                halo: [
                    Color(red: 1.0, green: 0.97, blue: 0.82).opacity(0.92),
                    Color(red: 0.69, green: 0.84, blue: 1.0).opacity(0.72),
                    Color(red: 0.78, green: 0.97, blue: 0.90).opacity(0.45),
                    Color.clear
                ],
                accent: Color(red: 1.0, green: 0.86, blue: 0.62).opacity(0.38),
                vignette: Color(red: 0.74, green: 0.84, blue: 0.94).opacity(0.30)
            )
        }
    }
}

private struct HeaderBlock: View {
    @Environment(NetworkMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsVPNNotice = false
    @State private var vpnBounceTrigger = 0
    @State private var vpnNoticeTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Text("На пульсе")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(titleColor)
                    .offset(x: showsVPNNotice ? -280 : 0)
                    .opacity(showsVPNNotice ? 0.18 : 1)
                    .animation(.spring(response: 0.38, dampingFraction: 0.82), value: showsVPNNotice)

                Spacer(minLength: 0)

                if monitor.isVPNActive {
                    vpnIndicator
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }

            Text("Быстрая проверка текущего состояния сети и признаков белых списков.")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(subtitleColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 50)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: monitor.isVPNActive)
        .onChange(of: monitor.lastSnapshot?.checkedAt, initial: false) { _, newValue in
            guard newValue != nil, monitor.isVPNActive else { return }
            vpnBounceTrigger += 1
        }
        .onDisappear {
            vpnNoticeTask?.cancel()
        }
    }

    private var titleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.96) : Color(red: 0.08, green: 0.14, blue: 0.26)
    }

    private var subtitleColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.68) : Color(red: 0.24, green: 0.35, blue: 0.50)
    }

    private var vpnIndicator: some View {
        Button {
            presentVPNNotice()
        } label: {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.20))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass(.clear.interactive()))
        .symbolEffect(.bounce, value: vpnBounceTrigger)
        .offset(y: -4)
        .overlay(alignment: .leading) {
            if showsVPNNotice {
                Text("При активном VPN соединении измерения могут быть неточными.")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(width: 220, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .glassEffect(.regular.tint(Color(red: 1.0, green: 0.80, blue: 0.40).opacity(0.34)), in: .rect(cornerRadius: 20))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color(red: 1.0, green: 0.67, blue: 0.24).opacity(0.55), lineWidth: 1)
                    }
                    .offset(x: -260, y: -3)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private func presentVPNNotice() {
        vpnNoticeTask?.cancel()

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            showsVPNNotice = true
        }

        vpnNoticeTask = Task {
            try? await Task.sleep(for: .seconds(3))

            guard !Task.isCancelled else { return }

            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    showsVPNNotice = false
                }
            }
        }
    }
}

private struct NotificationPermissionBanner: View {
    let openSettings: () -> Void

    var body: some View {
        Button(action: openSettings) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bell.badge.slash.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Разрешите уведомления, чтобы вовремя узнавать о включении белых списков")
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct PullRefreshHeader: View {
    let isChecking: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isChecking ? "arrow.trianglehead.2.clockwise.rotate.90" : "arrow.down.circle")
                .font(.system(size: 12, weight: .semibold))

            Text(isChecking ? "Обновляем…" : "Потяните вниз, чтобы обновить")
                .font(.system(.footnote, design: .rounded, weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

private struct StatusHero: View {
    let snapshot: NetworkSnapshot?
    let isChecking: Bool
    @Environment(NetworkMonitor.self) private var monitor
    @State private var symbolAnimationTrigger = 0
    @State private var cardPulseScale = 1.0
    @State private var cardPulseOpacity = 0.0
    @State private var cardLift: CGFloat = 0

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Text("Состояние сети")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    AnimatedStatusSymbol(
                        state: snapshot?.state ?? .unknown,
                        trigger: symbolAnimationTrigger
                    )

                    Text(snapshot?.state.title ?? "Ожидание первой проверки")
                }
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(snapshot?.state.tint ?? .primary)
                .contentTransition(.symbolEffect(.replace))

                Text(snapshot?.headline ?? "Первый замер появится сразу после запуска.")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let snapshot {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(visibleDetails(for: snapshot), id: \.self) { detail in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 6))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 6)
                                Text(detail)
                                    .font(.system(.footnote, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                LastCheckPanel(
                    snapshot: snapshot
                )

#if DEBUG
                BackgroundDebugPanel(monitor: monitor)
#endif

#if DEBUG
                Button("Симулировать фон") {
                    Task {
                        await NetworkMonitor.shared.runCheck(origin: .background)
                    }
                }
                .buttonStyle(.glass)
#endif

                if isChecking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Проверяем доступность адресов")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scaleEffect(cardPulseScale)
        .offset(y: cardLift)
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill((snapshot?.state.tint ?? .secondary).opacity(cardPulseOpacity))
                .blur(radius: 8)
                .padding(-6)
        }
        .onChange(of: snapshot?.checkedAt, initial: snapshot != nil) { _, newValue in
            guard newValue != nil else { return }
            runStatusAnimations()
        }
    }

    private func visibleDetails(for snapshot: NetworkSnapshot) -> [String] {
        snapshot.details.filter { detail in
            !detail.localizedCaseInsensitiveContains("VPN")
        }
    }

    private func runStatusAnimations() {
        symbolAnimationTrigger += 1
        cardPulseScale = 0.985
        cardPulseOpacity = 0.22
        cardLift = -4

        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
            cardPulseScale = 1.01
            cardLift = -8
        }

        withAnimation(.easeOut(duration: 0.75)) {
            cardPulseOpacity = 0
        }

        withAnimation(.spring(response: 0.8, dampingFraction: 0.82).delay(0.08)) {
            cardPulseScale = 1
            cardLift = 0
        }
    }
}

private struct AnimatedStatusSymbol: View {
    let state: NetworkState
    let trigger: Int

    var body: some View {
        Image(systemName: state.symbol)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce, value: trigger)
            .symbolEffect(.pulse, isActive: state == .whitelistOn || state == .offline)
            .symbolEffect(.rotate.clockwise.byLayer, isActive: state == .whitelistOff)
    }
}

#if DEBUG
private struct BackgroundDebugPanel: View {
    let monitor: NetworkMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Отладка фона")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(backgroundRefreshStatusLine)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(scheduleAttemptLine)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(scheduleErrorLine)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(monitor.lastBackgroundScheduleError == nil ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)

            Text(refreshStartLine)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var backgroundRefreshStatusLine: String {
        "Refresh status: \(monitor.backgroundRefreshStatus.debugLabel)"
    }

    private var scheduleAttemptLine: String {
        "Schedule attempt: \(monitor.lastBackgroundScheduleAttempt?.formatted(date: .omitted, time: .standard) ?? "none")"
    }

    private var scheduleErrorLine: String {
        "Schedule error: \(monitor.lastBackgroundScheduleError ?? "none")"
    }

    private var refreshStartLine: String {
        "Last BG start: \(monitor.lastBackgroundRefreshStart?.formatted(date: .omitted, time: .standard) ?? "none")"
    }
}
#endif

#if DEBUG
private struct DebugDetailsSection: View {
    let monitor: NetworkMonitor
    let openEndpoint: (MonitoredEndpoint) -> Void

    var body: some View {
        VStack(spacing: 20) {
            debugMetrics

            EndpointSection(
                endpoints: monitor.endpoints,
                lastResults: monitor.lastSnapshot?.results ?? [],
                openEndpoint: openEndpoint
            )

            if !monitor.history.isEmpty {
                HistorySection(history: monitor.history)
            }
        }
    }

    private var debugMetrics: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                MetricPill(title: "Соединение", value: connectionLabel)
                MetricPill(title: "Уведомления", value: notificationLabel)
                MetricPill(title: "BG refresh", value: backgroundRefreshLabel)
            }
            .padding(.horizontal, 2)
        }
    }

    private var connectionLabel: String {
        switch monitor.connectionKind {
        case .wifi:
            "Wi‑Fi"
        case .cellular:
            "Cellular"
        case .wired:
            "Wired"
        case .other:
            "Other"
        case .offline:
            "Offline"
        case .unknown:
            "Unknown"
        }
    }

    private var notificationLabel: String {
        switch monitor.notificationStatus {
        case .authorized:
            "Allowed"
        case .denied:
            "Denied"
        case .notDetermined:
            "Pending"
        case .provisional:
            "Provisional"
        case .ephemeral:
            "Ephemeral"
        @unknown default:
            "Unknown"
        }
    }

    private var backgroundRefreshLabel: String {
        switch monitor.backgroundRefreshStatus {
        case .available:
            "Available"
        case .denied:
            "Denied"
        case .restricted:
            "Restricted"
        @unknown default:
            "Unknown"
        }
    }
}
#endif

private struct EndpointSection: View {
    let endpoints: [MonitoredEndpoint]
    let lastResults: [EndpointProbeResult]
    let openEndpoint: (MonitoredEndpoint) -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Контрольные адреса")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                    Text("Российские адреса сравниваются с зарубежными, чтобы понять текущее состояние сети.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(endpoints.enumerated()), id: \.element.id) { index, endpoint in
                        EndpointRow(
                            endpoint: endpoint,
                            result: lastResults.first(where: { $0.urlString == endpoint.urlString }),
                            isFirst: index == 0,
                            isLast: index == endpoints.count - 1,
                            openEndpoint: openEndpoint
                        )

                        if index < endpoints.count - 1 {
                            Divider()
                                .overlay(.white.opacity(0.18))
                                .padding(.leading, 42)
                        }
                    }
                }
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }
}

private struct EndpointRow: View {
    let endpoint: MonitoredEndpoint
    let result: EndpointProbeResult?
    let isFirst: Bool
    let isLast: Bool
    let openEndpoint: (MonitoredEndpoint) -> Void

    var body: some View {
        Button {
            openEndpoint(endpoint)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Text(endpoint.role == .allowed ? "🇷🇺" : "🌍")
                    .font(.title2)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(endpoint.displayName)
                            .font(.system(.body, design: .rounded, weight: .semibold))

                        Text(endpoint.role.badgeTitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(endpoint.role == .allowed ? .cyan : .orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                    }

                    Text(endpoint.urlString)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        guard let result else { return .primary }

        switch result.outcome {
        case .reachable:
            return .green
        case .unreachable, .invalidURL, .cancelled:
            return .red
        }
    }
}

private struct HistorySection: View {
    let history: [NetworkSnapshot]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Последние проверки")
                    .font(.system(.headline, design: .rounded, weight: .semibold))

                ForEach(history.prefix(6)) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(snapshot.state.title, systemImage: snapshot.state.symbol)
                                .foregroundStyle(snapshot.state.tint)
                            Spacer()
                            Text(snapshot.checkedAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))

                        Text(snapshot.summary)
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .padding(20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(cardBaseFill)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(cardTint)
                        .blur(radius: 14)
                        .opacity(0.65)
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                }
            )
            .glassEffect(.regular.tint(glassTint).interactive(), in: .rect(cornerRadius: 28))
            .shadow(color: shadowColor, radius: 24, x: 0, y: 18)
    }

    private var cardBaseFill: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.10), Color.white.opacity(0.04)]
                : [Color.white.opacity(0.72), Color.white.opacity(0.42)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var cardTint: Color {
        colorScheme == .dark
            ? Color(red: 0.30, green: 0.48, blue: 0.80).opacity(0.18)
            : Color(red: 0.76, green: 0.88, blue: 1.0).opacity(0.28)
    }

    private var cardStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.56)
    }

    private var glassTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.white.opacity(0.10)
    }

    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.30)
            : Color(red: 0.30, green: 0.49, blue: 0.72).opacity(0.16)
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct LastCheckPanel: View {
    let snapshot: NetworkSnapshot?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Последняя проверка")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(snapshot.map { timestamp(for: $0.checkedAt) } ?? "Еще не выполнялся")
                .font(.system(.headline, design: .rounded, weight: .semibold))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(panelStroke, lineWidth: 1)
                }
        )
        .glassEffect(.regular.tint(panelGlassTint), in: .rect(cornerRadius: 22))
    }

    private func timestamp(for date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)

        if calendar.isDateInToday(date) {
            return "Сегодня, \(time)"
        }

        if calendar.isDateInYesterday(date) {
            return "Вчера, \(time)"
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var panelFill: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.18, green: 0.24, blue: 0.34).opacity(0.58),
                    Color(red: 0.10, green: 0.14, blue: 0.22).opacity(0.42)
                ]
                : [
                    Color(red: 0.99, green: 0.97, blue: 0.90).opacity(0.76),
                    Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.62)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var panelStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.58)
    }

    private var panelGlassTint: Color {
        colorScheme == .dark
            ? Color(red: 0.60, green: 0.72, blue: 0.98).opacity(0.08)
            : Color(red: 1.0, green: 0.90, blue: 0.72).opacity(0.14)
    }
}

private struct BackgroundPalette {
    let background: [Color]
    let ridge: Color
    let halo: [Color]
    let accent: Color
    let vignette: Color
}

#Preview {
    ContentView()
        .environment(NetworkMonitor.preview)
}
