import Foundation

/// Výsledek `window.__mygramHealth()` z `filters.js`.
public struct HealthReport: Codable, Equatable {
    public let loggedIn: Bool
    public let path: String
    /// Počet prvků nalezených každým kotevním selektorem; -1 = selektor je neplatný.
    public let counts: [String: Int]

    public init(loggedIn: Bool, path: String, counts: [String: Int]) {
        self.loggedIn = loggedIn
        self.path = path
        self.counts = counts
    }
}

public enum FilterHealth {
    /// Jména kontrol, které na přihlášené domovské stránce nic nenašly.
    /// Prázdné pole = vše v pořádku (nebo nejde posoudit).
    public static func problems(in report: HealthReport) -> [String] {
        guard report.loggedIn, report.path == "/" else { return [] }
        return report.counts.filter { $0.value <= 0 }.map(\.key).sorted()
    }

    public static func problems(fromJSON json: String) -> [String] {
        guard let report = try? JSONDecoder().decode(HealthReport.self, from: Data(json.utf8)) else {
            return []
        }
        return problems(in: report)
    }
}
