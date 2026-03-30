import SwiftUI

struct SettingsTabView: View {
    @Environment(NetworkMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var notificationNamespace
    @Namespace private var intervalNamespace
    @State private var notificationTrigger = 0
    @State private var intervalTrigger = 0
    @State private var heroTrigger = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView(colorScheme: colorScheme)

                ScrollView {
                    VStack(spacing: 22) {
                        SettingsTopBanner(
                            currentNotification: monitor.notificationPreference,
                            currentInterval: monitor.checkInterval,
                            trigger: heroTrigger
                        )

                        SettingsCurrentModesCard(
                            notificationPreference: monitor.notificationPreference,
                            checkInterval: monitor.checkInterval
                        )

                        SettingsControlSection(
                            title: "Уведомления",
                            subtitle: "Режим оповещений для белых списков и состояния сети.",
                            tint: Color.orange,
                            namespace: notificationNamespace
                        ) {
                            VStack(spacing: 10) {
                                ForEach(NotificationPreference.allCases) { preference in
                                    SettingsSelectionButton(
                                        option: preference,
                                        isSelected: monitor.notificationPreference == preference,
                                        tint: .orange,
                                        namespace: notificationNamespace,
                                        namespaceID: "notification",
                                        trigger: notificationTrigger,
                                        animationStyle: .bounce
                                    ) {
                                        notificationTrigger += 1
                                        monitor.updateNotificationPreference(preference)
                                    }
                                }
                            }
                        }

                        SettingsControlSection(
                            title: "Ритм проверки",
                            subtitle: "Насколько активно приложение следит за изменениями сети.",
                            tint: Color.blue,
                            namespace: intervalNamespace
                        ) {
                            VStack(spacing: 10) {
                                ForEach(CheckInterval.allCases) { interval in
                                    SettingsSelectionButton(
                                        option: interval,
                                        isSelected: monitor.checkInterval == interval,
                                        tint: .blue,
                                        namespace: intervalNamespace,
                                        namespaceID: "interval",
                                        trigger: intervalTrigger,
                                        animationStyle: .rotate
                                    ) {
                                        intervalTrigger += 1
                                        monitor.updateCheckInterval(interval)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            heroTrigger += 1
        }
    }
}

private protocol SettingsOptionPresentable: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String { get }
    var symbol: String { get }
    var eyebrow: String { get }
}

extension NotificationPreference: SettingsOptionPresentable {
    var eyebrow: String {
        switch self {
        case .none:
            "Тишина"
        case .whitelistChanges:
            "Фокус"
        case .whitelistAndConnection:
            "Полный контроль"
        }
    }
}

extension CheckInterval: SettingsOptionPresentable {
    var eyebrow: String {
        switch self {
        case .often:
            "Бодрый режим"
        case .recommended:
            "Баланс"
        case .rarely:
            "Экономия"
        }
    }

    var symbol: String {
        switch self {
        case .often:
            "bolt.badge.clock"
        case .recommended:
            "dial.medium"
        case .rarely:
            "moon.zzz"
        }
    }
}

private enum SettingsAnimationStyle {
    case bounce
    case rotate
}

private struct SettingsTopBanner: View {
    let currentNotification: NotificationPreference
    let currentInterval: CheckInterval
    let trigger: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Тонкая настройка")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Соберите нужный режим работы: от полной тишины до аккуратного контроля сети и белых списков.")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "switch.2")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white.opacity(0.96))
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular.tint(Color.white.opacity(0.14)).interactive(), in: .circle)
                    .symbolEffect(.bounce, value: trigger)
            }

            HStack(spacing: 10) {
                SettingsMiniBadge(
                    title: currentNotification.title,
                    systemImage: currentNotification.symbol,
                    tint: .orange
                )
                SettingsMiniBadge(
                    title: currentInterval.title,
                    systemImage: currentInterval.symbol,
                    tint: .blue
                )
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular.tint(Color.white.opacity(0.12)), in: .rect(cornerRadius: 30))
                .overlay {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
        }
    }
}

private struct SettingsMiniBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.12), in: Capsule(style: .continuous))
    }
}

private struct SettingsCurrentModesCard: View {
    let notificationPreference: NotificationPreference
    let checkInterval: CheckInterval

    var body: some View {
        HStack(spacing: 12) {
            SettingsModeSummaryTile(
                title: "Оповещения",
                value: notificationPreference.title,
                symbol: notificationPreference.symbol,
                tint: .orange
            )

            SettingsModeSummaryTile(
                title: "Проверка",
                value: checkInterval.title,
                symbol: checkInterval.symbol,
                tint: .blue
            )
        }
    }
}

private struct SettingsModeSummaryTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular.tint(Color.white.opacity(0.09)), in: .rect(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}

private struct SettingsControlSection<Content: View>: View {
    let title: String
    let subtitle: String
    let tint: Color
    let namespace: Namespace.ID
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(tint.opacity(0.28))
                    .frame(width: 10, height: 10)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            GlassEffectContainer(spacing: 18) {
                VStack(spacing: 10) {
                    content
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(Color.white.opacity(0.10)), in: .rect(cornerRadius: 30))
                        .overlay {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        }
                }
            }
        }
    }
}

private struct SettingsSelectionButton<Option: SettingsOptionPresentable>: View {
    let option: Option
    let isSelected: Bool
    let tint: Color
    let namespace: Namespace.ID
    let namespaceID: String
    let trigger: Int
    let animationStyle: SettingsAnimationStyle
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                action()
            }
        } label: {
            HStack(spacing: 14) {
                icon

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.eyebrow.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? tint : .secondary)

                    Text(option.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(option.subtitle)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : .secondary.opacity(0.55))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(tint.opacity(0.20)).interactive(), in: .rect(cornerRadius: 22))
                        .matchedGeometryEffect(id: namespaceID, in: namespace)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
    }

    @ViewBuilder
    private var icon: some View {
        let image = Image(systemName: option.symbol)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isSelected ? tint : .primary)
            .frame(width: 44, height: 44)
            .background(tint.opacity(isSelected ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

        switch animationStyle {
        case .bounce:
            image.symbolEffect(.bounce, value: trigger)
        case .rotate:
            image.symbolEffect(.rotate.clockwise.byLayer, value: trigger)
        }
    }
}
