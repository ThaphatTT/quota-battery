import AppKit
import ApplicationServices
import Combine
import os

struct QuotaOverlayAnchor: Equatable {
    let frame: CGRect
    let windowID: CFHashCode
    let surface: String
}

struct QuotaOverlayGate {
    enum Decision: Equatable { case hidden, confirming, show, keepShowing }

    private var candidate: QuotaOverlayAnchor?
    private var presented: QuotaOverlayAnchor?

    mutating func reset() {
        candidate = nil
        presented = nil
    }

    mutating func check(_ anchor: QuotaOverlayAnchor?) -> Decision {
        guard let anchor else {
            reset()
            return .hidden
        }
        if presented == anchor { return .keepShowing }
        if candidate == anchor {
            presented = anchor
            candidate = nil
            return .show
        }
        presented = nil
        candidate = anchor
        return .confirming
    }
}

struct QuotaOverlayLocation {
    let window: AXUIElement
    let anchor: QuotaOverlayAnchor

    init(window: AXUIElement, frame: CGRect, surface: String) {
        self.window = window
        self.anchor = QuotaOverlayAnchor(frame: frame, windowID: CFHash(window), surface: surface)
    }
}

@MainActor
final class QuotaOverlayTracker {
    private static let logger = Logger(subsystem: "local.aiusage", category: "quota-overlay")
    private let panel: NSPanel
    private let visibility: QuotaOverlayVisibility
    private let bundleID: String
    private let isEnabled: () -> Bool
    private let locate: (pid_t) -> QuotaOverlayLocation?
    private let closePopover: () -> Void
    private var gate = QuotaOverlayGate()
    private var revision: UInt64 = 0
    private var presentation: UInt64 = 0
    private var reading = false
    private var timer: Timer?
    private var confirmTask: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []
    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedWindow: AXUIElement?
    private var lastStatus: String?
    private static let windowEvents = [
        kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification
    ]

    init(panel: NSPanel, visibility: QuotaOverlayVisibility, bundleID: String, isEnabled: @escaping () -> Bool,
         locate: @escaping (pid_t) -> QuotaOverlayLocation?, closePopover: @escaping () -> Void) {
        self.panel = panel
        self.visibility = visibility
        self.bundleID = bundleID
        self.isEnabled = isEnabled
        self.locate = locate
        self.closePopover = closePopover

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.activeSpaceDidChangeNotification))
            .sink { [weak self] _ in Task { @MainActor in self?.contextChanged() } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in Task { @MainActor in self?.contextChanged() } }
            .store(in: &subscriptions)
        contextChanged()
    }

    deinit {
        timer?.invalidate()
        confirmTask?.cancel()
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }

    private var targetPID: pid_t? {
        guard isEnabled(), let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == bundleID else { return nil }
        return app.processIdentifier
    }

    func contextChanged() {
        revision &+= 1
        gate.reset()
        confirmTask?.cancel()
        hide()
        guard let pid = targetPID else {
            report("inactive")
            timer?.invalidate()
            timer = nil
            stopObserving()
            return
        }
        if timer == nil {
            let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.probe() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        if observedPID != pid { stopObserving() }
        probe()
    }

    private func probe() {
        guard let pid = targetPID else {
            gate.reset()
            hide()
            return
        }
        guard AXIsProcessTrusted() else {
            report("waiting for Accessibility")
            gate.reset()
            hide()
            return
        }
        guard !reading else { return }
        reading = true
        let check = revision
        let locate = self.locate
        Task { [weak self] in
            let location = await Task.detached(priority: .utility) { locate(pid) }.value
            guard let self else { return }
            reading = false
            guard check == revision, targetPID == pid else {
                if targetPID != nil { probe() }
                return
            }
            observe(pid: pid, window: location?.window)
            let frame = location.flatMap { screenFrame(for: $0.anchor.frame) }
            switch gate.check(frame == nil ? nil : location?.anchor) {
            case .hidden:
                report(location == nil ? "anchor unavailable" : "anchor offscreen")
                hide()
            case .confirming:
                report("confirming anchor")
                hide()
                confirmTask?.cancel()
                confirmTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(110)) } catch { return }
                    self?.probe()
                }
            case .show:
                report("presenting overlay")
                if let frame { show(frame: frame, pid: pid, revision: check) }
            case .keepShowing:
                break
            }
        }
    }

    private func report(_ status: String) {
        guard status != lastStatus else { return }
        lastStatus = status
        Self.logger.notice("\(self.bundleID, privacy: .public): \(status, privacy: .public)")
    }

    private func screenFrame(for anchor: CGRect) -> CGRect? {
        let screens = NSScreen.screens
        guard let first = screens.first else { return nil }
        let frame = CGRect(x: anchor.minX, y: first.frame.maxY - anchor.maxY,
                           width: anchor.width, height: anchor.height)
        return screens.contains { $0.frame.contains(frame) } ? frame : nil
    }

    private func show(frame: CGRect, pid: pid_t, revision check: UInt64) {
        guard targetPID == pid, revision == check else { return }
        panel.alphaValue = 0
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        presentation &+= 1
        visibility.presentation = presentation
        DispatchQueue.main.async { [weak self] in
            guard let self, revision == check, targetPID == pid, visibility.presentation != nil else { return }
            panel.alphaValue = 1
        }
    }

    private func hide() {
        guard panel.isVisible || visibility.presentation != nil else { return }
        panel.alphaValue = 0
        closePopover()
        panel.orderOut(nil)
        visibility.presentation = nil
    }

    private func observe(pid: pid_t, window: AXUIElement?) {
        if observer == nil {
            var result: AXObserver?
            let status = AXObserverCreate(pid, { _, _, _, context in
                guard let context else { return }
                let tracker = Unmanaged<QuotaOverlayTracker>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { tracker.contextChanged() }
            }, &result)
            guard status == .success, let result else { return }
            observer = result
            observedPID = pid
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result), .commonModes)
            let app = AXUIElementCreateApplication(pid)
            for event in [kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
                AXObserverAddNotification(result, app, event as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        guard let observer, let window else { return }
        if let observedWindow, CFEqual(observedWindow, window) { return }
        if let observedWindow {
            for event in Self.windowEvents {
                AXObserverRemoveNotification(observer, observedWindow, event as CFString)
            }
        }
        observedWindow = window
        for event in Self.windowEvents {
            AXObserverAddNotification(observer, window, event as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
    }

    private func stopObserving() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil
        observedPID = nil
        observedWindow = nil
    }
}
