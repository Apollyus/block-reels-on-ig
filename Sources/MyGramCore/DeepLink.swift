import Foundation

/// `mygram://open` -> DM, `mygram://open?path=/direct/inbox/` -> povolená cesta.
public enum DeepLink {
    public static func resolve(_ url: URL, config: FilterConfig) -> URL? {
        guard url.scheme?.lowercased() == "mygram", url.host?.lowercased() == "open" else { return nil }

        var path = config.inboxPath
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let requested = items.first(where: { $0.name == "path" })?.value {
            path = requested
        }
        // Jen cesty uvnitř Instagramu, nikdy "//jinyhost" ani schéma.
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("\\"),
              let target = URL(string: "https://www.instagram.com" + path),
              target.host == "www.instagram.com"
        else { return nil }

        var policy = URLPolicy(config: config)
        return policy.decide(from: nil, to: target, userInitiated: true) == .allow ? target : nil
    }
}
