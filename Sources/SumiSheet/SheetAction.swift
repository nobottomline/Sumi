import UIKit
import Sumi

// SheetAction — one row inside a SumiSheet.
//
// Model object, not a view. The presentation layer materialises
// a `SheetActionRow` for each one with the appropriate visual
// style. Per-action `handler` fires on tap right before the
// sheet dismisses; the `SumiSheet.present(...)` async return
// also yields the picked action's index so callers can switch
// on result in a flat code path.

public struct SheetAction: Sendable {

    public enum Style: Sendable {
        case `default`     // normal weight, textPrimary
        case destructive   // semibold, danger red — irreversible ops
    }

    public let title: String
    public let subtitle: String?
    public let icon: UIImage?
    public let style: Style
    /// Pointer feedback policy for this action row or pill.
    public let pointerBehavior: SumiPointerBehavior
    public let handler: (@MainActor @Sendable () -> Void)?

    public init(
        title: String,
        subtitle: String? = nil,
        icon: UIImage? = nil,
        style: Style = .default,
        pointerBehavior: SumiPointerBehavior = .automatic,
        handler: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.style = style
        self.pointerBehavior = pointerBehavior
        self.handler = handler
    }
}
