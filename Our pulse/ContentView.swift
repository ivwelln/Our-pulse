//
//  ContentView.swift
//  Our pulse
//
//  Created by Иван Солончак on 26.03.2026.
//

import SwiftUI
import UserNotifications

struct ContentView: View {
    @Environment(NetworkMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        @Bindable var monitor = monitor

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    StatusHero(snapshot: monitor.lastSnapshot, isChecking: monitor.isChecking)

                    ControlPanel(
                        isChecking: monitor.isChecking,
                        notificationStatus: monitor.notificationStatus,
                        backgroundRefreshStatus: monitor.backgroundRefreshStatus,
                        nextBackgroundRefreshDate: monitor.nextBackgroundRefreshDate,
                        onRefresh: {
                            Task {
                                await monitor.runManualCheck()
                            }
                        },
                        onRequestNotifications: {
                            Task {
                                await monitor.requestNotificationPermissionIfNeeded(forcePrompt: true)
                            }
                        }
                    )

                    EndpointSection(endpoints: $monitor.endpoints)

                    if !monitor.history.isEmpty {
                        HistorySection(history: monitor.history)
                    }
                }
                .padding(20)
            }
            .background(backgroundView)
            .navigationTitle("Our Pulse")
        }
        .task {
            await monitor.handleViewAppeared()
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        let palette = colorScheme == .dark ? darkPalette : lightPalette

        ZStack {
            LinearGradient(colors: palette.background, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            Circle()
                .fill(palette.orbA)
                .frame(width: 240, height: 240)
                .blur(radius: 70)
                .offset(x: -130, y: -240)

            Circle()
                .fill(palette.orbB)
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: 170, y: 260)
        }
    }

    private var lightPalette: BackgroundPalette {
        BackgroundPalette(
            background: [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.86, green: 0.92, blue: 0.98)],
            orbA: Color(red: 0.43, green: 0.76, blue: 0.98).opacity(0.28),
            orbB: Color(red: 0.47, green: 0.95, blue: 0.80).opacity(0.24)
        )
    }

    private var darkPalette: BackgroundPalette {
        BackgroundPalette(
            background: [Color(red: 0.06, green: 0.09, blue: 0.14), Color(red: 0.08, green: 0.13, blue: 0.19)],
            orbA: Color(red: 0.20, green: 0.58, blue: 0.88).opacity(0.30),
            orbB: Color(red: 0.14, green: 0.72, blue: 0.60).opacity(0.24)
        )
    }
}

private struct StatusHero: View {
    let snapshot: NetworkSnapshot?
    let isChecking: Bool

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 18) {
                Label(snapshot?.state.title ?? "Ожидание первого замера", systemImage: snapshot?.state.symbol ?? "waveform.path.ecg")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(snapshot?.state.tint ?? .primary)
                    .contentTransition(.symbolEffect(.replace))

                Text(snapshot?.state.description ?? "Добавьте адреса и выполните первую проверку.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    MetricPill(title: "Активно", value: "каждую минуту")
                    MetricPill(title: "В фоне", value: "не раньше 15 мин")
                    MetricPill(
                        title: "Последняя",
                        value: snapshot.map { $0.checkedAt.formatted(date: .omitted, time: .shortened) } ?? "нет"
                    )
                }

                if isChecking {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Выполняется сетевой замер")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ControlPanel: View {
    let isChecking: Bool
    let notificationStatus: UNAuthorizationStatus
    let backgroundRefreshStatus: UIBackgroundRefreshStatus
    let nextBackgroundRefreshDate: Date?
    let onRefresh: () -> Void
    let onRequestNotifications: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Управление")
                    .font(.headline)

                HStack(spacing: 12) {
                    Button("Проверить сейчас", action: onRefresh)
                        .buttonStyle(.glassProminent)
                        .disabled(isChecking)

                    if notificationStatus == .notDetermined || notificationStatus == .denied {
                        Button("Разрешить уведомления", action: onRequestNotifications)
                            .buttonStyle(.glass)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    StatusRow(label: "Уведомления", value: notificationTitle)
                    StatusRow(label: "Background Refresh", value: backgroundRefreshTitle)
                    StatusRow(
                        label: "Следующая фоновая попытка",
                        value: nextBackgroundRefreshDate?.formatted(date: .omitted, time: .shortened) ?? "будет назначена системой"
                    )
                }
            }
        }
    }

    private var notificationTitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            "включены"
        case .notDetermined:
            "не запрошены"
        case .denied:
            "запрещены"
        @unknown default:
            "неизвестно"
        }
    }

    private var backgroundRefreshTitle: String {
        switch backgroundRefreshStatus {
        case .available:
            "доступен"
        case .denied:
            "запрещен в системе"
        case .restricted:
            "ограничен"
        @unknown default:
            "неизвестно"
        }
    }
}

private struct EndpointSection: View {
    @Binding var endpoints: [MonitoredEndpoint]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Адреса")
                        .font(.headline)

                    Spacer()

                    Button("Добавить") {
                        endpoints.append(.empty(role: .restricted))
                    }
                    .buttonStyle(.glass)
                }

                ForEach($endpoints) { endpoint in
                    EndpointEditor(endpoint: endpoint)
                }

                if endpoints.isEmpty {
                    Text("Нужен минимум один адрес из белого списка и один вне него.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct EndpointEditor: View {
    @Binding var endpoint: MonitoredEndpoint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Роль", selection: $endpoint.role) {
                    ForEach(EndpointRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Вкл", isOn: $endpoint.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            TextField("https://example.com", text: $endpoint.urlString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct HistorySection: View {
    let history: [NetworkSnapshot]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Последние проверки")
                    .font(.headline)

                ForEach(history.prefix(6)) { snapshot in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(snapshot.state.title, systemImage: snapshot.state.symbol)
                                .foregroundStyle(snapshot.state.tint)
                            Spacer()
                            Text(snapshot.checkedAt.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline.weight(.semibold))

                        Text(snapshot.summary)
                            .font(.footnote)
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

    var body: some View {
        content
            .padding(20)
            .glassEffect(.regular.tint(.white.opacity(0.05)).interactive(), in: .rect(cornerRadius: 28))
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

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}

private struct BackgroundPalette {
    let background: [Color]
    let orbA: Color
    let orbB: Color
}

#Preview {
    ContentView()
        .environment(NetworkMonitor.preview)
}
