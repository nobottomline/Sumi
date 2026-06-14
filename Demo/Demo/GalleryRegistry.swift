import UIKit

// GalleryRegistry — canonical list of catalog entries.
//
// The App layer asks for `GalleryRegistry.allEntries` and hands
// it to `GalleryListViewController`. Adding the next component
// means appending to this array, nothing else.
//
// Why central registry instead of "each component module
// registers itself": Swift static initialisers on first access
// aren't deterministic when modules are linked statically into
// the same binary, and side-effecting `+load` ObjC tricks are
// hostile to debugging. An explicit list is the boring,
// trace-friendly choice.

@MainActor
public enum GalleryRegistry {
    public static var allEntries: [GalleryEntry] {
        [
            GalleryEntry(
                id: "alert",
                title: "Alert",
                subtitle: "Async/await modal dialog with horizontal / vertical layout and destructive style.",
                symbol: "exclamationmark.bubble",
                make: { AlertPlaygroundViewController() }
            ),
            GalleryEntry(
                id: "choice-dialog",
                title: "Choice Dialog",
                subtitle: "Single / multi / tri-state picker with animated indicators and colour swatches.",
                symbol: "checklist",
                make: { ChoiceDialogPlaygroundViewController() }
            ),
            GalleryEntry(
                id: "context-menu",
                title: "Context Menu",
                subtitle: "Long-press preview + actions list, blurred backdrop, auto-flip near screen edges.",
                symbol: "rectangle.stack.badge.plus",
                make: { ContextMenuPlaygroundViewController() }
            ),
            GalleryEntry(
                id: "dialog",
                title: "Dialog",
                subtitle: "Material-3 dialog — right-aligned text buttons, tap-outside dismiss, outlined floating-label field.",
                symbol: "text.bubble",
                make: { DialogPlaygroundViewController() }
            ),
            GalleryEntry(
                id: "menu",
                title: "Menu",
                subtitle: "Tap-anchored popover with smart positioning, shared action-row look.",
                symbol: "ellipsis.circle",
                make: { MenuPlaygroundViewController() }
            ),
            GalleryEntry(
                id: "sheet",
                title: "Sheet",
                subtitle: "Bottom action sheet — icon column, destructive style, swipe-down dismiss.",
                symbol: "square.and.pencil",
                make: { SheetPlaygroundViewController() }
            ),
            GalleryEntry(
                id: "stepper",
                title: "Stepper",
                subtitle: "Hero integer card — 72pt value, 64pt circular ± buttons, hold-to-repeat with haptics.",
                symbol: "plusminus.circle",
                make: { StepperPlaygroundViewController() }
            ),
            GalleryEntry(
                id: "toast",
                title: "Toast",
                subtitle: "Non-blocking transient overlay with queue + swipe + action button.",
                symbol: "bell.badge",
                make: { ToastPlaygroundViewController() }
            )
            // Future entries — each new component lands here as a
            // single line. Keep alphabetised by title.
        ]
    }
}
