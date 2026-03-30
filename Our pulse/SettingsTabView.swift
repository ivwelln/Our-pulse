import SwiftUI

struct SettingsTabView: View {
    @Environment(NetworkMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    @State private var bellTrigger = 0
    @State private var timerTrigger = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView(colorScheme: colorScheme)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        SettingsSectionHeader(
                            title: "Уведомления",
                            subtitle: "Выберите, о каких событиях приложение должно сообщать."
                        )

                        VStack(spacing: 12) {
                            ForEach(NotificationPreference.allCases) { preference in
                                SettingsOptionCard(
                                    title: preference.title,
                                    subtitle: preference.subtitle,
                                    systemImage: preference.symbol,
                                    isSelected: monitor.notificationPreference == preference,
                                    selectionTint: .orange,
                                    effect: .bounce,
                                    trigger: bellTrigger
                                ) {
                                    bellTrigger += 1
                                    monitor.updateNotificationPreference(preference)
                                }
                            }
                        }

                        SettingsSectionHeader(
                            title: "Частота проверки",
                            subtitle: "Определяет, как часто приложение повторяет проверку соединения."
                        )

                        VStack(spacing: 12) {
                            ForEach(CheckInterval.allCases) { interval in
                                SettingsOptionCard(
                                    title: interval.title,
                                    subtitle: interval.subtitle,
                                    systemImage: "timer",
                                    isSelected: monitor.checkInterval == interval,
                                    selectionTint: .blue,
                                    effect: .rotate,
                                    trigger: timerTrigger
                                ) {
                                    timerTrigger += 1
                                    monitor.updateCheckInterval(interval)
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
    }
}

private enum SettingsSymbolEffect {
    case bounce
    case rotate
}

private struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
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
}

private struct SettingsOptionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let selectionTint: Color
    let effect: SettingsSymbolEffect
    var trigger: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? selectionTint : .secondary.opacity(0.6))
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isSelected ? selectionTint.opacity(0.45) : Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: selectionTint.opacity(isSelected ? 0.18 : 0), radius: 14, y: 8)
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1 : 0.995)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isSelected)
    }

    @ViewBuilder
    private var icon: some View {
        let image = Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(isSelected ? selectionTint : .primary)
            .frame(width: 42, height: 42)
            .background(selectionTint.opacity(isSelected ? 0.18 : 0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        switch effect {
        case .bounce:
            image.symbolEffect(.bounce, value: trigger)
        case .rotate:
            image.symbolEffect(.rotate.clockwise.byLayer, value: trigger)
        }
    }
}
