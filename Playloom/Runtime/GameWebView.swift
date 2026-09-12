import SwiftUI
import WebKit

struct GameWebView: UIViewRepresentable {
    let session: GameRuntimeSession

    func makeUIView(context: Context) -> WKWebView {
        session.makeWebView()
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
