import Foundation
import Testing
@testable import Our_pulse

struct Our_pulseTests {
    private let endpoints = [
        MonitoredEndpoint(displayName: "Allowed", urlString: "https://allowed.example", probePath: nil, role: .allowed, isEnabled: true, isVPNRestricted: false),
        MonitoredEndpoint(displayName: "Restricted", urlString: "https://restricted.example", probePath: nil, role: .restricted, isEnabled: true, isVPNRestricted: false),
    ]

    @Test func stagedProbeOrderStartsWithGoogleThenOtherForeignThenRussian() async throws {
        let stagedOrder = NetworkMonitor.stagedProbeOrderForTesting(endpoints: [
            MonitoredEndpoint(displayName: "Yandex", urlString: "https://ya.ru", probePath: nil, role: .allowed, isEnabled: true, isVPNRestricted: false),
            MonitoredEndpoint(displayName: "Cloudflare", urlString: "https://www.cloudflare.com", probePath: nil, role: .restricted, isEnabled: true, isVPNRestricted: false),
            MonitoredEndpoint(displayName: "Google", urlString: "https://www.google.com", probePath: nil, role: .restricted, isEnabled: true, isVPNRestricted: false),
            MonitoredEndpoint(displayName: "VK", urlString: "https://vk.ru", probePath: nil, role: .allowed, isEnabled: true, isVPNRestricted: false),
            MonitoredEndpoint(displayName: "GitHub", urlString: "https://github.com", probePath: nil, role: .restricted, isEnabled: true, isVPNRestricted: false),
        ])

        #expect(stagedOrder.map(\.displayName) == ["Google", "Cloudflare", "GitHub", "Yandex", "VK"])
    }

    @Test func stagedProbeOrderFallsBackToFirstForeignEndpointWhenGoogleMissing() async throws {
        let stagedOrder = NetworkMonitor.stagedProbeOrderForTesting(endpoints: [
            MonitoredEndpoint(displayName: "Cloudflare", urlString: "https://www.cloudflare.com", probePath: nil, role: .restricted, isEnabled: true, isVPNRestricted: false),
            MonitoredEndpoint(displayName: "Yandex", urlString: "https://ya.ru", probePath: nil, role: .allowed, isEnabled: true, isVPNRestricted: false),
            MonitoredEndpoint(displayName: "GitHub", urlString: "https://github.com", probePath: nil, role: .restricted, isEnabled: true, isVPNRestricted: false),
        ])

        #expect(stagedOrder.map(\.displayName) == ["Cloudflare", "GitHub", "Yandex"])
    }

    @Test func offlineOnWiFiDoesNotBecomeWhitelistOn() async throws {
        let state = NetworkMonitor.analyzeStateForTesting(
            results: [
                unreachableResult(name: "Allowed", url: "https://allowed.example", role: .allowed),
                unreachableResult(name: "Restricted", url: "https://restricted.example", role: .restricted),
            ],
            allEndpoints: endpoints,
            isVPNActive: false,
            connectionKind: .wifi
        )

        #expect(state == .offline)
    }

    @Test func offlineWithVPNBecomesVPNIndeterminateState() async throws {
        let state = NetworkMonitor.analyzeStateForTesting(
            results: [
                unreachableResult(name: "Allowed", url: "https://allowed.example", role: .allowed),
                unreachableResult(name: "Restricted", url: "https://restricted.example", role: .restricted),
            ],
            allEndpoints: endpoints,
            isVPNActive: true,
            connectionKind: .cellular
        )

        #expect(state == .vpnVerificationBlocked)
    }

    @Test func whitelistOnRequiresRestrictedFailuresButAllowedReachability() async throws {
        let state = NetworkMonitor.analyzeStateForTesting(
            results: [
                reachableResult(name: "Allowed", url: "https://allowed.example", role: .allowed),
                unreachableResult(name: "Restricted", url: "https://restricted.example", role: .restricted),
            ],
            allEndpoints: endpoints,
            isVPNActive: false,
            connectionKind: .cellular
        )

        #expect(state == .whitelistOn)
    }

    @Test func unexpectedRedirectHostIsNotReachable() async throws {
        let outcome = NetworkMonitor.probeOutcomeForTesting(
            statusCode: 200,
            requestedURL: URL(string: "https://www.google.com/robots.txt")!,
            responseURL: URL(string: "https://captive.portal.example/login")!
        )

        #expect(outcome == .unreachable)
    }

    @Test func successfulResponseOnExpectedHostIsReachable() async throws {
        let outcome = NetworkMonitor.probeOutcomeForTesting(
            statusCode: 200,
            requestedURL: URL(string: "https://github.com/robots.txt")!,
            responseURL: URL(string: "https://github.com/robots.txt")!
        )

        #expect(outcome == .reachable)
    }

    private func reachableResult(name: String, url: String, role: EndpointRole) -> EndpointProbeResult {
        EndpointProbeResult(
            endpointID: UUID(),
            displayName: name,
            urlString: url,
            role: role,
            isVPNRestricted: false,
            checkedAt: .now,
            outcome: .reachable,
            latencyMilliseconds: 120,
            detail: "HTTP 200"
        )
    }

    private func unreachableResult(name: String, url: String, role: EndpointRole) -> EndpointProbeResult {
        EndpointProbeResult(
            endpointID: UUID(),
            displayName: name,
            urlString: url,
            role: role,
            isVPNRestricted: false,
            checkedAt: .now,
            outcome: .unreachable,
            latencyMilliseconds: nil,
            detail: "Timed out"
        )
    }
}
