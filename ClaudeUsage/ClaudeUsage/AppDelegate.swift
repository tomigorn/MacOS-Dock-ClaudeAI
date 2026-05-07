import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("HELLO WORLD - APP STARTED")

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Hello World"
        window.isReleasedWhenClosed = false
        window.center()

        let label = NSTextField(labelWithString: "Hello World!")
        label.font = NSFont.boldSystemFont(ofSize: 32)
        label.alignment = .center
        label.frame = window.contentView!.bounds
        label.autoresizingMask = [.width, .height]
        window.contentView?.addSubview(label)

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        NSLog("WINDOW SHOULD BE VISIBLE NOW")
    }
}
