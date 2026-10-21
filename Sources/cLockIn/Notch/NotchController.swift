import AppKit
import SwiftUI

/// Owns the notch panel: positions it, tracks the pointer and decides when it takes clicks.
@MainActor
final class NotchController {
    private let model: AppModel
    private let settings: AppSettings
    let viewModel: NotchViewModel

    private var panel: NotchPanel?
    private var eventMonitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var collapseTask: Task<Void, Never>?

    init(model: AppModel, settings: AppSettings) {
        self.model = model
        self.settings = settings
        viewModel = NotchViewModel(model: model, geometry: NotchGeometry.current(allowVirtual: true) ?? .fallback)
    }

    func start() {
        layoutPanel()
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { $0.layoutPanel() }
        observe(NotificationCenter.default, .notchPlacementSettingsChanged) { $0.layoutPanel() }
        observe(NotificationCenter.default, .hotKeySettingChanged) { $0.registerHotKey() }
        registerHotKey()
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.updateFullScreenState() }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.updateFullScreenState() }

        let moveEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: moveEvents, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) { eventMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: moveEvents, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pointerMoved() }
            return event
        }) { eventMonitors.append(local) }
        // Global click events only come from other apps' windows, so any of them is a click outside the panel.
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }) { eventMonitors.append(outside) }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) == true } ? nil : event
        }) { eventMonitors.append(scroll) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.viewModel.handleKey(event) == true } ? nil : event
        }) { eventMonitors.append(keys) }

        updateFullScreenState()
        trackShapeChanges()
        #if DEBUG
        AnimationProbe.shared.install(controller: self)
        #endif
        trackKeyboardNeed()
    }

    /// The global shortcut toggles the panel and gives it the keyboard until it closes.
    private func registerHotKey() {
        HotKeyService.shared.register(settings.hotKey) { [weak self] in
            self?.toggleFromKeyboard()
        }
    }

    private func toggleFromKeyboard() {
        if viewModel.isExpanded {
            collapse()
            return
        }
        layoutPanel()
        viewModel.expand()
        viewModel.isKeyboardSession = true
        refreshHitTesting()
    }

    /// Opens the panel from the menu bar. It closes again a few seconds later if the pointer never arrives.
    func showExpanded() {
        viewModel.expand()
        refreshHitTesting()
        scheduleCollapse(after: .seconds(4))
    }

    #if DEBUG
    var debugContentView: NSView? { panel?.contentView }

    func debugOpen(tab: ExpandedTab) {
        viewModel.tab = tab
        viewModel.isExpanded = true
    }

    func debugClose() {
        collapse()
    }
    #endif

    // MARK: Layout

    /// Where the island should be right now, given the display setting.
    private var desiredGeometry: NotchGeometry? {
        let allowVirtual = settings.showOnScreensWithoutNotch
        switch settings.notchDisplay {
        case .builtIn:
            return NotchGeometry.current(allowVirtual: allowVirtual)
        case .pointer:
            // Prefer the display you're on; if it can't show the island, use the built-in one.
            return NotchGeometry.pointerScreen.flatMap { NotchGeometry.on($0, allowVirtual: allowVirtual) }
                ?? NotchGeometry.current(allowVirtual: allowVirtual)
        }
    }

    private func layoutPanel() {
        guard let geometry = desiredGeometry else {
            panel?.orderOut(nil)
            return
        }
        viewModel.geometry = geometry

        // Big enough for the largest state plus room for its shadow; most of it is transparent and click-through.
        let expanded = NotchViewModel.expandedBodySize(for: geometry.notchSize)
        let size = CGSize(width: expanded.width + 120, height: expanded.height + 60)
        let frame = CGRect(
            x: geometry.screenFrame.midX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )

        let panel = self.panel ?? makePanel(frame: frame)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        refreshHitTesting()
    }

    private func makePanel(frame: CGRect) -> NotchPanel {
        let panel = NotchPanel(contentRect: frame)
        let hostingView = NotchHostingView(rootView: NotchRootView(viewModel: viewModel))
        hostingView.sizingOptions = []
        hostingView.frame = CGRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        self.panel = panel
        return panel
    }

    // MARK: Pointer

    private func pointerMoved() {
        // Hop to the display the pointer moved to, unless the panel is open there.
        if settings.notchDisplay == .pointer, !viewModel.isExpanded,
           let screen = NotchGeometry.pointerScreen, screen.frame != viewModel.geometry.screenFrame {
            layoutPanel()
        }
        let inside = viewModel.hitRect.contains(NSEvent.mouseLocation)
        if inside != viewModel.isHovering {
            viewModel.isHovering = inside
            if inside, settings.hapticsEnabled {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        panel?.ignoresMouseEvents = !inside

        // While typing or using the keyboard, drifting off the panel shouldn't close it.
        guard viewModel.isExpanded, !viewModel.wantsKeyboard else { return }
        if inside {
            collapseTask?.cancel()
            collapseTask = nil
        } else if collapseTask == nil {
            scheduleCollapse(after: .milliseconds(700))
        }
    }

    /// The shape can grow or shrink without the pointer moving (an alert arrives, a timer starts),
    /// so re-check whether the pointer is over it whenever its size changes.
    private func trackShapeChanges() {
        withObservationTracking {
            _ = viewModel.hitRect
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.pointerMoved()
                self?.trackShapeChanges()
            }
        }
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let panel, event.window === panel, let content = panel.contentView else { return false }
        // SwiftUI's coordinates start at the top-left of the panel; AppKit's start at the bottom-left.
        let location = event.locationInWindow
        let point = CGPoint(x: location.x, y: content.bounds.height - location.y)
        return viewModel.handleScroll(event, at: point)
    }

    /// The panel only takes keyboard focus while a duration is being typed, then hands it back.
    private func trackKeyboardNeed() {
        withObservationTracking {
            _ = viewModel.wantsKeyboard
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateKeyboardFocus()
                self?.trackKeyboardNeed()
            }
        }
    }

    private func updateKeyboardFocus() {
        guard let panel else { return }
        let wantsKeyboard = viewModel.wantsKeyboard
        guard wantsKeyboard != panel.allowsKey else { return }
        panel.allowsKey = wantsKeyboard
        if wantsKeyboard {
            panel.makeKey()
        } else if panel.isKeyWindow {
            // Re-ordering a key panel that can no longer be key returns focus to the app you were using.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private func clickedOutside() {
        guard viewModel.isExpanded else { return }
        collapse()
    }

    private func scheduleCollapse(after delay: Duration) {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.collapse()
        }
    }

    private func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        viewModel.collapse()
        refreshHitTesting()
    }

    /// Re-checks the pointer after the shape changes size without the mouse moving.
    private func refreshHitTesting() {
        collapseTask?.cancel()
        collapseTask = nil
        pointerMoved()
    }

    // MARK: Full screen

    /// Hides the live activity while a full-screen app is in front of the notched display.
    private func updateFullScreenState() {
        viewModel.isSuppressed = settings.hideInFullScreen && frontmostAppIsFullScreen()
        // Spaces animate when switching, so look again once the transition has settled.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self else { return }
            viewModel.isSuppressed = settings.hideInFullScreen && frontmostAppIsFullScreen()
        }
    }

    private func frontmostAppIsFullScreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        let screenSize = viewModel.geometry.screenFrame.size
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return bounds.size == screenSize
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping (NotchController) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }
}
