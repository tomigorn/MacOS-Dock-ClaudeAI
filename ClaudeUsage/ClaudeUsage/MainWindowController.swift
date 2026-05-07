import AppKit
import WebKit

/// Hosts the WKWebView that keeps a live session on claude.ai.
/// The view also acts as the scraping host — JS is injected into the limits page.
class MainWindowController: NSWindowController {

    private var webView: WKWebView!

    // Tracks whether we have navigated to the limits page for scraping
    private var isScraping = false

    // Pending scrape completion handler
    private var scrapeCompletion: ((Result<UsageData, Error>) -> Void)?

    // URL we always return to after scraping
    private let homeURL = URL(string: "https://claude.ai")!
    private let limitsURL = URL(string: "https://claude.ai/settings/limits")!

    // MARK: - Init

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Usage"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        setupWebView()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    // MARK: - Setup

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // Share the default data store so cookies persist across launches
        config.websiteDataStore = .default()

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]

        window?.contentView = webView

        // Load claude.ai on first launch so the user can log in
        load(url: homeURL)
    }

    private func load(url: URL) {
        webView.load(URLRequest(url: url))
    }

    // MARK: - Scraping

    /// Navigate to the limits page, extract usage data, then navigate back to claude.ai.
    func scrapeUsage(completion: @escaping (Result<UsageData, Error>) -> Void) {
        guard !isScraping else {
            completion(.failure(ScrapeError.alreadyScraping))
            return
        }
        isScraping = true
        scrapeCompletion = completion
        load(url: limitsURL)
    }

    /// Called after the limits page finishes loading — inject JS and extract values.
    private func extractUsageFromPage() {
        UsageScraper.extractUsage(from: webView) { [weak self] result in
            guard let self else { return }
            self.isScraping = false
            let completion = self.scrapeCompletion
            self.scrapeCompletion = nil

            // Navigate back to the main page so the session stays warm
            self.load(url: self.homeURL)

            completion?(result)
        }
    }
}

// MARK: - WKNavigationDelegate

extension MainWindowController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }

        if isScraping && url.absoluteString.hasPrefix(limitsURL.absoluteString) {
            // Give the React app a moment to render dynamic content before scraping
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.extractUsageFromPage()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isScraping else { return }
        isScraping = false
        let completion = scrapeCompletion
        scrapeCompletion = nil
        print("[ClaudeUsage] Navigation failed during scrape: \(error.localizedDescription)")
        completion?(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard isScraping else { return }
        isScraping = false
        let completion = scrapeCompletion
        scrapeCompletion = nil
        print("[ClaudeUsage] Provisional navigation failed during scrape: \(error.localizedDescription)")
        completion?(.failure(error))
    }
}

// MARK: - Errors

enum ScrapeError: LocalizedError {
    case alreadyScraping
    case parseFailure(String)
    case javascriptError(String)

    var errorDescription: String? {
        switch self {
        case .alreadyScraping:       return "A scrape is already in progress."
        case .parseFailure(let msg): return "Parse failure: \(msg)"
        case .javascriptError(let msg): return "JavaScript error: \(msg)"
        }
    }
}
