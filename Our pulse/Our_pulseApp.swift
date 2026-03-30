import BackgroundTasks
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        #if DEBUG
        print("[OurPulse] didFinishLaunching register start")
        #endif
        BGTaskScheduler.shared.register(forTaskWithIdentifier: NetworkMonitor.Constants.backgroundTaskIdentifier, using: nil) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            NetworkMonitor.shared.handleBackgroundRefresh(task: task)
        }
        #if DEBUG
        print("[OurPulse] didFinishLaunching register done")
        #endif

        NetworkMonitor.shared.scheduleBackgroundRefresh()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

@main
struct Our_pulseApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var monitor = NetworkMonitor.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(monitor)
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            monitor.handleScenePhase(newPhase)
        }
    }
}
