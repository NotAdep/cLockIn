import AppKit

/// Where the notch is and how big it is, in screen coordinates.
struct NotchGeometry: Equatable {
    var screenFrame: CGRect
    var notchSize: CGSize
    /// False for a "virtual notch" drawn on a display without a camera housing.
    var hasHardwareNotch: Bool

    static let virtualNotchWidth: CGFloat = 110

    /// Used only if no display is attached at launch; replaced on the next screen change.
    static let fallback = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        notchSize: CGSize(width: virtualNotchWidth, height: 32),
        hasHardwareNotch: false
    )

    #if DEBUG
    /// A typical Mac without a notch: 24pt menu bar on a 1440×900 display.
    static let virtualPreview = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        notchSize: CGSize(width: virtualNotchWidth, height: 24),
        hasHardwareNotch: false
    )
    #endif

    /// The built-in notched display if there is one, otherwise the main display when `allowVirtual` is set.
    static func current(allowVirtual: Bool) -> NotchGeometry? {
        if let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return NotchGeometry(notchedScreen: screen)
        }
        guard allowVirtual, let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchGeometry(
            screenFrame: screen.frame,
            notchSize: CGSize(width: virtualNotchWidth, height: menuBarHeight > 0 ? menuBarHeight : 24),
            hasHardwareNotch: false
        )
    }

    private init(screenFrame: CGRect, notchSize: CGSize, hasHardwareNotch: Bool) {
        self.screenFrame = screenFrame
        self.notchSize = notchSize
        self.hasHardwareNotch = hasHardwareNotch
    }

    private init(notchedScreen screen: NSScreen) {
        var width: CGFloat = 185
        if let left = screen.auxiliaryTopLeftArea?.width, let right = screen.auxiliaryTopRightArea?.width {
            width = screen.frame.width - left - right
        }
        self.init(
            screenFrame: screen.frame,
            notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
            hasHardwareNotch: true
        )
    }
}
