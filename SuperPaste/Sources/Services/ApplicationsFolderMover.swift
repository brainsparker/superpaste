import AppKit
import Darwin

/// Offers to move SuperPaste into /Applications when it's launched from
/// somewhere else (the mounted DMG, Downloads, or a translocated copy).
///
/// Running outside Applications breaks the things SuperPaste depends on:
/// macOS runs quarantined apps from a randomized read-only path ("App
/// Translocation"), so permission grants and relaunches don't stick, and
/// Sparkle can't update the app in place.
enum ApplicationsFolderMover {
    private static let suppressKey = "suppressMoveToApplicationsPrompt"
    private static let releaseBundleID = "com.superpaste.app"
    /// setupApp runs on every main-window appearance; ask once per launch.
    private static var hasOffered = false

    static func offerMoveIfNeeded() {
        guard !hasOffered else { return }
        hasOffered = true
        // Dev builds deliberately run from the repo.
        guard Bundle.main.bundleIdentifier == releaseBundleID else { return }
        guard !UserDefaults.standard.bool(forKey: suppressKey) else { return }

        let running = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard !isInApplicationsFolder(running) else { return }

        // For a translocated launch, `running` is the randomized mirror; the
        // copy the user actually has lives at the original path.
        let source = originalURL(forTranslocated: running) ?? running
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(running.lastPathComponent)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Move SuperPaste to your Applications folder?"
        alert.informativeText = "SuperPaste needs to run from Applications so its permissions and updates keep working. It'll move itself and reopen."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don't ask again"

        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(true, forKey: suppressKey)
        }
        guard response == .alertFirstButtonReturn else { return }

        do {
            try install(from: running, to: destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = "Couldn't move SuperPaste"
            failure.informativeText = "Drag SuperPaste into your Applications folder in Finder, then open it from there.\n\n\(error.localizedDescription)"
            failure.runModal()
            return
        }

        // A copy on the DMG can't be deleted, but the DMG can be ejected once
        // we've quit. A copy elsewhere (e.g. Downloads) goes to the Trash.
        let volume = mountedVolume(containing: source)
        if volume == nil {
            try? FileManager.default.trashItem(at: source, resultingItemURL: nil)
        }

        AppRelauncher.reopenAfterExit(appPath: destination.path, detachVolume: volume)
        NSApp.terminate(nil)
    }

    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.path
        let roots = ["/Applications/", NSHomeDirectory() + "/Applications/"]
        return roots.contains { path.hasPrefix($0) } && !path.contains("/AppTranslocation/")
    }

    private static func install(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            // An older copy; Trash it rather than delete so it's recoverable.
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        // ditto preserves the bundle's symlinks and code signature exactly.
        try run("/usr/bin/ditto", [source.path, destination.path])
        // Without this, the moved copy is still quarantined and macOS would
        // translocate it again on the next launch.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])
    }

    /// "/Volumes/SuperPaste" for an app on a mounted disk image, else nil.
    private static func mountedVolume(containing url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "Volumes" else { return nil }
        return "/Volumes/\(parts[1])"
    }

    /// Resolves a translocated app back to where it really lives. The Security
    /// functions are SPI-adjacent, so look them up at runtime (as LetsMove and
    /// Sparkle do) and fall back gracefully if they ever disappear.
    private static func originalURL(forTranslocated url: URL) -> URL? {
        guard url.path.contains("/AppTranslocation/"),
              let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else {
            return nil
        }
        typealias CreateOriginal = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let create = unsafeBitCast(symbol, to: CreateOriginal.self)
        return create(url as CFURL, nil)?.takeRetainedValue() as URL?
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw NSError(domain: "SuperPaste", code: Int(task.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: tool).lastPathComponent) exited with status \(task.terminationStatus).",
            ])
        }
    }
}

enum AppRelauncher {
    /// Opens the app at `appPath` once this process has exited, optionally
    /// ejecting a disk image first. Waiting matters: launching while this copy
    /// is still alive trips single-instance checks, and plain `open` (no -n)
    /// just activates the app if something (e.g. macOS's own "Quit & Reopen")
    /// already relaunched it, so there's never a duplicate.
    @discardableResult
    static func reopenAfterExit(appPath: String = Bundle.main.bundleURL.path, detachVolume: String? = nil) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            """
            while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
            sleep 0.5
            if [ -n "$3" ]; then /usr/bin/hdiutil detach "$3" -quiet || true; fi
            /usr/bin/open "$2"
            """,
            "sh",
            String(ProcessInfo.processInfo.processIdentifier),
            appPath,
            detachVolume ?? "",
        ]
        do {
            try task.run()
            return true
        } catch {
            return false
        }
    }
}
