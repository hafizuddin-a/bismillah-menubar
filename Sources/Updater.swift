import AppKit
import CryptoKit

/// Keeps Bismillah up to date from this project's GitHub releases.
///
/// A release carries `Bismillah-<version>.zip` and `Bismillah-<version>.zip.sig`. The signature is an
/// Ed25519 signature of the zip, made with a private key that never leaves the maintainer's machine; the
/// matching public key is built into the app (Info.plist, `BismillahUpdateKey`). Nothing is installed
/// unless the signature checks out, so a hijacked release page alone can't ship code to users.
///
/// Installing means: unzip, check the package is really Bismillah at the announced version, quit, swap
/// the new app in for the old one, and open it again.
@MainActor
final class Updater {
    struct Release {
        let version: String
        let zip: URL
        let signature: URL
        let page: URL
    }

    enum UpdateError: LocalizedError {
        case noPublicKey
        case badSignature
        case badPackage(String)
        case cannotReplace(String)
        case http(Int)
        case missingFiles(String)

        var errorDescription: String? {
            switch self {
            case .noPublicKey: return "This build has no update key, so it can't verify updates."
            case .badSignature: return "The download's signature didn't match, so it was not installed."
            case .badPackage(let why): return "The download wasn't a valid Bismillah update (\(why))."
            case .cannotReplace(let why): return why
            case .http(let code): return "GitHub answered with HTTP \(code)."
            case .missingFiles(let version): return "Version \(version) is published but its update files are missing."
            }
        }
    }

    static let repository = "hafizuddin-a/bismillah-menubar"
    static let automaticKey = "UpdateAutomatically"
    private static let lastCheckKey = "LastUpdateCheck"
    private static let minimumGap: TimeInterval = 7 * 24 * 3600      // between automatic checks: once a week
    private static let recheckEvery: TimeInterval = 6 * 3600

    private let isPopupShowing: () -> Bool
    private var working = false
    private var timer: Timer?

    init(isPopupShowing: @escaping () -> Bool) {
        self.isPopupShowing = isPopupShowing
        UserDefaults.standard.register(defaults: [Self.automaticKey: true])
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var automaticEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.automaticKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.automaticKey) }
    }

    /// `BISMILLAH_FEED_URL` only exists for testing against a local server; updates still need a valid signature.
    private var feedURL: URL {
        if let override = ProcessInfo.processInfo.environment["BISMILLAH_FEED_URL"], let url = URL(string: override) { return url }
        return URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!
    }

    // MARK: - automatic

    /// Looks shortly after launch if a week has passed since the last check, and again later if the app stays open.
    func startAutomaticChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.recheckEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    /// Checks (and installs) only if automatic updates are on and the last check was over a week ago.
    func checkIfDue() {
        guard automaticEnabled, !working else { return }
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Date().timeIntervalSince(last) < Self.minimumGap { return }
        Task { await runAutomatic() }
    }

    private func runAutomatic() async {
        working = true
        defer { working = false }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        do {
            guard let release = try await latestRelease() else { return }
            try await install(release, waitForQuietMoment: true)
        } catch {
            NSLog("Bismillah: automatic update failed: \(error.localizedDescription)")
        }
    }

    // MARK: - manual

    /// "Check for Updates…" in the menu: always asks GitHub and tells you what it found.
    func checkManually() {
        guard !working else { return }
        Task { await runManual() }
    }

    private func runManual() async {
        working = true
        defer { working = false }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        var found: Release?
        do {
            found = try await latestRelease()
            guard let release = found else {
                showAlert("Bismillah is up to date", "You have the latest version (\(currentVersion)).")
                return
            }
            let alert = NSAlert()
            alert.messageText = "Bismillah \(release.version) is available"
            alert.informativeText = "You have \(currentVersion). Bismillah will restart to finish updating."
            alert.addButton(withTitle: "Install and Restart")
            alert.addButton(withTitle: "Later")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try await install(release, waitForQuietMoment: false)
        } catch UpdateError.cannotReplace(let why) {
            let alert = NSAlert()
            alert.messageText = "Can't update in place"
            alert.informativeText = why
            alert.addButton(withTitle: "Open Release Page")
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn, let page = found?.page { NSWorkspace.shared.open(page) }
        } catch {
            showAlert("Couldn't update Bismillah", error.localizedDescription)
        }
    }

    private func showAlert(_ title: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: - finding a newer release

    private struct APIRelease: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
    }

    /// The newest published release if it is newer than this app, otherwise nil.
    private func latestRelease() async throws -> Release? {
        let data = try await fetch(feedURL)
        let api = try JSONDecoder().decode(APIRelease.self, from: data)
        guard !api.draft, !api.prerelease else { return nil }
        let version = api.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard Self.isNewer(version, than: currentVersion) else { return nil }
        guard let zip = api.assets.first(where: { $0.name == "Bismillah-\(version).zip" }),
              let sig = api.assets.first(where: { $0.name == "Bismillah-\(version).zip.sig" })
        else { throw UpdateError.missingFiles(version) }
        return Release(version: version, zip: zip.browser_download_url, signature: sig.browser_download_url, page: api.html_url)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func fetch(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bismillah/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw UpdateError.http(http.statusCode) }
        return data
    }

    // MARK: - installing

    private func install(_ release: Release, waitForQuietMoment: Bool) async throws {
        let staged = try await stage(release)
        // Don't restart while the popup is on screen.
        while waitForQuietMoment && isPopupShowing() { try await Task.sleep(nanoseconds: 3_000_000_000) }
        do {
            try replaceAndRelaunch(with: staged.app, workDirectory: staged.work)
        } catch {
            try? FileManager.default.removeItem(at: staged.work)
            throw error
        }
    }

    /// Downloads, verifies and unpacks the release. Returns the unpacked app and its scratch folder.
    private func stage(_ release: Release) async throws -> (app: URL, work: URL) {
        guard let keyText = Bundle.main.object(forInfoDictionaryKey: "BismillahUpdateKey") as? String,
              let keyData = Data(base64Encoded: keyText),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { throw UpdateError.noPublicKey }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("bismillah-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            var request = URLRequest(url: release.zip, timeoutInterval: 120)
            request.setValue("Bismillah/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (downloaded, response) = try await URLSession.shared.download(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw UpdateError.http(http.statusCode) }
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)

            let signatureText = String(decoding: try await fetch(release.signature), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let signature = Data(base64Encoded: signatureText),
                  key.isValidSignature(signature, for: try Data(contentsOf: zip, options: .mappedIfSafe))
            else { throw UpdateError.badSignature }

            let unpacked = work.appendingPathComponent("unpacked")
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            let app = unpacked.appendingPathComponent("Bismillah.app")
            guard let bundle = Bundle(url: app) else { throw UpdateError.badPackage("no app inside") }
            guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else { throw UpdateError.badPackage("wrong app") }
            let packaged = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            guard packaged == release.version else { throw UpdateError.badPackage("version \(packaged ?? "?") instead of \(release.version)") }
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
            return (app, work)
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw UpdateError.badPackage("\((tool as NSString).lastPathComponent) failed")
        }
    }

    /// A small script outlives this process: it waits for us to quit, swaps the app, and opens the new one.
    /// If the swap fails halfway, the old app is put back.
    private static let swapScript = """
    #!/bin/sh
    # swap.sh <pid> <installed.app> <new.app> <scratch folder>
    PID="$1"; TARGET="$2"; NEW="$3"; WORK="$4"
    n=0
    while kill -0 "$PID" 2>/dev/null && [ "$n" -lt 100 ]; do sleep 0.3; n=$((n + 1)); done
    OLD="$TARGET.old-$$"
    if mv "$TARGET" "$OLD"; then
      if mv "$NEW" "$TARGET"; then rm -rf "$OLD"; else mv "$OLD" "$TARGET"; fi
    fi
    rm -rf "$WORK"
    open "$TARGET" --args --after-update
    """

    private func replaceAndRelaunch(with newApp: URL, workDirectory: URL) throws {
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        if target.path.contains("/AppTranslocation/") {
            throw UpdateError.cannotReplace("Bismillah is running from a temporary location. Move it to your Applications folder, open it from there, and try again.")
        }
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.cannotReplace("Bismillah can't change files in \(parent.path). Download the new version from the release page instead.")
        }
        let script = workDirectory.appendingPathComponent("swap.sh")
        try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = ["-c", "/bin/sh \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" >/dev/null 2>&1 &",
                              script.path, String(ProcessInfo.processInfo.processIdentifier),
                              target.path, newApp.path, workDirectory.path]
        try launcher.run()
        NSApp.terminate(nil)
    }
}
