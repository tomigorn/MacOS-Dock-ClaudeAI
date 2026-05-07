import WebKit

/// Parsed usage values scraped from claude.ai/settings/limits.
struct UsageData {
    /// Current usage window percentage (0–100), nil if not found.
    var dailyPercent: Double?
    /// Weekly usage percentage (0–100), nil if not found.
    var weeklyPercent: Double?
}

/// Injects JavaScript into a WKWebView pointed at the limits page and parses the result.
///
/// The JS selector logic is intentionally isolated here — update `scraperScript` when
/// Claude's DOM structure changes.
enum UsageScraper {

    // MARK: - JS Scraper Script
    //
    // Strategy: look for progress-bar aria-valuenow attributes or text content
    // that contains percentage-like numbers near usage-related labels.
    //
    // This is the single place to update if claude.ai changes its DOM.
    private static let scraperScript = """
    (function() {
        // Helper: parse a percentage string like "73%" or "73" into a number.
        function parsePct(str) {
            if (!str) return null;
            var n = parseFloat(str.replace(/[^0-9.]/g, ''));
            return isNaN(n) ? null : n;
        }

        // --- Strategy 1: ARIA progress bars ---
        // Claude renders usage as <div role="progressbar" aria-valuenow="73" ...>
        var bars = Array.from(document.querySelectorAll('[role="progressbar"]'));
        var ariaValues = bars
            .map(function(el) { return parsePct(el.getAttribute('aria-valuenow')); })
            .filter(function(v) { return v !== null; });

        if (ariaValues.length >= 2) {
            return JSON.stringify({ daily: ariaValues[0], weekly: ariaValues[1] });
        }
        if (ariaValues.length === 1) {
            return JSON.stringify({ daily: ariaValues[0], weekly: null });
        }

        // --- Strategy 2: Text content scan ---
        // Find elements whose text looks like "73%" near "usage" or "limit" labels.
        var pctPattern = /^\\d{1,3}%$/;
        var candidates = Array.from(document.querySelectorAll('*')).filter(function(el) {
            return el.children.length === 0 && pctPattern.test((el.textContent || '').trim());
        });

        var nums = candidates
            .map(function(el) { return parsePct(el.textContent); })
            .filter(function(v) { return v !== null; });

        if (nums.length >= 2) {
            return JSON.stringify({ daily: nums[0], weekly: nums[1] });
        }
        if (nums.length === 1) {
            return JSON.stringify({ daily: nums[0], weekly: null });
        }

        // --- Strategy 3: data-testid attributes ---
        var testIds = [
            'usage-daily-percent',
            'usage-weekly-percent',
            'daily-usage',
            'weekly-usage'
        ];
        var found = {};
        testIds.forEach(function(id) {
            var el = document.querySelector('[data-testid="' + id + '"]');
            if (el) found[id] = parsePct(el.textContent);
        });
        if (Object.keys(found).length > 0) {
            return JSON.stringify({ daily: found['usage-daily-percent'] || found['daily-usage'] || null,
                                    weekly: found['usage-weekly-percent'] || found['weekly-usage'] || null });
        }

        return JSON.stringify({ daily: null, weekly: null, debug: 'no selectors matched' });
    })();
    """

    // MARK: - Public API

    /// Inject the scraper into `webView` and call `completion` on the main thread.
    static func extractUsage(
        from webView: WKWebView,
        completion: @escaping (Result<UsageData, Error>) -> Void
    ) {
        webView.evaluateJavaScript(scraperScript) { result, error in
            DispatchQueue.main.async {
                if let error {
                    print("[UsageScraper] JS evaluation error: \(error.localizedDescription)")
                    completion(.failure(ScrapeError.javascriptError(error.localizedDescription)))
                    return
                }

                guard let jsonString = result as? String,
                      let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    let msg = "Unexpected JS result: \(String(describing: result))"
                    print("[UsageScraper] \(msg)")
                    completion(.failure(ScrapeError.parseFailure(msg)))
                    return
                }

                if let debug = json["debug"] as? String {
                    print("[UsageScraper] Debug note from JS: \(debug)")
                }

                let usage = UsageData(
                    dailyPercent: json["daily"] as? Double,
                    weeklyPercent: json["weekly"] as? Double
                )
                completion(.success(usage))
            }
        }
    }
}
