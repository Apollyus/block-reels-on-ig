import SwiftUI

@main
struct MyGramApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { BrowserController.shared.handle(url: $0) }
        }
    }
}
