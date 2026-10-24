import Foundation

/// Z `FilterConfig` generuje všechny tři vrstvy filtrování.
public enum FilterBuilder {
    /// Atribut na `<html>`, který nastavuje `filters.js` na stránkách jednoho příspěvku/Reelu.
    public static let contentPageAttribute = "data-mygram-content"

    // MARK: Vrstva 2: CSS

    public static func css(_ config: FilterConfig, enabledOptional: Set<String> = []) -> String {
        var rules = ["[data-mygram-hidden]{display:none!important}"]
        for entry in config.entries(enabledOptional: enabledOptional) {
            var selector: String
            if let ancestor = entry.ancestor {
                selector = ":is(\(ancestor)):has(\(entry.selector))"
            } else {
                selector = entry.selector
            }
            if entry.skipOnContentPages == true {
                selector = "html:not([\(contentPageAttribute)]) \(selector)"
            }
            rules.append("\(selector){display:none!important}")
        }
        return rules.joined(separator: "\n")
    }

    /// JS, který CSS vloží jako `<style>` už při `.atDocumentStart`.
    public static func cssInjectionScript(_ css: String) -> String {
        "(function(){var s=document.createElement('style');s.textContent=\(jsonString(css));"
            + "(document.head||document.documentElement).appendChild(s);})();"
    }

    // MARK: Vrstva 1: WKContentRuleList

    /// JSON pro `WKContentRuleListStore`. Obsahuje jen jednoduché selektory (bez `:has`).
    /// Vrací `nil`, když nemá co skrývat (prázdný seznam pravidel WebKit odmítne).
    public static func contentRuleListJSON(_ config: FilterConfig, enabledOptional: Set<String> = []) -> String? {
        var seen = Set<String>()
        let selectors = config.entries(enabledOptional: enabledOptional)
            .filter(\.isSimple)
            .map(\.selector)
            .filter { seen.insert($0).inserted }
        guard !selectors.isEmpty else { return nil }

        let rules: [[String: Any]] = [[
            "trigger": ["url-filter": ".*", "if-domain": ["*instagram.com"]],
            "action": ["type": "css-display-none", "selector": selectors.joined(separator: ", ")],
        ]]
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Vrstva 3: JS

    /// `window.__mygramConfig = {...};` + tělo `filters.js`.
    public static func userScript(
        _ config: FilterConfig, enabledOptional: Set<String> = [], scriptBody: String
    ) -> String {
        struct ScriptConfig: Encodable {
            let hide: [HideEntry]
            let suggestedTexts: [String]
            let health: [HealthCheck]
        }
        let payload = ScriptConfig(
            hide: config.entries(enabledOptional: enabledOptional),
            suggestedTexts: config.suggestedTexts,
            health: config.health
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let json = (try? encoder.encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "window.__mygramConfig = \(json);\n\(scriptBody)"
    }

    // MARK: Pomocné

    static func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
              let array = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        // ["..."] -> "..."
        return String(array.dropFirst().dropLast())
    }
}
