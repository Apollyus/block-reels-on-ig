import SwiftUI
import WebKit

struct ContentView: View {
    @ObservedObject private var browser = BrowserController.shared

    var body: some View {
        ZStack(alignment: .top) {
            InstaWebView(controller: browser)
                .ignoresSafeArea(edges: .bottom)

            if let warning = browser.warning {
                Button {
                    browser.warning = nil
                } label: {
                    Text(warning)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
    }
}

struct InstaWebView: UIViewRepresentable {
    let controller: BrowserController

    func makeUIView(context: Context) -> WKWebView {
        controller.startIfNeeded()
        return controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
