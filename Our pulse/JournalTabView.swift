import SwiftUI

struct JournalTabView: View {
    @Environment(NetworkMonitor.self) private var monitor
    @Environment(\.colorScheme) private var colorScheme
    @State private var titleTrigger = 0

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackgroundView(colorScheme: colorScheme)

                if monitor.history.isEmpty {
                    ContentUnavailableView(
                        "Журнал пуст",
                        systemImage: "lanyardcard",
                        description: Text("Здесь появятся результаты последних проверок сети.")
                    )
                    .symbolEffect(.bounce, value: titleTrigger)
                    .onAppear {
                        titleTrigger += 1
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(monitor.history) { snapshot in
                                JournalSnapshotRow(snapshot: snapshot)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 36)
                    }
                }
            }
            .navigationTitle("Журнал")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

private struct JournalSnapshotRow: View {
    let snapshot: NetworkSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: snapshot.state.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(snapshot.state.tint)
                    .frame(width: 42, height: 42)
                    .background(snapshot.state.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.state.title)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.primary)

                    Text(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }

            Text(snapshot.headline)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                JournalMetaBadge(
                    title: snapshot.connectionKind.title,
                    systemImage: snapshot.connectionKind.symbolName,
                    tint: .blue
                )

                JournalMetaBadge(
                    title: snapshot.isVPNActive ? "VPN включен" : "VPN выключен",
                    systemImage: snapshot.isVPNActive ? "lock.shield.fill" : "lock.open",
                    tint: snapshot.isVPNActive ? .orange : .green
                )
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        }
    }
}

private struct JournalMetaBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(tint.opacity(0.12), in: Capsule(style: .continuous))
    }
}
