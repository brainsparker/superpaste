import AppKit
import Combine
import Foundation
import Sparkle

/// Owns Sparkle's standard updater and publishes the small amount of update
/// state the rest of SuperPaste needs for badges and non-modal reminders.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    struct AvailableUpdate: Equatable {
        let version: String
        let releaseNotesURL: URL?
    }

    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isChecking = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyKeepsUpToDate = false
    @Published private(set) var lastCheckError: String?
    @Published private(set) var hasCompletedCheck = false

    private static let releasesPage = "https://github.com/brainsparker/superpaste/releases/latest"

    private var updaterController: SPUStandardUpdaterController!
    private var cancellables = Set<AnyCancellable>()

    private override init() {
        super.init()

        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String else { return }

        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController.startUpdater()
        bindUpdaterState()
    }

    private var updater: SPUUpdater {
        updaterController.updater
    }

    func checkForUpdates() {
        guard canCheckForUpdates, !isChecking else { return }
        isChecking = true
        lastCheckError = nil
        updater.checkForUpdates()
    }

    func installAvailableUpdate() {
        checkForUpdates()
    }

    func openReleaseNotes() {
        let url = availableUpdate?.releaseNotesURL ?? URL(string: Self.releasesPage)!
        NSWorkspace.shared.open(url)
    }

    func setAutomaticallyKeepsUpToDate(_ enabled: Bool) {
        guard updaterController != nil else { return }
        // Keep lightweight checks enabled even when the user prefers to approve
        // each install. The toggle controls background download + installation.
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = enabled
        automaticallyKeepsUpToDate = enabled
    }

    // MARK: - Sparkle delegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        availableUpdate = AvailableUpdate(
            version: item.displayVersionString,
            releaseNotesURL: item.releaseNotesURL
        )
        isChecking = false
        hasCompletedCheck = true
        lastCheckError = nil
        refreshDockBadge()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        availableUpdate = nil
        isChecking = false
        hasCompletedCheck = true
        lastCheckError = nil
        refreshDockBadge()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        isChecking = false

        let sparkleError = error as NSError
        if sparkleError.domain == SUSparkleErrorDomain,
           let code = SUError(rawValue: OSStatus(sparkleError.code)),
           code == .noUpdateError || code == .installationCanceledError {
            if code == .noUpdateError {
                hasCompletedCheck = true
            }
            lastCheckError = nil
            return
        }

        lastCheckError = error.localizedDescription
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        isChecking = false
    }

    func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if choice == .skip {
            availableUpdate = nil
            refreshDockBadge()
        }
    }

    // MARK: - State bridge

    private func bindUpdaterState() {
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] automaticallyDownloads in
                self?.automaticallyKeepsUpToDate = automaticallyDownloads
            }
            .store(in: &cancellables)
    }

    private func refreshDockBadge() {
        NSApp.dockTile.badgeLabel = availableUpdate == nil ? nil : "1"
    }
}
