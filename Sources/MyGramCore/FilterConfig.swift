import Foundation

/// Jedna položka ke skrytí. Bez `ancestor` se skryje samotný prvek, s ním nejbližší
/// předek odpovídající `ancestor`, který prvek obsahuje.
public struct HideEntry: Codable, Equatable {
    public let selector: String
    public let ancestor: String?
    /// Na stránce jednoho příspěvku/Reelu se pravidlo neuplatní (jinak by zmizel otevřený Reel).
    public let skipOnContentPages: Bool?

    public init(selector: String, ancestor: String? = nil, skipOnContentPages: Bool? = nil) {
        self.selector = selector
        self.ancestor = ancestor
        self.skipOnContentPages = skipOnContentPages
    }

    /// Jednoduchý selektor smí do `WKContentRuleList`; `:has()` a předky řeší jen CSS a JS vrstva.
    public var isSimple: Bool {
        ancestor == nil && !selector.contains(":has(")
    }
}

public struct FilterGroup: Codable, Equatable {
    public let name: String
    public let optional: Bool?
    public let hide: [HideEntry]

    public var isOptional: Bool { optional ?? false }
}

public struct HealthCheck: Codable, Equatable {
    public let name: String
    public let selector: String
}

/// Obsah `filters.json`: jediný zdroj pravdy pro CSS, JS i `WKContentRuleList` i URL pravidla.
public struct FilterConfig: Codable, Equatable {
    public let version: Int
    public let allowedHosts: [String]
    public let homePath: String
    public let inboxPath: String
    public let blockedPrefixes: [String]
    public let allowedPrefixes: [String]
    public let suggestedTexts: [String]
    public let groups: [FilterGroup]
    public let health: [HealthCheck]

    public static func decode(from data: Data) throws -> FilterConfig {
        try JSONDecoder().decode(FilterConfig.self, from: data)
    }

    /// Položky všech povinných skupin + zapnutých volitelných (podle jména skupiny).
    public func entries(enabledOptional: Set<String> = []) -> [HideEntry] {
        groups
            .filter { !$0.isOptional || enabledOptional.contains($0.name) }
            .flatMap(\.hide)
    }
}

public enum FilterResources {
    public enum LoadError: Error { case missing(String) }

    public static func configData() throws -> Data {
        try data(named: "filters", ext: "json")
    }

    public static func scriptSource() throws -> String {
        String(decoding: try data(named: "filters", ext: "js"), as: UTF8.self)
    }

    public static func loadConfig() throws -> FilterConfig {
        try FilterConfig.decode(from: configData())
    }

    private static func data(named name: String, ext: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext) else {
            throw LoadError.missing("\(name).\(ext)")
        }
        return try Data(contentsOf: url)
    }
}
