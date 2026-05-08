//
//  UpdateChecker.swift
//  MacOS-Dock-ClaudeAI
//
//  Created by Tomas Milata on 08.05.2026.
//

import Foundation
import AppKit

class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    
    @Published var latestVersion: String?
    @Published var latestReleaseURL: String?
    @Published var isUpdateAvailable: Bool = false
    
    private let githubReleasesURL = "https://api.github.com/repos/tomigorn/MacOS-Dock-ClaudeAI/releases/latest"
    private var checkTimer: Timer?
    
    private init() {}
    
    func startPeriodicCheck() {
        // Check immediately on launch
        checkForUpdates()
        
        // Then check every 6 hours
        checkTimer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }
    
    func checkForUpdates() {
        guard let url = URL(string: githubReleasesURL) else { return }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil else {
                print("❌ Update check failed: \(error?.localizedDescription ?? "unknown error")")
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let tagName = json["tag_name"] as? String,
                   let htmlURL = json["html_url"] as? String {
                    
                    DispatchQueue.main.async {
                        self.latestVersion = tagName
                        self.latestReleaseURL = htmlURL
                        
                        let currentVersion = self.getCurrentVersion()
                        let isNewer = self.isNewerVersion(latest: tagName, current: currentVersion)
                        
                        if isNewer {
                            self.isUpdateAvailable = true
                            print("✅ Update available: \(tagName) (current: \(currentVersion))")
                        } else {
                            self.isUpdateAvailable = false
                            print("✅ App is up to date: \(currentVersion)")
                        }
                    }
                }
            } catch {
                print("❌ Failed to parse update response: \(error)")
            }
        }.resume()
    }
    
    func openReleasePage() {
        guard let urlString = latestReleaseURL ?? "https://github.com/tomigorn/MacOS-Dock-ClaudeAI/releases",
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
    
    private func getCurrentVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    
    private func isNewerVersion(latest: String, current: String) -> Bool {
        // Remove 'v' prefix if present
        let latestClean = latest.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        let currentClean = current.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
        
        let latestComponents = latestClean.split(separator: ".").compactMap { Int($0) }
        let currentComponents = currentClean.split(separator: ".").compactMap { Int($0) }
        
        // Compare version components
        for i in 0..<max(latestComponents.count, currentComponents.count) {
            let latestNum = i < latestComponents.count ? latestComponents[i] : 0
            let currentNum = i < currentComponents.count ? currentComponents[i] : 0
            
            if latestNum > currentNum {
                return true
            } else if latestNum < currentNum {
                return false
            }
        }
        
        return false
    }
}
