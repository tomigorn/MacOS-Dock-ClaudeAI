import AppKit

/// Draws live usage percentages onto an NSImage and sets it as the Dock icon.
/// All rendering happens on the main thread.
final class DockIconRenderer {

    static let shared = DockIconRenderer()
    private init() {}

    // Icon canvas size (points). Retina will scale automatically.
    private let size = NSSize(width: 128, height: 128)

    // MARK: - Public API

    /// Render new values onto the Dock icon.
    /// Pass `nil` for either value to display "?%" instead.
    func render(daily: Double?, weekly: Double?) {
        assert(Thread.isMainThread, "DockIconRenderer must be called on the main thread")
        let image = buildImage(daily: daily, weekly: weekly)
        NSApplication.shared.applicationIconImage = image
    }

    // MARK: - Drawing

    private func buildImage(daily: Double?, weekly: Double?) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(origin: .zero, size: size)

        drawBackground(in: rect)
        drawText(daily: daily, weekly: weekly, in: rect)

        return image
    }

    // Dark rounded-rectangle background
    private func drawBackground(in rect: NSRect) {
        let inset = rect.insetBy(dx: 6, dy: 6)
        let path = NSBezierPath(roundedRect: inset, xRadius: 20, yRadius: 20)

        // Deep charcoal background
        NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0).setFill()
        path.fill()

        // Subtle border
        NSColor(white: 0.35, alpha: 0.6).setStroke()
        path.lineWidth = 2.5
        path.stroke()
    }

    // Two lines of bold white text
    private func drawText(daily: Double?, weekly: Double?, in rect: NSRect) {
        let dailyString  = formatPercent(daily)
        let weeklyString = formatPercent(weekly) + " wk"

        // Typography
        let topFont    = NSFont.boldSystemFont(ofSize: 34)
        let bottomFont = NSFont.boldSystemFont(ofSize: 26)

        let topColor    = textColor(for: daily)
        let bottomColor = textColor(for: weekly)

        let topAttrs: [NSAttributedString.Key: Any] = [
            .font: topFont,
            .foregroundColor: topColor,
        ]
        let bottomAttrs: [NSAttributedString.Key: Any] = [
            .font: bottomFont,
            .foregroundColor: bottomColor,
        ]

        let topStr    = NSAttributedString(string: dailyString, attributes: topAttrs)
        let bottomStr = NSAttributedString(string: weeklyString, attributes: bottomAttrs)

        let topSize    = topStr.size()
        let bottomSize = bottomStr.size()

        let padding: CGFloat = 6
        let totalH = topSize.height + bottomSize.height + padding
        let startY = (rect.height - totalH) / 2

        let topX    = (rect.width - topSize.width) / 2
        let bottomX = (rect.width - bottomSize.width) / 2

        topStr.draw(at: NSPoint(x: topX, y: startY + bottomSize.height + padding))
        bottomStr.draw(at: NSPoint(x: bottomX, y: startY))
    }

    // MARK: - Helpers

    private func formatPercent(_ value: Double?) -> String {
        guard let v = value else { return "?%" }
        return "\(Int(v.rounded()))%"
    }

    /// Color shifts from white → yellow → orange as usage climbs past thresholds.
    private func textColor(for value: Double?) -> NSColor {
        guard let v = value else { return .white }
        switch v {
        case ..<70:  return .white
        case ..<85:  return NSColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1.0)  // yellow
        default:     return NSColor(red: 1.0, green: 0.45, blue: 0.2, alpha: 1.0)  // orange-red
        }
    }
}
