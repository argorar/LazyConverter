//
//  YouTubePreviewSheet.swift
//  LazyConverter
//

import SwiftUI
import WebKit

struct YouTubePreviewSheet: View {
    let url: URL
    let title: String
    let closeTitle: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(closeTitle, action: close)
            }

            YouTubeWebView(url: url)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 500)
    }
}

private struct YouTubeWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        loadPreview(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard webView.url != url else { return }
        loadPreview(in: webView)
    }

    private func loadPreview(in webView: WKWebView) {
        var request = URLRequest(url: url)
        let appID = (Bundle.main.bundleIdentifier ?? "com.argorar.LazyConverter").lowercased()
        request.setValue("https://\(appID)", forHTTPHeaderField: "Referer")
        webView.load(request)
    }
}
