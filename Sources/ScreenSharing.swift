import AppKit
import IOKit.pwr_mgt

/// A best-effort guess at whether the screen is being shared or recorded right now. macOS has no public way to ask,
/// so this looks for the telltale signs that apps leave: a power assertion that says so (video-call apps and
/// recorders usually take one), or a sharing indicator window (its title is only readable when macOS lets this app
/// see window titles). When it can't tell, it says no.
enum ScreenSharing {
    static func isActive() -> Bool { assertionsMentionSharing() || windowsMentionSharing() }

    private static let assertionPhrases = ["screen shar", "sharing your screen", "sharing screen", "sharing the screen",
                                           "screen captur", "screen record", "display captur", "desktop shar"]
    /// What a sharing indicator window says, in the apps that show one.
    private static let indicatorPhrases = ["is sharing your screen", "is sharing a window", "is sharing a tab", "is sharing this tab",
                                           "you are sharing", "you're sharing", "stop sharing", "stop share", "screen sharing",
                                           "recording"]
    /// Apps whose window titles are about the meeting or recording rather than a web page, so they're safe to match.
    private static let indicatorApps: Set<String> = ["zoom.us", "Microsoft Teams", "MSTeams", "Microsoft Teams (work or school)", "Slack",
                                                     "Discord", "FaceTime", "Webex", "QuickTime Player", "screencaptureui", "Screenshot",
                                                     "OBS", "Loom", "Screen Sharing"]
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
            if indicatorApps.contains(owner), indicatorPhrases.contains(where: title.contains) { return true }
            if browserPhrases.contains(where: title.contains) { return true }
        }
        return false
    }
}
