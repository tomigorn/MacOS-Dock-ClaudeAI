//
//  ContentView.swift
//  MacOS-Dock-ClaudeAI
//
//  Created by Tomas Milata on 07.05.2026.
//

import SwiftUI
import WebKit
import AppKit

// MARK: - Usage Scraping
// Update these selectors if claude.ai's DOM changes
let usageJS = """
(function() {
    var bars = document.querySelectorAll('[role="progressbar"]');
    var results = {};
    bars.forEach(function(bar, i) {
        var val = Number(bar.getAttribute('aria-valuenow'));
        var parent = bar.parentElement?.parentElement?.parentElement;
        if (!parent) return;
        var spans = Array.from(parent.querySelectorAll('span'));
        var texts = spans.map(function(s) { return s.innerText.trim(); });
        if (texts.indexOf('Current session') !== -1) {
            results.session = val;
            var reset = texts.find(function(t) { return t.startsWith('Resets in'); });
            if (reset) results.sessionReset = reset;
        }
        if (texts.indexOf('All models') !== -1) {
            results.weekly = val;
            var reset = texts.find(function(t) { return t.startsWith('Resets '); });
            if (reset) results.weeklyReset = reset;
        }
    });
    return JSON.stringify(results);
})()
"""

// MARK: - Session Store

class SessionStore {
    static let shared = SessionStore()
    var cookies: [HTTPCookie] = []
    var sessionUsage: Int?
    var weeklyUsage: Int?
    var sessionResetText: String?
    var weeklyResetText: String?
}

// MARK: - Dock Icon Renderer

func updateDockIcon(session: Int? = nil, weekly: Int? = nil) {
    let size = NSSize(width: 128, height: 128)
    let image = NSImage(size: size, flipped: false) { rect in
        let bgPath = NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: 24, yRadius: 24)
        NSColor(white: 0.15, alpha: 1.0).setFill()
        bgPath.fill()

        let bigFont = NSFont.boldSystemFont(ofSize: 38)
        let smallFont = NSFont.boldSystemFont(ofSize: 32)
        let textColor = NSColor.white
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let bigAttrs: [NSAttributedString.Key: Any] = [
            .font: bigFont, .foregroundColor: textColor, .paragraphStyle: paragraphStyle
        ]
        let smallAttrs: [NSAttributedString.Key: Any] = [
            .font: smallFont, .foregroundColor: textColor, .paragraphStyle: paragraphStyle
        ]

        let line1 = session.map { "\($0)%" } ?? "—"
        let line1Size = (line1 as NSString).size(withAttributes: bigAttrs)
        let line1Rect = NSRect(x: 0, y: rect.midY + 2, width: rect.width, height: line1Size.height)
        (line1 as NSString).draw(in: line1Rect, withAttributes: bigAttrs)

        let line2 = weekly.map { "\($0)%" } ?? "—"
        let line2Size = (line2 as NSString).size(withAttributes: smallAttrs)
        let line2Rect = NSRect(x: 0, y: rect.midY - line2Size.height + 2, width: rect.width, height: line2Size.height)
        (line2 as NSString).draw(in: line2Rect, withAttributes: smallAttrs)

        return true
    }
    NSApplication.shared.applicationIconImage = image
}

// MARK: - Usage Scraper (hidden WKWebView)

class UsageScraper: NSObject, WKNavigationDelegate {
    static let shared = UsageScraper()

    private var hiddenWebView: WKWebView!
    private var refreshTimer: Timer?
    private var isScraping = false
    private var hasSucceeded = false
    weak var loginWebView: WKWebView?

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        hiddenWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        hiddenWebView.navigationDelegate = self
    }

    private var retryTimer: Timer?

    func startPeriodicFetch() {
        fetchUsage()
        // Retry every 10 seconds until first success
        retryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.hasSucceeded {
                timer.invalidate()
                self.retryTimer = nil
                // Switch to 15-minute refresh
                self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
                    self?.fetchUsage()
                }
            } else {
                self.fetchUsage()
            }
        }
    }

    func fetchUsage() {
        guard !isScraping else { return }
        isScraping = true
        print("🔄 Fetching usage data...")
        hiddenWebView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        // If redirected to login, we're not authenticated yet
        if url.path.contains("login") {
            print("⚠️ Not logged in yet — waiting for user to log in via window")
            isScraping = false
            return
        }
        guard url.absoluteString.contains("settings/usage") else { return }

        // Wait for the SPA to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            webView.evaluateJavaScript(usageJS) { result, error in
                defer { self?.isScraping = false }

                if let error = error {
                    print("❌ JS error: \(error)")
                    return
                }
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("❌ Failed to parse usage JSON")
                    return
                }

                guard let session = json["session"] as? Int,
                      let weekly = json["weekly"] as? Int else {
                    print("⚠️ Usage values not found in DOM — page may not have rendered yet")
                    return
                }

                SessionStore.shared.sessionUsage = session
                SessionStore.shared.weeklyUsage = weekly
                SessionStore.shared.sessionResetText = json["sessionReset"] as? String
                SessionStore.shared.weeklyResetText = json["weeklyReset"] as? String

                print("=== Usage Data ===")
                print("Current session: \(session)%")
                print("Weekly (all models): \(weekly)%")
                print("==================")

                updateDockIcon(session: session, weekly: weekly)

                // Close the login window after first successful fetch
                if let self = self, !self.hasSucceeded {
                    self.hasSucceeded = true
                    self.loginWebView?.window?.close()
                    self.loginWebView = nil
                }
            }
        }
    }
}

// MARK: - Login WebView Coordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    var registered = false

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host?.contains("claude.ai") == true else { return }

        if !registered {
            registered = true
            // Tell the scraper which window to close after first successful fetch
            UsageScraper.shared.loginWebView = webView
        }
    }
}

// MARK: - WebView

struct WebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - ContentView

struct ContentView: View {
    var body: some View {
        WebView(url: URL(string: "https://claude.ai")!)
            .frame(minWidth: 800, minHeight: 600)
    }
}
