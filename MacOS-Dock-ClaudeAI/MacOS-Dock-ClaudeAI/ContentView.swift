//
//  ContentView.swift
//  MacOS-Dock-ClaudeAI
//
//  Created by Tomas Milata on 07.05.2026.
//

import SwiftUI
import WebKit
import AppKit
import UserNotifications

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
    let hasUpdate = UpdateChecker.shared.hasUpdate()
    
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
        
        // Draw update badge directly on the icon
        if hasUpdate {
            let badgeSize: CGFloat = 48
            let badgeX = rect.width - badgeSize - 2
            let badgeY = rect.height - badgeSize - 2
            let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeSize, height: badgeSize)
            
            // Red circle background
            let badgePath = NSBezierPath(ovalIn: badgeRect)
            NSColor.systemRed.setFill()
            badgePath.fill()
            
            // White up arrow text
            let badgeFont = NSFont.boldSystemFont(ofSize: 38)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraphStyle
            ]
            let badgeText = "↑"
            let badgeTextSize = (badgeText as NSString).size(withAttributes: badgeAttrs)
            let badgeTextRect = NSRect(
                x: badgeX + (badgeSize - badgeTextSize.width) / 2,
                y: badgeY + (badgeSize - badgeTextSize.height) / 2 - 1,
                width: badgeTextSize.width,
                height: badgeTextSize.height
            )
            (badgeText as NSString).draw(in: badgeTextRect, withAttributes: badgeAttrs)
            print("🔔 Drawing badge directly on icon")
        }

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
    weak var appDelegate: AppDelegate?  // Store reference to AppDelegate
    var loginWindowIsOpen = false  // Track if login window is already shown (internal access)
    var windowOpenedForLogin = false  // Track if window was auto-opened for login vs manually opened
    private var cookiesReady = false  // Track if we've verified cookies are loaded

    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        hiddenWebView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800), configuration: config)
        hiddenWebView.navigationDelegate = self
        
        // Wait for cookies to be loaded from disk before marking as ready
        ensureCookiesLoaded()
    }

    private var retryTimer: Timer?
    
    // Ensure cookies are loaded from disk before attempting any requests
    private func ensureCookiesLoaded() {
        print("🍪 Waiting for WebKit to load cookies from disk...")
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            print("🍪 WebKit loaded \(cookies.count) total cookies, \(claudeCookies.count) for claude.ai")
            
            DispatchQueue.main.async {
                self?.cookiesReady = true
                print("✅ Cookies are ready")
            }
        }
    }
    
    // Quick check on app launch to see if we need to show login window
    func quickLoginCheck() {
        guard cookiesReady else {
            print("⏸️ Cookies not ready yet, waiting...")
            // Retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.quickLoginCheck()
            }
            return
        }
        
        guard !isScraping else {
            print("⏸️ Already scraping, skipping quick check")
            return
        }
        print("🔍 Quick login check...")
        isScraping = true
        hiddenWebView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }

    func startPeriodicFetch() {
        fetchUsage()
        // Retry every 10 seconds until first success
        retryTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.hasSucceeded {
                timer.invalidate()
                self.retryTimer = nil
                // Switch to 8-minute refresh (480 seconds)
                self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 480, repeats: true) { [weak self] _ in
                    self?.fetchUsage()
                }
            } else {
                self.fetchUsage()
            }
        }
    }

    func fetchUsage() {
        // Don't fetch while login window is open
        guard !loginWindowIsOpen else {
            print("⏸️ Login window is open, pausing background scraping")
            isScraping = false
            return
        }
        
        // Wait for cookies to be loaded before attempting to fetch
        guard cookiesReady else {
            print("⏸️ Cookies not ready yet, waiting...")
            // Retry after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.fetchUsage()
            }
            return
        }
        
        guard !isScraping else { 
            print("⏸️ Already scraping, skipping duplicate request")
            return 
        }
        isScraping = true
        print("🔄 Fetching usage data...")
        
        // Check if we have cookies before attempting to load
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            let claudeCookies = cookies.filter { $0.domain.contains("claude.ai") }
            print("🍪 Found \(claudeCookies.count) claude.ai cookies")
        }
        
        hiddenWebView.load(URLRequest(url: URL(string: "https://claude.ai/settings/usage")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { 
            isScraping = false
            return 
        }
        
        // Check if redirected to login or logout (not authenticated)
        let urlString = url.absoluteString
        if url.path.contains("login") || url.path.contains("logout") || urlString.contains("returnTo") {
            print("⚠️ Not logged in — opening window for user to log in")
            isScraping = false
            
            // Only open the window once
            guard !loginWindowIsOpen else {
                print("🔒 Login window already open, skipping duplicate open request")
                return
            }
            
            loginWindowIsOpen = true
            windowOpenedForLogin = true  // Mark that this window was auto-opened for login
            
            // Show the login window
            DispatchQueue.main.async { [weak self] in
                print("🔍 Attempting to get AppDelegate...")
                guard let appDelegate = self?.appDelegate else {
                    print("❌ AppDelegate reference is nil! Trying NSApp.delegate...")
                    if let nsAppDelegate = NSApp.delegate as? AppDelegate {
                        print("✅ Got AppDelegate from NSApp, calling openClaudeWindow()")
                        nsAppDelegate.openClaudeWindow(autoOpenedForLogin: true)
                    } else {
                        print("❌ NSApp.delegate cast failed too!")
                        self?.loginWindowIsOpen = false  // Reset flag if failed
                        self?.windowOpenedForLogin = false
                    }
                    return
                }
                print("✅ Got AppDelegate from stored reference, calling openClaudeWindow()")
                appDelegate.openClaudeWindow(autoOpenedForLogin: true)
            }
            return
        }
        
        guard urlString.contains("settings/usage") else { 
            print("⚠️ Unexpected URL: \(urlString)")
            isScraping = false
            return 
        }

        // Wait for the SPA to render
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            webView.evaluateJavaScript(usageJS) { result, error in
                defer { self?.isScraping = false }

                if let error = error {
                    print("❌ JS error: \(error)")
                    // Clear cached values and show dashes
                    SessionStore.shared.sessionUsage = nil
                    SessionStore.shared.weeklyUsage = nil
                    SessionStore.shared.sessionResetText = nil
                    SessionStore.shared.weeklyResetText = nil
                    SessionStore.shared.isLoading = false  // No longer loading
                    updateDockIcon(session: nil, weekly: nil)
                    return
                }
                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    print("❌ Failed to parse usage JSON")
                    // Clear cached values and show dashes
                    SessionStore.shared.sessionUsage = nil
                    SessionStore.shared.weeklyUsage = nil
                    SessionStore.shared.sessionResetText = nil
                    SessionStore.shared.weeklyResetText = nil
                    SessionStore.shared.isLoading = false  // No longer loading
                    updateDockIcon(session: nil, weekly: nil)
                    return
                }

                guard let session = json["session"] as? Int,
                      let weekly = json["weekly"] as? Int else {
                    print("⚠️ Usage values not found in DOM — page may not have rendered yet")
                    // Clear cached values and show dashes
                    SessionStore.shared.sessionUsage = nil
                    SessionStore.shared.weeklyUsage = nil
                    SessionStore.shared.sessionResetText = nil
                    SessionStore.shared.weeklyResetText = nil
                    SessionStore.shared.isLoading = false  // No longer loading
                    updateDockIcon(session: nil, weekly: nil)
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

                // Mark as succeeded so we switch to 15-minute refresh
                if let self = self, !self.hasSucceeded {
                    self.hasSucceeded = true
                    self.loginWindowIsOpen = false  // Reset flag so window can open again if needed
                    self.windowOpenedForLogin = false  // Reset this too
                    print("🎉 First successful data fetch!")
                }
            }
        }
    }
}

// MARK: - Login WebView Coordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    var registered = false
    private var checkTimer: Timer?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url, url.host?.contains("claude.ai") == true else { return }

        if !registered {
            registered = true
            // Tell the scraper which window to close after first successful fetch
            UsageScraper.shared.loginWebView = webView
            
            // Start polling for URL changes every 2 seconds
            checkTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self, weak webView] _ in
                self?.checkIfLoggedIn(webView: webView)
            }
        }
        
        checkIfLoggedIn(webView: webView)
    }
    
    private func checkIfLoggedIn(webView: WKWebView?) {
        guard let webView = webView, let url = webView.url else { return }
        
        let urlString = url.absoluteString
        print("🌐 WebView current URL: \(urlString)")
        
        // STRICT check - ONLY close on /new or /chat URLs (actual logged-in pages)
        // Do NOT close on logout, login, or redirect URLs
        let isNewPage = urlString.contains("/new") && !urlString.contains("/login") && !urlString.contains("/logout")
        let isChatPage = urlString.contains("/chat") && !urlString.contains("/login") && !urlString.contains("/logout")
        
        if isNewPage || isChatPage {
            // Only auto-close if the window was opened automatically for login
            // If user manually opened it, let them use it normally
            if !UsageScraper.shared.windowOpenedForLogin {
                print("✅ Login successful, but window was manually opened - keeping it open")
                checkTimer?.invalidate()
                checkTimer = nil
                return
            }
            
            // User is logged in via auto-opened window! Close it and reset the flag
            print("✅ Login successful! User reached: \(urlString)")
            print("🪟 Auto-closing login window...")
            
            // Stop the timer
            checkTimer?.invalidate()
            checkTimer = nil
            
            UsageScraper.shared.loginWindowIsOpen = false
            UsageScraper.shared.windowOpenedForLogin = false
            
            // Use the stored appDelegate reference instead of NSApp.delegate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let appDelegate = UsageScraper.shared.appDelegate {
                    if let window = appDelegate.claudeWindow {
                        print("🪟 Actually closing window: \(window)")
                        window.close()
                        appDelegate.claudeWindow = nil
                    } else {
                        print("⚠️ Window reference was nil, couldn't close")
                    }
                } else {
                    print("⚠️ Couldn't get AppDelegate from UsageScraper")
                }
            }
        }
    }
    
    deinit {
        checkTimer?.invalidate()
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
// MARK: - Update Checker

class UpdateChecker {
    static let shared = UpdateChecker()
    private var latestVersionString: String? {
        didSet {
            UserDefaults.standard.set(latestVersionString, forKey: "latestVersionString")
        }
    }
    private var updateAvailable = false {
        didSet {
            UserDefaults.standard.set(updateAvailable, forKey: "updateAvailable")
        }
    }
    
    private init() {
        // Restore state from UserDefaults
        latestVersionString = UserDefaults.standard.string(forKey: "latestVersionString")
        updateAvailable = UserDefaults.standard.bool(forKey: "updateAvailable")
    }
    
    func startChecking() {
        // Request notification permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            if granted {
                print("✅ Notification permission granted")
            }
        }
        
        // Check for updates immediately on launch
        checkForUpdates()
        
        // Then check every hour (3600 seconds)
        Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }
    
    func checkForUpdates() {
        guard let url = URL(string: "https://api.github.com/repos/tomigorn/MacOS-Dock-ClaudeAI/releases/latest") else { return }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                return
            }
            
            DispatchQueue.main.async {
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                let wasUpdateAvailable = self.updateAvailable
                
                if self.isNewer(remote: tagName, local: currentVersion) {
                    self.latestVersionString = tagName
                    self.updateAvailable = true
                    print("✅ Update available: \(tagName) (current: \(currentVersion))")
                    
                    // Only send notification if this is a newly detected update
                    if !wasUpdateAvailable {
                        self.sendUpdateNotification(version: tagName)
                    }
                    
                    // Redraw the dock icon with the badge
                    let store = SessionStore.shared
                    updateDockIcon(session: store.sessionUsage, weekly: store.weeklyUsage)
                } else {
                    // No update available - clear the flags
                    if wasUpdateAvailable {
                        print("✅ App is now up to date (current: \(currentVersion), latest: \(tagName))")
                    }
                    self.latestVersionString = nil
                    self.updateAvailable = false
                    
                    // Redraw the dock icon without the badge
                    let store = SessionStore.shared
                    updateDockIcon(session: store.sessionUsage, weekly: store.weeklyUsage)
                }
            }
        }.resume()
    }
    
    func hasUpdate() -> Bool {
        return updateAvailable
    }
    
    func getLatestVersion() -> String? {
        return latestVersionString
    }
    
    func openReleasesPage() {
        if let url = URL(string: "https://github.com/tomigorn/MacOS-Dock-ClaudeAI/releases") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func sendUpdateNotification(version: String) {
        let content = UNMutableNotificationContent()
        content.title = "Update Available"
        content.body = "Version \(version) is now available. Right-click the dock icon to update."
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: "update-available", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Failed to send notification: \(error)")
            }
        }
    }
    
    private func isNewer(remote: String, local: String) -> Bool {
        let remoteClean = remote.replacingOccurrences(of: "v", with: "")
        let localClean = local.replacingOccurrences(of: "v", with: "")
        
        let remoteParts = remoteClean.split(separator: ".").compactMap { Int($0) }
        let localParts = localClean.split(separator: ".").compactMap { Int($0) }
        
        for i in 0..<max(remoteParts.count, localParts.count) {
            let r = i < remoteParts.count ? remoteParts[i] : 0
            let l = i < localParts.count ? localParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}

