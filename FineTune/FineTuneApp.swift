// FineTune/FineTuneApp.swift
import SwiftUI
import UserNotifications
import FluidMenuBarExtra
import AppKit
import os

private let logger = Logger(subsystem: "com.finetuneapp.FineTune", category: "App")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var audioEngine: AudioEngine?
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let audioEngine = audioEngine else {
            return
        }
        let urlHandler = URLHandler(audioEngine: audioEngine)

        for url in urls {
            urlHandler.handleURL(url)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}

@MainActor
final class MenuBarSpeakerIconUpdater {
    private weak var deviceVolumeMonitor: DeviceVolumeMonitor?
    private var timer: Timer?
    private var lastSymbolName: String?
    private let statusItemTitle = "FineTune"
    private weak var statusItemButton: NSStatusBarButton?

    func start(deviceVolumeMonitor: DeviceVolumeMonitor) {
        self.deviceVolumeMonitor = deviceVolumeMonitor
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let deviceVolumeMonitor else { return }
        let defaultDeviceID = deviceVolumeMonitor.defaultDeviceID
        let volume = deviceVolumeMonitor.volumes[defaultDeviceID] ?? 1.0
        let isMuted = deviceVolumeMonitor.muteStates[defaultDeviceID] ?? false
        let symbol = SpeakerVolumeIcon.symbolName(
            levelFraction: Double(volume),
            isMuted: isMuted
        )

        guard symbol != lastSymbolName else { return }
        if updateStatusButtonImage(symbolName: symbol) {
            lastSymbolName = symbol
        }
    }

    @discardableResult
    private func updateStatusButtonImage(symbolName: String) -> Bool {
        let button: NSStatusBarButton
        if let cached = statusItemButton {
            button = cached
        } else {
            guard let discovered = findFineTuneStatusButton() else { return false }
            statusItemButton = discovered
            button = discovered
        }

        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: statusItemTitle) else {
            return false
        }
        image.isTemplate = true

        DispatchQueue.main.async {
            button.image = image
        }
        return true
    }

    private func findFineTuneStatusButton() -> NSStatusBarButton? {
        if let statusItems = NSStatusBar.system.value(forKey: "_statusItems") as? [NSStatusItem] {
            for item in statusItems {
                guard let button = item.button else { continue }
                if isFineTuneStatusButton(button) {
                    return button
                }
            }
        }

        for window in NSApplication.shared.windows {
            guard let root = window.contentView else { continue }
            if let found = findStatusButton(in: root) {
                return found
            }
        }

        return nil
    }

    private func isFineTuneStatusButton(_ button: NSStatusBarButton) -> Bool {
        button.accessibilityTitle() == statusItemTitle ||
        button.toolTip == statusItemTitle ||
        button.title == statusItemTitle
    }

    private func findStatusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton, isFineTuneStatusButton(button) {
            return button
        }

        for subview in view.subviews {
            if let found = findStatusButton(in: subview) {
                return found
            }
        }

        return nil
    }
}

@main
struct FineTuneApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var audioEngine: AudioEngine
    @StateObject private var updateManager = UpdateManager()
    @State private var showMenuBarExtra = true
    private let menuBarSpeakerIconUpdater: MenuBarSpeakerIconUpdater?

    /// Icon style captured at launch (doesn't change during runtime)
    private let launchIconStyle: MenuBarIconStyle

    /// Icon name captured at launch for SF Symbols
    private let launchSystemImageName: String?

    /// Icon name captured at launch for asset catalog
    private let launchAssetImageName: String?

    var body: some Scene {
        // Use dual scenes with captured icon names - only one is visible based on icon type
        FluidMenuBarExtra("FineTune", systemImage: launchSystemImageName ?? "speaker.wave.2", isInserted: systemIconBinding) {
            menuBarContent
        }

        FluidMenuBarExtra("FineTune", image: launchAssetImageName ?? "MenuBarIcon", isInserted: assetIconBinding) {
            menuBarContent
        }
        .commands {
            CommandGroup(replacing: .appSettings) { }
        }
    }

    /// Show SF Symbol menu bar when launch style is a system symbol
    private var systemIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarExtra && launchIconStyle.isSystemSymbol },
            set: { showMenuBarExtra = $0 }
        )
    }

    /// Show asset catalog menu bar when launch style is not a system symbol
    private var assetIconBinding: Binding<Bool> {
        Binding(
            get: { showMenuBarExtra && !launchIconStyle.isSystemSymbol },
            set: { showMenuBarExtra = $0 }
        )
    }

    @ViewBuilder
    private var menuBarContent: some View {
        // Safe: AudioEngine always creates a concrete DeviceVolumeMonitor in production.
        // The protocol abstraction exists for testability of AudioEngine, not this view.
        MenuBarPopupView(
            audioEngine: audioEngine,
            deviceVolumeMonitor: audioEngine.deviceVolumeMonitor as! DeviceVolumeMonitor,
            updateManager: updateManager,
            launchIconStyle: launchIconStyle,
            permission: audioEngine.permission
        )
    }

    init() {
        // Install crash handler to clean up aggregate devices on abnormal exit
        CrashGuard.install()
        // Destroy any orphaned aggregate devices from previous crashes
        OrphanedTapCleanup.destroyOrphanedDevices()

        let settings = SettingsManager()
        let profileManager = AutoEQProfileManager()
        let permission = AudioRecordingPermission()
        let engine = AudioEngine(permission: permission, settingsManager: settings, autoEQProfileManager: profileManager)
        _audioEngine = State(initialValue: engine)

        // Pass engine to AppDelegate
        _appDelegate.wrappedValue.audioEngine = engine

        if permission.status == .unknown {
            permission.request()
        }

        // Capture icon style at launch - requires restart to change
        let iconStyle = settings.appSettings.menuBarIconStyle
        launchIconStyle = iconStyle

        // Capture the correct icon name based on type
        if iconStyle.isSystemSymbol {
            launchSystemImageName = iconStyle.iconName
            launchAssetImageName = nil
        } else {
            launchSystemImageName = nil
            launchAssetImageName = iconStyle.iconName
        }

        // DeviceVolumeMonitor is now created and started inside AudioEngine
        // This ensures proper initialization order: deviceMonitor.start() -> deviceVolumeMonitor.start()

        // Set delegate before requesting authorization so willPresent is called
        UNUserNotificationCenter.current().delegate = _appDelegate.wrappedValue

        // Request notification authorization (for device disconnect alerts)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                logger.error("Notification authorization error: \(error.localizedDescription)")
            }
            // If not granted, notifications will silently not appear - acceptable behavior
        }

        // Flush settings on app termination to prevent data loss from debounced saves
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [settings] _ in
            settings.flushSync()
        }

        if iconStyle == .speaker,
           let deviceVolumeMonitor = engine.deviceVolumeMonitor as? DeviceVolumeMonitor {
            let updater = MenuBarSpeakerIconUpdater()
            updater.start(deviceVolumeMonitor: deviceVolumeMonitor)
            menuBarSpeakerIconUpdater = updater
        } else {
            menuBarSpeakerIconUpdater = nil
        }
    }
}
