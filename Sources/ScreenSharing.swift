import AppKit
import IOKit.pwr_mgt

/// A best-effort guess at whether the screen is being shared or recorded right now. macOS has no public way to ask,
/// so this looks for the telltale signs that apps leave: a sharing indicator window (Zoom's share bar, Meet's
/// "is sharing your screen"), whose title macOS only reveals to an app with the Screen Recording permission, or a
/// power assertion that says so. Without the permission it can see far less. When it can't tell, it says no.
enum ScreenSharing {
    static func isActive() -> Bool { windowsMentionSharing() || assertionsMentionSharing() }

    /// Whether macOS lets this app read other apps' window titles (the Screen Recording permission). Bismillah never
    /// captures the screen; this is only used to read the titles of sharing indicators.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows macOS's own permission prompt the first time it is asked. Returns whether it is already allowed.
    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    static var settingsURL: URL { URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")! }

    private static let assertionPhrases = ["screen shar", "sharing your screen", "sharing screen", "sharing the screen",
                                           "screen captur", "screen record", "display captur", "desktop shar"]
    /// What the sharing bar of a meeting app says. Specific on purpose: window titles in these apps also hold chat and
    /// channel names, so a plain "sharing" or "recording" would trigger on a chat called "Sharing ideas".
    private static let meetingPhrases = ["is sharing your screen", "is sharing a window", "you are sharing", "you're sharing",
                                         "you are screen sharing", "stop sharing", "stop presenting", "sharing control", "sharing toolbar", "share toolbar",
                                         "share statusbar"]
    private static let meetingApps: Set<String> = ["zoom.us", "Microsoft Teams", "MSTeams", "Microsoft Teams (work or school)", "Slack",
                                                   "Discord", "FaceTime", "Webex", "Loom"]
    /// Apps whose job is capturing the screen, where the mention of recording is itself the sign.
    private static let recorderPhrases = ["recording", "screen sharing", "sharing your screen", "stop sharing"]
    private static let recorderApps: Set<String> = ["QuickTime Player", "screencaptureui", "Screenshot", "OBS", "Screen Sharing",
                                                    "Control Centre", "Control Center"]
    /// Browsers show an indicator such as "meet.google.com is sharing your screen", but their window titles are also
    /// web page titles, so only the specific "is sharing" wording counts there.
    private static let browserPhrases = ["is sharing your screen", "is sharing a window", "is sharing a tab", "is sharing this tab"]

    private static func assertionsMentionSharing() -> Bool {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        let me = NSNumber(value: getpid())
        for (pid, assertions) in byProcess where pid != me {
            for assertion in assertions {
                let name = (assertion["AssertName"] as? String ?? "").lowercased()
                if assertionPhrases.contains(where: name.contains) { return true }
            }
        }
        return false
    }

    private static func windowsMentionSharing() -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let me = getpid()
        for window in list {
            guard (window[kCGWindowOwnerPID as String] as? Int32) != me,
                  let owner = window[kCGWindowOwnerName as String] as? String,
                  let title = (window[kCGWindowName as String] as? String)?.lowercased(), !title.isEmpty else { continue }
            if owner == "zoom.us", title.contains("share toolbar") || title.contains("share statusbar") { return true }
            if meetingApps.contains(owner) || owner.contains("Teams"), meetingPhrases.contains(where: title.contains) { return true }
            if recorderApps.contains(owner), recorderPhrases.contains(where: title.contains) { return true }
            if browserPhrases.contains(where: title.contains) { return true }
        }
        return false
    }
}
