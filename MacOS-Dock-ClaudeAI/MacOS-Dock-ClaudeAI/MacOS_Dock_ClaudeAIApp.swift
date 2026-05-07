//
//  MacOS_Dock_ClaudeAIApp.swift
//  MacOS-Dock-ClaudeAI
//
//  Created by Tomas Milata on 07.05.2026.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
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

        return menu
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
