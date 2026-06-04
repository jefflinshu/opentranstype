import AppKit

@MainActor
enum WindowChrome {
    static func placeTrafficLightsInsidePanel(_ window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let buttonContainer = closeButton.superview else {
            return
        }

        let buttons = [
            window.standardWindowButton(.closeButton),
            window.standardWindowButton(.miniaturizeButton),
            window.standardWindowButton(.zoomButton)
        ].compactMap { $0 }

        let leftInset: CGFloat = 18
        let topInset: CGFloat = 14
        let spacing: CGFloat = 8
        var x = leftInset

        for button in buttons {
            button.setFrameOrigin(CGPoint(
                x: x,
                y: buttonContainer.bounds.height - button.frame.height - topInset
            ))
            x += button.frame.width + spacing
        }
    }
}
