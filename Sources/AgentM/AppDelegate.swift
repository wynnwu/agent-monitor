import AppKit
import SwiftUI
import Observation
import AgentMCore

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
    private var shadowHost: NSView?
    private var glass: NSView?
    private var hotKey: GlobalHotKey?
    private let panelMargin: CGFloat = 30 // room around the content for the soft shadow
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
                                   accessibilityDescription: "Agent M")
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
        panel.hasShadow = false // we draw our own fadeable, borderless shadow on the content
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Glass: a vibrancy blur behind the translucent SwiftUI content. NSVisualEffectView
        // ignores layer cornerRadius, so shape its bottom corners with a mask image.
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        blur.maskImage = Self.bottomRoundedMask(radius: 14)
        blur.autoresizingMask = [.width, .height]
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)

        // shadowHost carries a soft drop shadow we can fade in/out and slide.
        let shadowHost = NSView()
        shadowHost.wantsLayer = true
        shadowHost.layer?.shadowColor = NSColor.black.cgColor
        shadowHost.layer?.shadowOffset = CGSize(width: 0, height: -6)
        shadowHost.layer?.shadowRadius = 18
        shadowHost.layer?.shadowOpacity = 0
        shadowHost.addSubview(blur)

        let container = NSView()
        container.addSubview(shadowHost)
        panel.contentView = container

        self.hosting = hosting
        self.glass = blur
        self.shadowHost = shadowHost
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
        guard let panel, let hosting, let shadowHost, let glass else { return }
        hosting.layoutSubtreeIfNeeded()
        var content = hosting.fittingSize
        if content.width < 100 || content.height < 100 { content = NSSize(width: 902, height: 420) } // fallback
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let m = panelMargin
        let winW = content.width + 2 * m
        let winH = content.height + m                 // top flush at the bar; margin on sides + bottom
        let x = screen.frame.midX - winW / 2
        let topY = screen.visibleFrame.maxY + 1 // overlap the menu bar slightly to avoid a hairline gap
        let winFrame = NSRect(x: x, y: topY - winH, width: winW, height: winH)

        service.popoverOpen = true
        Task { await service.refreshNow() } // fresh data immediately on open
        panel.setFrame(winFrame, display: true)
        shadowHost.frame = NSRect(x: m, y: m, width: content.width, height: content.height)
        glass.frame = shadowHost.bounds
        hosting.frame = glass.bounds
        shadowHost.layer?.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: content),
                                              cornerWidth: 14, cornerHeight: 14, transform: nil)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Slide the content down from behind the bar and fade the shadow in. Explicit Core
        // Animation — window-frame animation is silently disabled under Reduce Motion.
        if let layer = shadowHost.layer {
            layer.removeAnimation(forKey: "slide"); layer.removeAnimation(forKey: "shadow")
            layer.transform = CATransform3DIdentity
            layer.shadowOpacity = 0.5
            let slide = CABasicAnimation(keyPath: "transform.translation.y")
            slide.fromValue = content.height
            slide.toValue = 0
            slide.duration = 0.18
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            let fade = CABasicAnimation(keyPath: "shadowOpacity")
            fade.fromValue = 0
            fade.toValue = 0.5
            fade.duration = 0.26
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(slide, forKey: "slide")
            layer.add(fade, forKey: "shadow")
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
        guard let panel, panel.isVisible, let shadowHost, let layer = shadowHost.layer else { panel?.orderOut(nil); return }
        let h = shadowHost.frame.height
        // Slide the content back up behind the bar and fade the shadow out, then hide.
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak panel] in
            MainActor.assumeIsolated { panel?.orderOut(nil) }
        }
        layer.transform = CATransform3DMakeTranslation(0, h, 0)
        layer.shadowOpacity = 0
        let slide = CABasicAnimation(keyPath: "transform.translation.y")
        slide.fromValue = 0
        slide.toValue = h
        slide.duration = 0.14
        slide.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let fade = CABasicAnimation(keyPath: "shadowOpacity")
        fade.fromValue = 0.5
        fade.toValue = 0
        fade.duration = 0.12
        layer.add(slide, forKey: "slide")
        layer.add(fade, forKey: "shadow")
        CATransaction.commit()
    }

    /// A black mask whose bottom corners are rounded and top corners square (for the glass).
    static func bottomRoundedMask(radius r: CGFloat) -> NSImage {
        let d = r * 2 + 1
        let image = NSImage(size: NSSize(width: d, height: d))
        image.lockFocus()
        NSColor.black.setFill()
        // Draw a rounded rect extending above the canvas so only the bottom corners round.
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: d, height: d + r), xRadius: r, yRadius: r).fill()
        image.unlockFocus()
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
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
        window.title = "Agent M Settings"
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
