import Foundation

public enum URLDecision: Equatable {
    case allow
    case redirectHome
    case openInSafari
    /// SPA už přešla na nový Reel (swipe) – vrátit se na předchozí URL.
    case blockAndGoBack
}

/// Rozhodnutí, kam smí aplikace přejít. Drží jediný stav: id Reelu, který uživatel otevřel.
public struct URLPolicy {
    public let config: FilterConfig
    public private(set) var allowedReelId: String?

    public init(config: FilterConfig) {
        self.config = config
    }

    public func isAllowedHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return config.allowedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// - Parameters:
    ///   - from: aktuální URL (nil při prvním načtení / otevření zvenku).
    ///   - userInitiated: navigace vznikla kliknutím/klepnutím, ne swipem nebo skriptem.
    public mutating func decide(from: URL?, to: URL, userInitiated: Bool) -> URLDecision {
        guard let scheme = to.scheme?.lowercased() else { return .openInSafari }
        if scheme == "about" { return .allow }
        guard scheme == "http" || scheme == "https", isAllowedHost(to.host) else {
            return .openInSafari
        }

        let comps = Self.components(of: to)
        let fromComps: [String] = {
            guard let from, isAllowedHost(from.host) else { return [] }
            return Self.components(of: from)
        }()
        let fromIsDirect = fromComps.first == "direct"
        let fromContentId: String? = {
            if case .content(let id, _) = Self.classify(fromComps) { return id }
            return nil
        }()

        switch Self.classify(comps) {
        case .content(let id, let viaReelsPath):
            // /reels/<id> je u Instagramu feed začínající daným Reelem: povolit jen ze zprávy
            // nebo z už otevřeného Reelu, odjinud ho brát jako feed.
            if viaReelsPath && !(fromIsDirect || fromContentId != nil) {
                return .redirectHome
            }
            // Swipe na další Reel: URL se změní bez kliknutí.
            if let current = allowedReelId, let fromId = fromContentId,
               fromId == current, id != current, !userInitiated {
                return .blockAndGoBack
            }
            allowedReelId = id
            return .allow

        case .other:
            let path = "/" + comps.joined(separator: "/")
            if Self.matches(path, anyOf: config.allowedPrefixes) {
                allowedReelId = nil
                return .allow
            }
            if Self.matches(path, anyOf: config.blockedPrefixes) {
                return .redirectHome
            }
            // Záložka Reels na profilu: /<uživatel>/reels/
            if comps.count == 2, comps[1] == "reels" {
                return .redirectHome
            }
            allowedReelId = nil
            return .allow
        }
    }

    // MARK: Klasifikace cest

    enum PathKind: Equatable {
        case content(id: String, viaReelsPath: Bool)
        case other
    }

    static func components(of url: URL) -> [String] {
        url.path.split(separator: "/").map(String.init)
    }

    private static let contentSegments: Set<String> = ["reel", "p", "tv"]

    /// `/reel/<id>`, `/p/<id>`, `/tv/<id>`, `/<uživatel>/reel/<id>`, `/<uživatel>/p/<id>`, `/reels/<id>`.
    static func classify(_ comps: [String]) -> PathKind {
        if comps.count == 2, contentSegments.contains(comps[0]) {
            return .content(id: comps[1], viaReelsPath: false)
        }
        if comps.count == 2, comps[0] == "reels" {
            return .content(id: comps[1], viaReelsPath: true)
        }
        if comps.count == 3, contentSegments.contains(comps[1]) {
            return .content(id: comps[2], viaReelsPath: false)
        }
        return .other
    }

    static func matches(_ path: String, anyOf prefixes: [String]) -> Bool {
        prefixes.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}
