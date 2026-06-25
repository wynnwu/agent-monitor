import AppKit
import SwiftUI
import Observation
import AgentMonitorCore

/// Borderless panel that can still become key (so Esc/keys reach it), with a fixed
/// short slide duration.
final class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let service = AgentService()
    let prefs = HotKeyPreferences()

    private var statusItem: NSStatusItem!
    private var panel: DropdownPanel?
    private var hosting: NSView?
    private var hotKey: GlobalHotKey?
    private var escMonitor: Any?
    private var clickMonitor: Any?
    private var transcriptWindows: [String: NSWindow] = [:]
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // status-bar only, no Dock icon
        service.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right",
                                   accessibilityDescription: "Agent Monitor")
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
        }

        let hosting = NSHostingView(rootView: PopoverRootView(
            service: service,
            prefs: prefs,
            onOpen: { [weak self] session in self?.openTranscript(for: session) },
            onSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        ))
        let panel = DropdownPanel(contentRect: NSRect(x: 0, y: 0, width: 902, height: 420),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Glass: a vibrancy blur behind the (translucent) SwiftUI content, rounded at the bottom.
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner] // bottom corners
        blur.layer?.masksToBounds = true
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        panel.contentView = blur
        self.hosting = hosting
        self.panel = panel

        applyHotKey()
        observePrefs()
        observeBadge()
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if panel?.isVisible == true { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let panel, let hosting else { return }
        hosting.layoutSubtreeIfNeeded()
        var size = hosting.fittingSize
        if size.width < 100 || size.height < 100 { size = NSSize(width: 902, height: 420) } // fallback
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let x = screen.frame.midX - size.width / 2
        let topY = screen.visibleFrame.maxY                 // bottom of the menu bar
        let shown = NSRect(x: x, y: topY - size.height, width: size.width, height: size.height)

        service.popoverOpen = true
        Task { await service.refreshNow() } // fresh data immediately on open
        // No window shadow during the slide — it would sit at the full frame while the
        // content animates. Re-enable it once the panel settles.
        panel.hasShadow = false
        panel.setFrame(shown, display: true)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Slide the content down from behind the bar via explicit Core Animation
        // (window-frame animation is silently disabled under Reduce Motion).
        if let layer = panel.contentView?.layer {
            layer.removeAnimation(forKey: "slide")
            layer.transform = CATransform3DIdentity
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak panel] in
                MainActor.assumeIsolated { panel?.hasShadow = true }
            }
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = size.height   // start shifted up (clipped by the window), then drop in
            slide.toValue = 0
            slide.duration = 0.18
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(slide, forKey: "slide")
            CATransaction.commit()
        }
        // Esc closes while open.
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.closePopover(); return nil } // kVK_Escape
            return event
        }
        // Clicking in any other app dismisses (our own clicks aren't seen by the global monitor).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        service.popoverOpen = false
        if let escMonitor { NSEvent.removeMonitor(escMonitor); self.escMonitor = nil }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        guard let panel, panel.isVisible, let layer = panel.contentView?.layer else { panel?.orderOut(nil); return }
        panel.hasShadow = false // avoid the shadow lingering at the frame during slide-up
        // Slide the content back up behind the bar, then hide.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak panel] in
            MainActor.assumeIsolated { panel?.orderOut(nil) }
        }
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = 0
        slide.toValue = panel.frame.height
        slide.duration = 0.14
        slide.timingFunction = CAMediaTimingFunction(name: .easeIn)
        slide.fillMode = .forwards
        slide.isRemovedOnCompletion = false
        layer.add(slide, forKey: "slide")
        CATransaction.commit()
    }

    // MARK: - Transcript windows

    func openTranscript(for session: AgentSession) {
        closePopover()
        if let existing = transcriptWindows[session.sessionId] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let target = TranscriptTarget(
            sessionId: session.sessionId,
            folder: session.folder,
            parent: session.parentPath,
            branch: service.gitBranches[session.sessionId],
            kind: session.kind.rawValue,
            pid: session.pid,
            startedAt: session.startedAt
        )
        let host = NSHostingController(rootView: TranscriptView(target: target))
        let window = NSWindow(contentViewController: host)
        window.title = session.folder
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.appearance = NSAppearance(named: .darkAqua)
        window.setContentSize(NSSize(width: 480, height: 600))
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        transcriptWindows[session.sessionId] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        transcriptWindows = transcriptWindows.filter { $0.value !== closing }
        if settingsWindow === closing { settingsWindow = nil }
    }

    // MARK: - Settings & hotkey

    /// Register / unregister the global hotkey to match preferences.
    private func applyHotKey() {
        hotKey?.invalidate()
        hotKey = nil
        guard prefs.enabled else { return }
        hotKey = GlobalHotKey(keyCode: prefs.keyCode, modifiers: prefs.modifiers) { [weak self] in
            self?.togglePopover()
        }
    }

    private func observePrefs() {
        withObservationTracking {
            _ = prefs.enabled; _ = prefs.keyCode; _ = prefs.modifiers
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.applyHotKey()
                self?.observePrefs() // re-arm
            }
        }
    }

    func openSettings() {
        closePopover()
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsView(prefs: prefs))
        let window = NSWindow(contentViewController: host)
        window.title = "Agent Monitor Settings"
        window.styleMask = [.titled, .closable]
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Badge

    private func observeBadge() {
        withObservationTracking {
            _ = service.groups.activeBadge
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateBadge()
                self?.observeBadge() // re-arm for the next change
            }
        }
        updateBadge()
    }

    private func updateBadge() {
        guard let button = statusItem.button else { return }
        let badge = service.groups.activeBadge
        button.title = badge > 0 ? " \(badge)" : ""
        button.imagePosition = badge > 0 ? .imageLeading : .imageOnly
    }
}
