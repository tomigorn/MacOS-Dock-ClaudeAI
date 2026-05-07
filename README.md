# Claude Usage — macOS Dock Monitor

A native macOS app that shows your Claude.ai usage percentages directly on the Dock icon.

## What it does

- Shows your **current session %** and **weekly usage %** on the Dock icon
- Right-click the Dock icon to see details with reset times
- Polls claude.ai every **15 minutes** in the background using a hidden WKWebView
- Closes the window automatically after first successful fetch
- Stays running after the window closes; click the Dock icon to reopen

## Requirements

- macOS 26.4 or later
- Xcode 26.4 or later
- A Claude.ai account

## Build & Run

1. Clone the repo and open in Xcode:
   ```bash
   git clone <repo-url>
   cd MacOS-Dock-ClaudeAI
   open MacOS-Dock-ClaudeAI/MacOS-Dock-ClaudeAI.xcodeproj
   ```

2. In Xcode, select the **MacOS-Dock-ClaudeAI** target, open **Signing & Capabilities**, and choose your personal Apple ID as the Team.

3. Press **Cmd+R** to build and run.

4. Log in to Claude in the browser window that opens. The app will automatically fetch your usage data and close the window.

## Export the app (no developer account needed)

1. In Xcode: **Product → Archive**
2. In the Organizer: **Distribute App → Custom → Copy App**
3. Choose a save location (e.g. Desktop)
4. Right-click the `.app` → **Compress** to create a `.zip`
5. Upload the `.zip` to a GitHub release, or move the `.app` to `/Applications`

> **Note:** Since the app is not notarized, anyone installing it needs to right-click → Open on first launch to bypass the macOS security warning.

## Launch at login

With the app running, right-click its Dock icon → Options → **Open at Login**.

## How it works

On launch, a WKWebView loads claude.ai so you can log in. A separate hidden WKWebView navigates to `claude.ai/settings/usage`, waits for the page to render, then injects JavaScript that reads `aria-valuenow` from the usage progress bars. The percentages are drawn onto the Dock icon as bold white text on a dark rounded rectangle.

The scraping JS is defined in the `usageJS` constant at the top of `ContentView.swift` — update it there if Claude's DOM changes.

## Permissions

The app only requires outbound network access (`com.apple.security.network.client`) within the standard app sandbox.
