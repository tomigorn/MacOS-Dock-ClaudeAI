//
//  MacOS_Dock_ClaudeAIApp.swift
//  MacOS-Dock-ClaudeAI
//
//  Created by Tomas Milata on 07.05.2026.
//

import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        // Set a dark placeholder icon as early as possible
        updateDockIcon()
        // Start scraping immediately — don't wait for the visible window
        UsageScraper.shared.startPeriodicFetch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
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

        let isEnabled = SMAppService.mainApp.status == .enabled
        let loginItem = NSMenuItem(
            title: isEnabled ? "Disable Launch at Login" : "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        if isEnabled {
            loginItem.state = .on
        }
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem.separator())

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
}

@main
struct MacOS_Dock_ClaudeAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1200, height: 800)
    }
}
