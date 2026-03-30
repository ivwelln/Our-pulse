import BackgroundTasks
import CFNetwork
import Network
import Observation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    static let preview = NetworkMonitor(isPreview: true)

    private enum StorageKey {
        static let snapshot = "monitor.snapshot"
        static let history = "monitor.history"
        static let knownState = "monitor.known-state"
        static let notificationPreference = "monitor.notification-preference"
        static let checkInterval = "monitor.check-interval"
    }

    enum Constants {
        static let backgroundTaskIdentifier = "Ruscan.Our-pulse.refresh"
        static let probeTimeout: TimeInterval = 4
        static let overallProbeDeadline: Duration = .seconds(5)
        static let maxHistoryCount = 20
    }

    var endpoints: [MonitoredEndpoint]
    var displaySnapshot: NetworkSnapshot?
    var lastSnapshot: NetworkSnapshot?
    var history: [NetworkSnapshot]
    var notificationStatus: UNAuthorizationStatus = .notDetermined
    var backgroundRefreshStatus: UIBackgroundRefreshStatus = .available
    var nextBackgroundRefreshDate: Date?
    var isVPNActive = false
    var connectionKind: NetworkConnectionKind = .unknown
    var isChecking = false
    var lastBackgroundScheduleError: String?
    var lastBackgroundScheduleAttempt: Date?
    var lastBackgroundRefreshStart: Date?
    var notificationPreference: NotificationPreference
    var checkInterval: CheckInterval

    private var foregroundLoopTask: Task<Void, Never>?
    private let pathMonitor: NWPathMonitor?
    private let pathMonitorQueue = DispatchQueue(label: "OurPulse.Network.PathMonitor")
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private let isPreview: Bool

    init(isPreview: Bool = false, defaults: UserDefaults = .standard) {
        self.isPreview = isPreview
        self.defaults = defaults
        pathMonitor = isPreview ? nil : NWPathMonitor()
        endpoints = Self.defaultEndpoints
        displaySnapshot = nil
        lastSnapshot = Self.load(NetworkSnapshot.self, key: StorageKey.snapshot, from: defaults)
        history = Self.load([NetworkSnapshot].self, key: StorageKey.history, from: defaults) ?? []
        notificationPreference = Self.load(NotificationPreference.self, key: StorageKey.notificationPreference, from: defaults) ?? .whitelistChanges
        checkInterval = Self.load(CheckInterval.self, key: StorageKey.checkInterval, from: defaults) ?? .thirtyMinutes

        displaySnapshot = lastSnapshot

        if isPreview {
            endpoints = Self.defaultEndpoints
            lastSnapshot = NetworkSnapshot.preview
            displaySnapshot = NetworkSnapshot.preview
            history = [NetworkSnapshot.preview]
            notificationStatus = .authorized
            backgroundRefreshStatus = .available
            isVPNActive = false
            connectionKind = .wifi
            notificationPreference = .whitelistChanges
            checkInterval = .twentyMinutes
            nextBackgroundRefreshDate = .now.addingTimeInterval(checkInterval.timeInterval)
        } else {
            startPathMonitoring()
        }
    }

    func handleViewAppeared() async {
        refreshEnvironmentStatuses()
        await requestNotificationPermissionIfNeeded(forcePrompt: false)
        startForegroundMonitoring()

        if lastSnapshot == nil {
            _ = await runCheck(origin: .startup)
        } else {
            scheduleBackgroundRefresh()
        }
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            refreshEnvironmentStatuses()
            Task {
                await requestNotificationPermissionIfNeeded(forcePrompt: false)
                _ = await runCheck(origin: .sceneActivation)
            }
            startForegroundMonitoring()
        case .inactive:
            foregroundLoopTask?.cancel()
            foregroundLoopTask = nil
        case .background:
            foregroundLoopTask?.cancel()
            foregroundLoopTask = nil
            scheduleBackgroundRefresh()
        @unknown default:
            break
        }
    }

    func runManualCheck() async {
        _ = await runCheck(origin: .manual)
    }

    func performUserInitiatedRefresh() async {
        let task = Task { @MainActor in
            await runManualCheck()
        }
        _ = await task.result
    }

    func requestNotificationPermissionIfNeeded(forcePrompt: Bool) async {
        let settings = await center.notificationSettings()
        notificationStatus = settings.authorizationStatus

        guard notificationPreference != .none else {
            return
        }

        guard forcePrompt || settings.authorizationStatus == .notDetermined else {
            return
        }

        do {
            if try await center.requestAuthorization(options: [.alert, .sound, .badge]) {
                notificationStatus = .authorized
            } else {
                notificationStatus = .denied
            }
        } catch {
            notificationStatus = settings.authorizationStatus
        }
    }

    func scheduleBackgroundRefresh() {
        guard !isPreview else { return }

        let request = BGAppRefreshTaskRequest(identifier: Constants.backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: checkInterval.timeInterval)

        do {
            try BGTaskScheduler.shared.submit(request)
            nextBackgroundRefreshDate = request.earliestBeginDate
            lastBackgroundScheduleError = nil
            lastBackgroundScheduleAttempt = .now
            debugLog("background refresh scheduled: \(request.identifier)", origin: .background)
        } catch {
            nextBackgroundRefreshDate = nil
            lastBackgroundScheduleError = error.localizedDescription
            lastBackgroundScheduleAttempt = .now
            debugLog("background refresh schedule failed: \(error.localizedDescription)", origin: .background)
        }
    }

    func handleBackgroundRefresh(task: BGAppRefreshTask) {
        debugLog("background refresh started", origin: .background)
        lastBackgroundRefreshStart = .now
        scheduleBackgroundRefresh()

        let worker = Task {
            let success = await runCheck(origin: .background)
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            worker.cancel()
        }
    }

    @discardableResult
    func runCheck(origin: CheckOrigin) async -> Bool {
        guard !isChecking else { return false }

        debugLog("runCheck started", origin: origin)
        let activeEndpoints = endpoints.filter(\.isEnabled)
        guard !activeEndpoints.isEmpty else {
            let snapshot = NetworkSnapshot(
                checkedAt: .now,
                state: .unknown,
                results: [],
                summary: "Нет активных адресов для проверки.",
                headline: "Список контрольных адресов пуст",
                details: [
                    "Приложению нечего проверять."
                ],
                connectionKind: connectionKind,
                isVPNActive: isVPNActive
            )
            apply(snapshot)
            scheduleBackgroundRefresh()
            debugLog("runCheck finished: no active endpoints", origin: origin)
            return true
        }

        isChecking = true
        defer { isChecking = false }

        refreshEnvironmentStatuses()

        if connectionKind == .offline {
            let snapshot = NetworkSnapshot(
                checkedAt: .now,
                state: .offline,
                results: [],
                summary: "Сетевой путь недоступен: запросы не запускались.",
                headline: "Нет доступа к сети",
                details: offlineDetails(isVPNActive: isVPNActive),
                connectionKind: connectionKind,
                isVPNActive: isVPNActive
            )

            let previousState = lastSnapshot?.state
            apply(snapshot)

            if let previousState, previousState != snapshot.state {
                await notifyAboutStateChange(from: previousState, to: snapshot.state)
            }

            triggerActiveAppHapticIfNeeded()
            scheduleBackgroundRefresh()
            debugLog("runCheck finished early: path offline", origin: origin)
            return origin != .background || !Task.isCancelled
        }

        let probeTask = Task { [self] in
            await stagedProbe(endpoints: activeEndpoints)
        }
        let completedBeforeDeadline = await didProbeFinishBeforeDeadline(probeTask)

        if !completedBeforeDeadline {
            let snapshot = NetworkSnapshot(
                checkedAt: .now,
                state: .offline,
                results: [],
                summary: "Ни один сервер не ответил в течение \(Self.deadlineDescription).",
                headline: "Нет доступа к сети",
                details: timeoutOfflineDetails(isVPNActive: isVPNActive),
                connectionKind: connectionKind,
                isVPNActive: isVPNActive
            )
            displaySnapshot = snapshot
            debugLog("runCheck provisional timeout: waiting for late responses", origin: origin)
        }

        let results = await probeTask.value
        let analysis = Self.analyze(
            results: results,
            allEndpoints: activeEndpoints,
            isVPNActive: isVPNActive,
            connectionKind: connectionKind
        )
        let snapshot = NetworkSnapshot(
            checkedAt: .now,
            state: analysis.state,
            results: results,
            summary: analysis.summary,
            headline: analysis.headline,
            details: analysis.details,
            connectionKind: connectionKind,
            isVPNActive: isVPNActive
        )

        let previousState = lastSnapshot?.state
        apply(snapshot)

        if let previousState, previousState != snapshot.state {
            await notifyAboutStateChange(from: previousState, to: snapshot.state)
        }

        triggerActiveAppHapticIfNeeded()

        scheduleBackgroundRefresh()
        debugLog("runCheck finished: \\(snapshot.state.rawValue)", origin: origin)
        return origin != .background || !Task.isCancelled
    }

    private func startForegroundMonitoring() {
        guard foregroundLoopTask == nil else { return }

        foregroundLoopTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: checkInterval.duration)
                if Task.isCancelled {
                    break
                }

                _ = await runCheck(origin: .foregroundLoop)
            }
        }
    }

    private func apply(_ snapshot: NetworkSnapshot) {
        displaySnapshot = snapshot
        lastSnapshot = snapshot
        history.insert(snapshot, at: 0)
        history = Array(history.prefix(Constants.maxHistoryCount))
        persist()
    }

    private func refreshEnvironmentStatuses() {
        backgroundRefreshStatus = UIApplication.shared.backgroundRefreshStatus
        isVPNActive = Self.detectVPNConnection()
#if DEBUG
        debugLog("background refresh status: \(backgroundRefreshStatus.debugLabel)", origin: .background)
        debugLog("vpn active: \(isVPNActive)", origin: .background)
        debugLog("connection kind: \(connectionKind.rawValue)", origin: .background)
        if let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] {
            debugLog("permitted identifiers: \(permitted.joined(separator: ", "))", origin: .background)
        } else {
            debugLog("permitted identifiers: missing", origin: .background)
        }
#endif
    }

    private func triggerActiveAppHapticIfNeeded() {
        guard !isPreview else { return }
        guard UIApplication.shared.applicationState == .active else { return }

        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    private func persist() {
        guard !isPreview else { return }

        Self.store(lastSnapshot, key: StorageKey.snapshot, to: defaults)
        Self.store(history, key: StorageKey.history, to: defaults)
        Self.store(notificationPreference, key: StorageKey.notificationPreference, to: defaults)
        Self.store(checkInterval, key: StorageKey.checkInterval, to: defaults)
        defaults.set(lastSnapshot?.state.rawValue, forKey: StorageKey.knownState)
    }

    private func notifyAboutStateChange(from oldState: NetworkState, to newState: NetworkState) async {
        guard oldState != newState else { return }
        guard shouldNotify(from: oldState, to: newState) else { return }

        let settings = await center.notificationSettings()
        notificationStatus = settings.authorizationStatus

        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        debugLog("state change notification: \\(oldState.rawValue) -> \\(newState.rawValue)", origin: .background)
        let notificationVariant = notificationVariant(for: oldState, to: newState)
        let content = UNMutableNotificationContent()
        content.title = notificationVariant.title
        content.body = notificationVariant.body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "network-state-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    private func probe(endpoints: [MonitoredEndpoint]) async -> [EndpointProbeResult] {
        await withTaskGroup(of: EndpointProbeResult.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    await Self.probe(endpoint: endpoint)
                }
            }

            var collected: [EndpointProbeResult] = []
            for await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.urlString < $1.urlString }
        }
    }

    private func stagedProbe(endpoints: [MonitoredEndpoint]) async -> [EndpointProbeResult] {
        let restricted = endpoints.filter { $0.role == .restricted }
        let allowed = endpoints.filter { $0.role == .allowed }

        guard let primaryRestricted = Self.primaryRestrictedEndpoint(from: restricted) else {
            let allowedResults = await probe(endpoints: allowed)
            return allowedResults.sorted { $0.urlString < $1.urlString }
        }

        var collected = [await Self.probe(endpoint: primaryRestricted)]
        if collected.contains(where: \.isReachable) {
            return collected
        }

        let secondaryRestricted = restricted.filter { $0.id != primaryRestricted.id }
        async let secondaryRestrictedResultsTask = probe(endpoints: secondaryRestricted)
        async let allowedResultsTask = probe(endpoints: allowed)

        let secondaryRestrictedResults = await secondaryRestrictedResultsTask
        collected.append(contentsOf: secondaryRestrictedResults)

        if secondaryRestrictedResults.contains(where: \.isReachable) {
            return collected.sorted { $0.urlString < $1.urlString }
        }

        let allowedResults = await allowedResultsTask
        collected.append(contentsOf: allowedResults)
        return collected.sorted { $0.urlString < $1.urlString }
    }

    private func didProbeFinishBeforeDeadline(_ probeTask: Task<[EndpointProbeResult], Never>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                _ = await probeTask.value
                return true
            }

            group.addTask {
                try? await Task.sleep(for: Constants.overallProbeDeadline)
                return false
            }

            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }
    }

    private static func probe(endpoint: MonitoredEndpoint) async -> EndpointProbeResult {
        guard let url = endpoint.probeURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return EndpointProbeResult(
                endpointID: endpoint.id,
                displayName: endpoint.displayName,
                urlString: endpoint.urlString,
                role: endpoint.role,
                isVPNRestricted: endpoint.isVPNRestricted,
                checkedAt: .now,
                outcome: .invalidURL,
                latencyMilliseconds: nil,
                detail: "Некорректный URL"
            )
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = Constants.probeTimeout
        configuration.timeoutIntervalForResource = Constants.probeTimeout
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)

        let start = ContinuousClock.now

        do {
            let response = try await performProbeRequest(with: session, url: url)
            let latency = start.duration(to: .now)
            let validation = validateProbeResponse(response, requestedURL: url)

            return EndpointProbeResult(
                endpointID: endpoint.id,
                displayName: endpoint.displayName,
                urlString: endpoint.urlString,
                role: endpoint.role,
                isVPNRestricted: endpoint.isVPNRestricted,
                checkedAt: .now,
                outcome: validation.outcome,
                latencyMilliseconds: Int(latency.components.seconds * 1_000) + Int(latency.components.attoseconds / 1_000_000_000_000_000),
                detail: validation.detail
            )
        } catch is CancellationError {
            debugLogStatic("probe cancelled: \(endpoint.urlString)")
            return EndpointProbeResult(
                endpointID: endpoint.id,
                displayName: endpoint.displayName,
                urlString: endpoint.urlString,
                role: endpoint.role,
                isVPNRestricted: endpoint.isVPNRestricted,
                checkedAt: .now,
                outcome: .cancelled,
                latencyMilliseconds: nil,
                detail: "Проверка отменена"
            )
        } catch {
            debugLogStatic("probe failed: \(endpoint.urlString) \(error.localizedDescription)")
            return EndpointProbeResult(
                endpointID: endpoint.id,
                displayName: endpoint.displayName,
                urlString: endpoint.urlString,
                role: endpoint.role,
                isVPNRestricted: endpoint.isVPNRestricted,
                checkedAt: .now,
                outcome: .unreachable,
                latencyMilliseconds: nil,
                detail: error.localizedDescription
            )
        }
    }

    private static func performProbeRequest(with session: URLSession, url: URL) async throws -> HTTPURLResponse {
        let methods: [(String, String?)] = [
            ("HEAD", nil),
            ("GET", "bytes=0-0"),
        ]

        var lastError: Error?

        for (method, range) in methods {
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: Constants.probeTimeout
            )
            request.httpMethod = method

            if let range {
                request.setValue(range, forHTTPHeaderField: "Range")
            }

            do {
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    return httpResponse
                }
            } catch {
                lastError = error
            }
        }

        throw lastError ?? URLError(.badServerResponse)
    }

    private nonisolated static func primaryRestrictedEndpoint(from endpoints: [MonitoredEndpoint]) -> MonitoredEndpoint? {
        endpoints.first { endpoint in
            URL(string: endpoint.urlString)?.host?.localizedCaseInsensitiveContains("google.com") == true
        } ?? endpoints.first
    }

    private nonisolated static func validateProbeResponse(
        _ response: HTTPURLResponse,
        requestedURL: URL
    ) -> (outcome: EndpointProbeOutcome, detail: String) {
        guard (200..<400).contains(response.statusCode) else {
            return (.unreachable, "HTTP \(response.statusCode)")
        }

        guard isExpectedResponseHost(response.url, requestedURL: requestedURL) else {
            let finalHost = response.url?.host ?? "unknown"
            return (.unreachable, "Неожиданный хост ответа: \(finalHost)")
        }

        return (.reachable, "HTTP \(response.statusCode)")
    }

    private nonisolated static func isExpectedResponseHost(_ responseURL: URL?, requestedURL: URL) -> Bool {
        guard
            let requestedHost = requestedURL.host?.lowercased(),
            let responseHost = (responseURL ?? requestedURL).host?.lowercased()
        else {
            return false
        }

        if requestedHost == responseHost {
            return true
        }

        return requestedHost.hasSuffix(".\(responseHost)") || responseHost.hasSuffix(".\(requestedHost)")
    }

    private func debugLog(_ message: String, origin: CheckOrigin) {
#if DEBUG
        print("[OurPulse] \(message) origin=\(origin.rawValue)")
#endif
    }

    private static func debugLogStatic(_ message: String) {
#if DEBUG
        print("[OurPulse] \(message)")
#endif
    }

    private nonisolated static func analyze(
        results: [EndpointProbeResult],
        allEndpoints: [MonitoredEndpoint],
        isVPNActive: Bool,
        connectionKind: NetworkConnectionKind
    ) -> NetworkAnalysis {
        let allowedConfigured = allEndpoints.contains { $0.role == .allowed }
        let restrictedConfigured = allEndpoints.contains { $0.role == .restricted }
        let wifiWarning = "При подключении по Wi-Fi нельзя наверняка судить о состоянии белых списков для мобильной сети."
        let wifiActivationHint = "Если по Wi-Fi зарубежные адреса недоступны, это сильный признак активных белых списков, хотя такой сценарий в целом маловероятен."

        guard allowedConfigured, restrictedConfigured else {
            var details = [
                "Нужен хотя бы один российский и один зарубежный адрес."
            ]
            if isVPNActive {
                details.insert("На устройстве обнаружен активный VPN. Он может искажать результаты проверки.", at: 0)
            }
            if connectionKind == .wifi {
                details.append(wifiWarning)
            }
            return NetworkAnalysis(
                state: .unknown,
                headline: "Недостаточно контрольных адресов",
                summary: makeSummary(from: results),
                details: details
            )
        }

        let allowedReachable = results.contains { $0.role == .allowed && $0.outcome == .reachable }
        let coreAllowedReachable = results.contains {
            $0.role == .allowed && $0.outcome == .reachable && !$0.isVPNRestricted
        }
        let restrictedReachable = results.contains { $0.role == .restricted && $0.outcome == .reachable }
        let anyReachable = results.contains { $0.outcome == .reachable }
        let allowedFailures = results.filter { $0.role == .allowed && $0.outcome != .reachable }
        let restrictedFailures = results.filter { $0.role == .restricted && $0.outcome != .reachable }
        let vpnSensitiveFailures = allowedFailures.filter(\.isVPNRestricted)
        let vpnWarning = "На устройстве обнаружен активный VPN. Результаты проверки могут быть некорректны."

        if restrictedReachable {
            var details = [
                "Зарубежные сервера отвечают.",
                "Признаков активных белых списков сейчас нет."
            ]

            if isVPNActive {
                details.insert(vpnWarning, at: 0)
            }
            if connectionKind == .wifi {
                details.append(wifiWarning)
            }

            if !vpnSensitiveFailures.isEmpty && allowedFailures.count == vpnSensitiveFailures.count {
                details.append("Не отвечают только VPN-чувствительные российские сервисы. Скорее всего у Вас включен VPN.")
            } else if !allowedFailures.isEmpty {
                details.append("Некоторые российские сервисы недоступны, из-за возможного использования VPN.")
            } else {
                details.append("И российские, и зарубежные сервера доступны.")
            }

            return NetworkAnalysis(
                state: .whitelistOff,
                headline: "Белые списки не наблюдаются",
                summary: makeSummary(from: results),
                details: details
            )
        }

        if coreAllowedReachable && !restrictedReachable {
            var details = [
                "Российские сервера отвечают, а зарубежные нет.",
                "Это похоже на активные белые списки."
            ]

            if isVPNActive {
                details.insert(vpnWarning, at: 0)
            }
            if connectionKind == .wifi {
                details.append(wifiActivationHint)
            }

            if !vpnSensitiveFailures.isEmpty {
                details.append("VPN-чувствительные российские сервисы могут не отвечать.")
            }

            return NetworkAnalysis(
                state: .whitelistOn,
                headline: "Похоже, белые списки включены",
                summary: makeSummary(from: results),
                details: details
            )
        }

        if !anyReachable && connectionKind == .wifi {
            return NetworkAnalysis(
                state: .offline,
                headline: "По Wi-Fi нет связи",
                summary: makeSummary(from: results),
                details: [
                    wifiWarning,
                    "Сейчас не отвечает ни один сервер.",
                    "Похоже на проблему с подключением к сети или локальным роутером."
                ]
            )
        }

        if !anyReachable {
            return NetworkAnalysis(
                state: .offline,
                headline: "Не удаётся связаться ни с одним сервером",
                summary: makeSummary(from: results),
                details: [
                    "Не отвечают и российские, и зарубежные сервисы.",
                    "Это больше похоже на отсутствие интернета, общий сетевой сбой или полную блокировку соединений."
                ]
            )
        }

        var details: [String] = []

        if isVPNActive {
            details.append(vpnWarning)
        }
        if connectionKind == .wifi {
            details.append(wifiWarning)
        }

        if allowedReachable && !coreAllowedReachable && !restrictedReachable {
            details.append("Отвечают только VPN-чувствительные российские сервисы.")
            details.append("Этого недостаточно, чтобы уверенно считать белые списки включенными.")
        } else if !allowedReachable && restrictedReachable {
            details.append("Зарубежные сервисы доступны, а российские нет.")
            details.append("Это больше похоже на VPN, локальную блокировку или сбой отдельных российских ресурсов.")
        } else {
            details.append("Картина ответов смешанная и не укладывается в базовые сценарии.")
        }

        if !allowedFailures.isEmpty {
            details.append("Недоступны российские: \(allowedFailures.map(\.displayName).joined(separator: ", ")).")
        }

        if !restrictedFailures.isEmpty {
            details.append("Недоступны зарубежные: \(restrictedFailures.map(\.displayName).joined(separator: ", ")).")
        }

        return NetworkAnalysis(
            state: .degraded,
            headline: "Состояние сети неоднозначно",
            summary: makeSummary(from: results),
            details: details
        )
    }

    private nonisolated static func makeSummary(from results: [EndpointProbeResult]) -> String {
        let reachable = results.filter { $0.outcome == .reachable }.count
        let unreachable = results.filter { $0.outcome == .unreachable }.count
        let invalid = results.filter { $0.outcome == .invalidURL }.count

        return "Доступны: \(reachable), недоступны: \(unreachable), некорректны: \(invalid)."
    }

    private static func detectVPNConnection() -> Bool {
        guard
            let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
            let scoped = settings["__SCOPED__"] as? [String: Any]
        else {
            return false
        }

        let vpnPrefixes = ["ipsec", "ppp", "tap", "tun", "utun"]
        return scoped.keys.contains { key in
            let normalizedKey = key.lowercased()
            return vpnPrefixes.contains { normalizedKey.hasPrefix($0) }
        }
    }

    private func startPathMonitoring() {
        guard let pathMonitor else { return }

        pathMonitor.pathUpdateHandler = { [weak self] path in
            let nextKind = NetworkConnectionKind(path: path)
            Task { @MainActor [weak self, nextKind] in
                self?.connectionKind = nextKind
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func store<T: Encodable>(_ value: T?, key: String, to defaults: UserDefaults) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(data, forKey: key)
    }

    private static let defaultEndpoints: [MonitoredEndpoint] = [
        MonitoredEndpoint(displayName: "Яндекс", urlString: "https://ya.ru", probePath: "/robots.txt", role: .allowed, isEnabled: true, isVPNRestricted: false),
        MonitoredEndpoint(displayName: "ВК", urlString: "https://vk.ru", probePath: "/robots.txt", role: .allowed, isEnabled: true, isVPNRestricted: false),
        MonitoredEndpoint(displayName: "Госуслуги", urlString: "https://www.gosuslugi.ru", probePath: "/robots.txt", role: .allowed, isEnabled: true, isVPNRestricted: true),
        MonitoredEndpoint(displayName: "Google", urlString: "https://www.google.com", probePath: "/robots.txt", role: .restricted, isEnabled: true, isVPNRestricted: false),
        MonitoredEndpoint(displayName: "Cloudflare", urlString: "https://www.cloudflare.com", probePath: "/robots.txt", role: .restricted, isEnabled: true, isVPNRestricted: false),
        MonitoredEndpoint(displayName: "GitHub", urlString: "https://github.com", probePath: "/robots.txt", role: .restricted, isEnabled: true, isVPNRestricted: false),
    ]

    nonisolated static func analyzeStateForTesting(
        results: [EndpointProbeResult],
        allEndpoints: [MonitoredEndpoint],
        isVPNActive: Bool,
        connectionKind: NetworkConnectionKind
    ) -> NetworkState {
        analyze(
            results: results,
            allEndpoints: allEndpoints,
            isVPNActive: isVPNActive,
            connectionKind: connectionKind
        ).state
    }

    nonisolated static func probeOutcomeForTesting(
        statusCode: Int,
        requestedURL: URL,
        responseURL: URL? = nil
    ) -> EndpointProbeOutcome {
        guard let response = HTTPURLResponse(
            url: responseURL ?? requestedURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            return .unreachable
        }

        return validateProbeResponse(response, requestedURL: requestedURL).outcome
    }

    nonisolated static func stagedProbeOrderForTesting(endpoints: [MonitoredEndpoint]) -> [MonitoredEndpoint] {
        let restricted = endpoints.filter { $0.role == .restricted }
        let allowed = endpoints.filter { $0.role == .allowed }

        guard let primaryRestricted = primaryRestrictedEndpoint(from: restricted) else {
            return allowed
        }

        let secondaryRestricted = restricted.filter { $0.id != primaryRestricted.id }
        return [primaryRestricted] + secondaryRestricted + allowed
    }

    nonisolated static func shouldNotifyForTesting(
        preference: NotificationPreference,
        oldState: NetworkState,
        newState: NetworkState
    ) -> Bool {
        switch preference {
        case .none:
            false
        case .whitelistChanges:
            newState == .whitelistOn || (oldState == .whitelistOn && newState == .whitelistOff)
        case .connectionLoss:
            (oldState != .offline && newState == .offline) || (oldState == .offline && newState != .offline)
        }
    }

    func updateNotificationPreference(_ preference: NotificationPreference) {
        notificationPreference = preference
        persist()

        Task {
            if preference != .none {
                await requestNotificationPermissionIfNeeded(forcePrompt: true)
            } else {
                center.removeAllPendingNotificationRequests()
            }
        }
    }

    func updateCheckInterval(_ interval: CheckInterval) {
        guard checkInterval != interval else { return }
        checkInterval = interval
        persist()
        restartForegroundMonitoringIfNeeded()
        scheduleBackgroundRefresh()
    }

    private func restartForegroundMonitoringIfNeeded() {
        foregroundLoopTask?.cancel()
        foregroundLoopTask = nil

        guard UIApplication.shared.applicationState == .active else {
            return
        }

        startForegroundMonitoring()
    }

    private func shouldNotify(from oldState: NetworkState, to newState: NetworkState) -> Bool {
        Self.shouldNotifyForTesting(
            preference: notificationPreference,
            oldState: oldState,
            newState: newState
        )
    }

    private func notificationVariant(for oldState: NetworkState, to newState: NetworkState) -> NotificationVariant {
        switch notificationPreference {
        case .none, .whitelistChanges:
            return NotificationVariant(title: newState.notificationTitle, body: newState.notificationBody)
        case .connectionLoss:
            if newState == .offline {
                return NotificationVariant(
                    title: "Соединение пропало",
                    body: "Приложение перестало видеть доступ к сети."
                )
            }

            if oldState == .offline {
                return NotificationVariant(
                    title: "Соединение восстановлено",
                    body: "Сеть снова доступна. Текущий статус: \\(newState.title)."
                )
            }

            return NotificationVariant(title: newState.notificationTitle, body: newState.notificationBody)
        }
    }

    private func offlineDetails(isVPNActive: Bool) -> [String] {
        if isVPNActive {
            return [
                "На устройстве обнаружен активный VPN.",
                "Системный монитор сети уже сообщает об отсутствии доступного соединения.",
                "Ни один запрос не запускался, потому что сеть недоступна на системном уровне."
            ]
        }

        return [
            "Системный монитор сети сообщает, что доступного соединения сейчас нет.",
            "Поэтому приложение сразу показывает офлайн-статус без ожидания таймаутов HTTP-запросов."
        ]
    }

    private func timeoutOfflineDetails(isVPNActive: Bool) -> [String] {
        if isVPNActive {
            return [
                "На устройстве обнаружен активный VPN.",
                "Ни один контрольный сервер не ответил в течение \(Self.deadlineDescription).",
                "Для скорости приложение считает такой сценарий отсутствием доступа к сети."
            ]
        }

        return [
            "Ни один контрольный сервер не ответил в течение \(Self.deadlineDescription).",
            "Для скорости приложение завершило проверку и показало офлайн-статус."
        ]
    }

    private static var deadlineDescription: String {
        "5 секунд"
    }
}

extension NetworkMonitor {
    enum CheckOrigin {
        case startup
        case sceneActivation
        case manual
        case foregroundLoop
        case background

        var rawValue: String {
            switch self {
            case .startup:
                "startup"
            case .sceneActivation:
                "scene-activation"
            case .manual:
                "manual"
            case .foregroundLoop:
                "foreground"
            case .background:
                "background"
            }
        }
    }
}

enum EndpointRole: String, Codable, CaseIterable, Identifiable {
    case allowed
    case restricted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allowed:
            "Российский адрес"
        case .restricted:
            "Зарубежный адрес"
        }
    }

    var badgeTitle: String {
        switch self {
        case .allowed:
            "Белый список"
        case .restricted:
            "Вне белого списка"
        }
    }
}

extension UIBackgroundRefreshStatus {
    var debugLabel: String {
        switch self {
        case .available:
            return "available"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }
}

enum EndpointProbeOutcome: String, Codable {
    case reachable
    case unreachable
    case invalidURL
    case cancelled
}

enum NotificationPreference: String, Codable, CaseIterable, Identifiable {
    case none
    case whitelistChanges
    case connectionLoss

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "Не получать"
        case .whitelistChanges:
            "Белые списки"
        case .connectionLoss:
            "Потеря сети"
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            "Уведомления полностью отключены."
        case .whitelistChanges:
            "Только о включении и выключении белых списков."
        case .connectionLoss:
            "Когда соединение пропадает и когда оно снова появляется."
        }
    }

    var symbol: String {
        switch self {
        case .none:
            "bell.slash"
        case .whitelistChanges:
            "bell.badge"
        case .connectionLoss:
            "wifi.exclamationmark"
        }
    }
}

enum CheckInterval: String, Codable, CaseIterable, Identifiable {
    case tenMinutes
    case twentyMinutes
    case thirtyMinutes
    case oneHour

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tenMinutes:
            "10 минут"
        case .twentyMinutes:
            "20 минут"
        case .thirtyMinutes:
            "30 минут"
        case .oneHour:
            "1 час"
        }
    }

    var subtitle: String {
        switch self {
        case .tenMinutes:
            "Чаще проверяет состояние сети."
        case .twentyMinutes:
            "Баланс между частотой и расходом."
        case .thirtyMinutes:
            "Стандартный умеренный режим."
        case .oneHour:
            "Минимум фоновой активности."
        }
    }

    var duration: Duration {
        .seconds(timeInterval)
    }

    var timeInterval: TimeInterval {
        switch self {
        case .tenMinutes:
            10 * 60
        case .twentyMinutes:
            20 * 60
        case .thirtyMinutes:
            30 * 60
        case .oneHour:
            60 * 60
        }
    }
}

enum NetworkConnectionKind: String, Codable {
    case wifi
    case cellular
    case wired
    case other
    case offline
    case unknown

    nonisolated init(path: NWPath) {
        if path.status != .satisfied {
            self = .offline
        } else if path.usesInterfaceType(.wifi) {
            self = .wifi
        } else if path.usesInterfaceType(.cellular) {
            self = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            self = .wired
        } else if path.usesInterfaceType(.other) {
            self = .other
        } else {
            self = .unknown
        }
    }
}

extension NetworkConnectionKind {
    var title: String {
        switch self {
        case .wifi:
            "Wi-Fi"
        case .cellular:
            "Сотовая сеть"
        case .wired:
            "Проводная сеть"
        case .other:
            "Другое подключение"
        case .offline:
            "Нет сети"
        case .unknown:
            "Не определено"
        }
    }

    var symbolName: String {
        switch self {
        case .wifi:
            "wifi"
        case .cellular:
            "antenna.radiowaves.left.and.right"
        case .wired:
            "cable.connector"
        case .other:
            "network"
        case .offline:
            "wifi.slash"
        case .unknown:
            "questionmark.circle"
        }
    }
}

enum NetworkState: String, Codable {
    case whitelistOn
    case whitelistOff
    case offline
    case degraded
    case unknown

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        switch rawValue {
        case "whitelistOn":
            self = .whitelistOn
        case "whitelistOff":
            self = .whitelistOff
        case "offline", "vpnVerificationBlocked":
            self = .offline
        case "degraded":
            self = .degraded
        case "unknown":
            self = .unknown
        default:
            self = .unknown
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var title: String {
        switch self {
        case .whitelistOn:
            "Белые списки включены"
        case .whitelistOff:
            "Белые списки выключены"
        case .offline:
            "Нет доступа к сети"
        case .degraded:
            "Сеть в деградированном состоянии"
        case .unknown:
            "Недостаточно данных"
        }
    }

    var description: String {
        switch self {
        case .whitelistOn:
            "Адреса из белого списка отвечают, остальные нет."
        case .whitelistOff:
            "Связь со всеми серверами в норме."
        case .offline:
            "Ни один из адресов сейчас не отвечает."
        case .degraded:
            "Есть частичная связность, но картина не укладывается в ожидаемый паттерн."
        case .unknown:
            "Для уверенного вывода нужен минимум один адрес каждой категории."
        }
    }

    var symbol: String {
        switch self {
        case .whitelistOn:
            "lock.shield.fill"
        case .whitelistOff:
            "globe.badge.chevron.backward"
        case .offline:
            "wifi.slash"
        case .degraded:
            "exclamationmark.triangle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .whitelistOn:
            .orange
        case .whitelistOff:
            .green
        case .offline:
            .red
        case .degraded:
            .yellow
        case .unknown:
            .secondary
        }
    }

    var notificationTitle: String {
        notificationVariant.title
    }

    var notificationBody: String {
        notificationVariant.body
    }

    private var notificationVariant: NotificationVariant {
        switch self {
        case .whitelistOn:
            Self.whitelistOnVariants.randomElement() ?? NotificationVariant(
                title: "🔒 Белые списки включились",
                body: "🌍 Зарубежные сервера перестали отвечать, российские доступны."
            )
        case .whitelistOff:
            Self.whitelistOffVariants.randomElement() ?? NotificationVariant(
                title: "🌍 Белые списки отключились",
                body: "✨ Зарубежные сервера снова доступны."
            )
        case .offline, .degraded, .unknown:
            NotificationVariant(title: title, body: description)
        }
    }

    private static let whitelistOnVariants: [NotificationVariant] = [
        NotificationVariant(title: "🔒 Белые списки включились", body: "🌍 Зарубежные сервера перестали отвечать, российские доступны."),
        NotificationVariant(title: "⚠️ Похоже, рубильник щелкнул", body: "🚧 Внешние сервисы недоступны, белые списки в деле."),
        NotificationVariant(title: "🏠 Интернет стал локальнее", body: "📡 Признаки указывают на активацию белых списков."),
        NotificationVariant(title: "🚪 Границу закрыли", body: "🪪 Похоже, интернет теперь по пропускам"),
        NotificationVariant(title: "⛔️ Шлагбаум опустился", body: "🙃 Сегодня никого не выпускают"),
        NotificationVariant(title: "🛋️ Интернет на домашнем режиме", body: "🌫️ Снаружи тишина"),
        NotificationVariant(title: "🧑‍✈️ Сеть включила режим вахтера", body: "🚷 Пускают в основном своих, остальные остались у двери"),
        NotificationVariant(title: "👃 Пахнет белыми списками", body: "🛰️ Иностранные сервера пропали с радаров."),
    ]

    private static let whitelistOffVariants: [NotificationVariant] = [
        NotificationVariant(title: "🌍 Белые списки отключились", body: "✨ Зарубежные адреса снова доступны."),
        NotificationVariant(title: "✅ Шлагбаум открыт", body: "🌐 И российские, и зарубежные сервисы сейчас в сети."),
        NotificationVariant(title: "📬 Мир снова на связи", body: "🎉 Признаков активных белых списков больше нет."),
        NotificationVariant(title: "🌬️ Воздух свободы в сети", body: "📱 Внешние адреса снова отзываются, наконец, можно снова зайти в тикток."),
        NotificationVariant(title: "😮‍💨 Интернет выдохнул", body: "🙂 И мы тоже."),
        NotificationVariant(title: "🔁 Рубильник отщелкнули обратно", body: "🌐 Снаружи снова кто-то есть, и это хорошая новость."),
        NotificationVariant(title: "😜 Интернет вернулся", body: "🖥️ Хотели бы мы глянуть Нетфликс.."),
    ]
}

private struct NotificationVariant {
    let title: String
    let body: String
}

private struct NetworkAnalysis {
    let state: NetworkState
    let headline: String
    let summary: String
    let details: [String]
}

struct MonitoredEndpoint: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var displayName: String
    var urlString: String
    var probePath: String?
    var role: EndpointRole
    var isEnabled: Bool
    var isVPNRestricted: Bool

    var probeURL: URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        if let probePath, !probePath.isEmpty {
            if probePath.hasPrefix("/") {
                components.path = probePath
            } else {
                components.path = "/" + probePath
            }
            components.query = nil
            components.fragment = nil
        }
        return components.url
    }
}

struct EndpointProbeResult: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var endpointID: UUID
    var displayName: String
    var urlString: String
    var role: EndpointRole
    var isVPNRestricted: Bool
    var checkedAt: Date
    var outcome: EndpointProbeOutcome
    var latencyMilliseconds: Int?
    var detail: String

    var isReachable: Bool {
        outcome == .reachable
    }
}

struct NetworkSnapshot: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var checkedAt: Date
    var state: NetworkState
    var results: [EndpointProbeResult]
    var summary: String
    var headline: String
    var details: [String]
    var connectionKind: NetworkConnectionKind
    var isVPNActive: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case checkedAt
        case state
        case results
        case summary
        case headline
        case details
        case connectionKind
        case isVPNActive
    }

    init(
        id: UUID = UUID(),
        checkedAt: Date,
        state: NetworkState,
        results: [EndpointProbeResult],
        summary: String,
        headline: String,
        details: [String],
        connectionKind: NetworkConnectionKind,
        isVPNActive: Bool
    ) {
        self.id = id
        self.checkedAt = checkedAt
        self.state = state
        self.results = results
        self.summary = summary
        self.headline = headline
        self.details = details
        self.connectionKind = connectionKind
        self.isVPNActive = isVPNActive
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
        state = try container.decode(NetworkState.self, forKey: .state)
        results = try container.decode([EndpointProbeResult].self, forKey: .results)
        summary = try container.decode(String.self, forKey: .summary)
        headline = try container.decode(String.self, forKey: .headline)
        details = try container.decode([String].self, forKey: .details)
        connectionKind = try container.decodeIfPresent(NetworkConnectionKind.self, forKey: .connectionKind) ?? .unknown
        isVPNActive = try container.decodeIfPresent(Bool.self, forKey: .isVPNActive) ?? false
    }

    static let preview = NetworkSnapshot(
        checkedAt: .now,
        state: .whitelistOn,
        results: [],
        summary: "Доступны: 3, недоступны: 3, некорректны: 0.",
        headline: "Похоже, белые списки включены",
        details: [
            "Базовые российские адреса отвечают, а зарубежные нет.",
            "Это похоже на включение белых списков."
        ],
        connectionKind: .wifi,
        isVPNActive: false
    )
}
