# Claude Usage — macOS Dock Monitor

A native macOS app that scrapes your Claude.ai usage limits and renders them live onto the Dock icon.

![Dock icon showing 73% and 68% wk](docs/dock-icon-preview.png)

## What it does

- Shows your **current usage window %** and **weekly usage %** directly on the Dock icon
- Polls claude.ai every **15 minutes** in the background
- Keeps a **WKWebView window** open so you stay logged in (your existing cookies are reused — no credentials stored)
- Stays running after you close the window; click the Dock icon to reopen it
- Text color shifts white → yellow → orange as usage climbs past 70% / 85%

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later (free from the Mac App Store)
- A Claude.ai account

## Installation

### 1. Clone the repo

```bash
git clone <repo-url>
cd MacOS-Dock-ClaudeAI
```

### 2. Open in Xcode

```bash
open ClaudeUsage/ClaudeUsage.xcodeproj
```

### 3. Set your signing team

Xcode needs a code signing identity to build a macOS app, even for local use.

1. In the Xcode sidebar, click the **ClaudeUsage** project (top of the tree)
2. Select the **ClaudeUsage** target
3. Open the **Signing & Capabilities** tab
4. Under **Team**, choose your personal Apple ID (add it via Xcode → Settings → Accounts if needed)

If you don't have a paid developer account, choose your free personal team — this works fine for running on your own Mac.

### 4. Build and run

Press **⌘R** (or Product → Run).

The app will:
- Open a window with claude.ai loaded
- Show `?%` on the Dock icon until the first scrape completes (~5 seconds after launch)

### 5. Log in to Claude

If you're not already logged in, log in normally inside the app window. Your session persists across relaunches via the system cookie store.

### 6. (Optional) Launch at login

To have the app start automatically when you log in to your Mac:

1. Build a Release build: Product → Archive, then Distribute App → Copy App
2. Move `ClaudeUsage.app` to `/Applications`
3. Open **System Settings → General → Login Items**
4. Click **+** and add `ClaudeUsage.app`

Alternatively, with the app running, right-click its Dock icon → Options → **Open at Login**.

## How the scraping works

Every 15 minutes the app navigates its WKWebView to `claude.ai/settings/limits`, waits ~2.5 seconds for React to render, then injects a small JavaScript snippet that reads the usage percentages from the DOM. The page is then navigated back to `claude.ai` to keep your session warm.

The JS tries three selector strategies in order:

1. `[role="progressbar"]` ARIA attributes
2. Bare text nodes matching `/^\d{1,3}%$/`
3. `data-testid` attributes

If none match (e.g. after a Claude DOM update), the icon shows `?%` and an error is logged to the console. To fix a broken selector, edit the `scraperScript` constant at the top of `ClaudeUsage/ClaudeUsage/UsageScraper.swift`.

## Project layout

```
ClaudeUsage/
├── ClaudeUsage.xcodeproj/
└── ClaudeUsage/
    ├── AppDelegate.swift           # lifecycle, 15-min timer, orchestration
    ├── MainWindowController.swift  # WKWebView window + scrape coordination
    ├── UsageScraper.swift          # JS injection and response parsing
    ├── DockIconRenderer.swift      # draws the live Dock icon
    ├── Info.plist                  # app metadata, no quit-on-close
    └── ClaudeUsage.entitlements    # sandbox + outbound network
```

## Permissions

The app requests only:

- `com.apple.security.network.client` — outbound HTTPS to claude.ai
- `com.apple.security.app-sandbox` — standard sandboxing

No microphone, camera, location, contacts, or keychain access.

## Troubleshooting

**Icon stays at `?%`**
The DOM selectors may have broken after a Claude update. Open the Console app, filter by `ClaudeUsage`, and look for `[UsageScraper]` log lines. Then update `scraperScript` in `UsageScraper.swift`.

**App doesn't stay in the Dock after closing the window**
This is expected — the app runs as a regular app (not a menu-bar-only app) so it remains in the Dock. Closing the window doesn't quit it; use ⌘Q to quit.

**Build error: "No account for team"**
Go to Xcode → Settings → Accounts → add your Apple ID.

**Build error about signing**
Try: Product → Clean Build Folder (⇧⌘K), then build again.
