//
//  MacOS_Dock_ClaudeAIApp.swift
//  MacOS-Dock-ClaudeAI
//
//  Created by Tomas Milata on 07.05.2026.
//

import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var claudeWindow: NSWindow?
    
    override init() {
        super.init()
        // Set a dark placeholder icon as early as possible
        updateDockIcon()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Give WebKit more time to fully initialize and load cookies from disk
        // Especially important after a cold boot (shutdown vs restart)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
            UsageScraper.shared.startPeriodicFetch()
        }
        
        // Start update checker
        UpdateChecker.shared.startChecking()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    // Handle left-click on dock icon - show menu instead of opening window
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Don't open any windows - return false to prevent default behavior
        // But we can't easily show the dock menu programmatically with system items
        // So we'll just prevent the window from opening
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let store = SessionStore.shared

        let sessionText = "Session: \(store.sessionUsage.map { "\($0)%" } ?? "—")"
        let sessionReset = store.sessionResetText ?? ""
        let sessionItem = NSMenuItem(title: sessionText + (sessionReset.isEmpty ? "" : "  ·  \(sessionReset)"), action: nil, keyEquivalent: "")
        sessionItem.isEnabled = false
        menu.addItem(sessionItem)

        let weeklyText = "Weekly: \(store.weeklyUsage.map { "\($0)%" } ?? "—")"
        let weeklyReset = store.weeklyResetText ?? ""
        let weeklyItem = NSMenuItem(title: weeklyText + (weeklyReset.isEmpty ? "" : "  ·  \(weeklyReset)"), action: nil, keyEquivalent: "")
        weeklyItem.isEnabled = false
        menu.addItem(weeklyItem)

        menu.addItem(NSMenuItem.separator())

        // Open Claude browser window
        let openWindowItem = NSMenuItem(
            title: "Open Claude Browser",
            action: #selector(openClaudeWindow),
            keyEquivalent: ""
        )
        openWindowItem.target = self
        menu.addItem(openWindowItem)

        menu.addItem(NSMenuItem.separator())

        let isEnabled = SMAppService.mainApp.status == .enabled
        let statusIcon = isEnabled ? "✓" : "✗"
        let loginItem = NSMenuItem(
            title: "\(statusIcon) Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

        // Check for updates
        if UpdateChecker.shared.hasUpdate(), let version = UpdateChecker.shared.getLatestVersion() {
            let updateItem = NSMenuItem(title: "Update Available → \(version)", action: #selector(openUpdates), keyEquivalent: "")
            updateItem.target = self
            menu.addItem(updateItem)
            menu.addItem(NSMenuItem.separator())
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "v\(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        return menu
    }

    @objc func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                print("Launch at login disabled")
            } else {
                try SMAppService.mainApp.register()
                print("Launch at login enabled")
            }
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }
    
    @objc func openClaudeWindow() {
        // Check if we already have a Claude window
        if let existingWindow = claudeWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a new window
        let contentView = ContentView()
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Claude AI"
        window.setContentSize(NSSize(width: 1200, height: 800))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Store reference
        claudeWindow = window
    }
    
    @objc func openUpdates() {
        UpdateChecker.shared.openReleasesPage()
    }
}

@main
struct MacOS_Dock_ClaudeAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty Settings scene - prevents automatic window creation
        Settings {
            EmptyView()
        }
    }
}
