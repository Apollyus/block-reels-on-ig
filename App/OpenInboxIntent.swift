import AppIntents

struct OpenInboxIntent: AppIntent {
    static var title: LocalizedStringResource = "Otevřít zprávy v MyGram"
    static var description = IntentDescription("Otevře seznam konverzací (DM).")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        BrowserController.shared.openInbox()
        return .result()
    }
}

struct MyGramShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenInboxIntent(),
            phrases: ["Otevři zprávy v \(.applicationName)", "Open messages in \(.applicationName)"],
            shortTitle: "Zprávy",
            systemImageName: "paperplane")
    }
}
