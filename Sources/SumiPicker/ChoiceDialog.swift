import UIKit
import Sumi

// ChoiceDialog — modal centered dialog for picking from a
// list of options. Three flavours:
//
//   • single     — radio-button list, auto-dismiss + return
//                  on tap. Returns picked value or nil if
//                  user tapped outside.
//   • multi      — checkbox list with explicit "Done" button.
//                  Returns the final set, or nil if cancelled.
//   • tri-state  — three-cycle indicator (off / on / negated).
//                  Returns the final state map, or nil.
//
// Card-style modal (rounded blur on dimmer), spring scale-in
// animation, light haptic on present, selection haptic on
// pick. No Cancel button — tap-outside dimisses (returns nil).
//
// Built on async/await — call sites read like:
//
//   ```swift
//   let pick = await ChoiceDialog.presentSingle(
//       title: "Thumbnail quality",
//       choices: [
//           Choice(value: .small, title: "Small"),
//           Choice(value: .medium, title: "Medium"),
//           Choice(value: .large, title: "Large")
//       ],
//       selected: currentQuality
//   )
//   if let pick { currentQuality = pick }
//   ```

public enum ChoiceDialog {

    // MARK: - Single

    @MainActor
    public static func presentSingle<T: Hashable & Sendable>(
        title: String,
        message: String? = nil,
        choices: [Choice<T>],
        selected: T? = nil
    ) async -> T? {
        await withCheckedContinuation { continuation in
            guard let window = activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let controller = ChoiceDialogController(
                title: title,
                message: message,
                mode: .single(initial: selected),
                choices: choices
            ) { result in
                switch result {
                case .single(let value):
                    continuation.resume(returning: value as? T)
                default:
                    continuation.resume(returning: nil)
                }
            }
            controller.present(in: window)
        }
    }

    // MARK: - Multi

    @MainActor
    public static func presentMulti<T: Hashable & Sendable>(
        title: String,
        message: String? = nil,
        choices: [Choice<T>],
        selected: Set<T> = []
    ) async -> Set<T>? {
        await withCheckedContinuation { continuation in
            guard let window = activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let controller = ChoiceDialogController(
                title: title,
                message: message,
                mode: .multi(initial: Set(selected.map(AnyHashable.init))),
                choices: choices
            ) { result in
                switch result {
                case .multi(let raw):
                    let values = raw.compactMap { $0.base as? T }
                    continuation.resume(returning: Set(values))
                default:
                    continuation.resume(returning: nil)
                }
            }
            controller.present(in: window)
        }
    }

    // MARK: - Accessory + multi-with-accessory

    /// Trailing "create-new" affordance rendered inside a
    /// multi-select picker. Tapping it short-circuits the
    /// regular pick → Done flow and returns
    /// `MultiPickResult.accessory` to the caller, which is
    /// expected to run an external "create" sub-flow (e.g.
    /// presenting `Alert.presentText` for a new category name)
    /// and then re-present this picker with refreshed choices.
    ///
    /// Two display modes share the same value:
    ///
    ///   • Choices NON-EMPTY → accessory is the last row in
    ///     the picker, separated from real rows by a thicker
    ///     divider so the user reads it as "another action,
    ///     not a category".
    ///   • Choices EMPTY → the picker switches to an empty-
    ///     state layout: large icon + helper text + a primary-
    ///     CTA button bound to the accessory. No Done button
    ///     (nothing to confirm).
    public struct PickerAccessory: Sendable {

        /// Where the accessory affordance is rendered:
        ///
        ///   • `.row` (default) — appended to the choice list
        ///     as the last row, separated by a thicker divider.
        ///     For empty choice lists the picker switches to a
        ///     dedicated empty-state layout (large icon + helper
        ///     text + primary-CTA button bound to this accessory).
        ///     Reads as "another option in the list."
        ///
        ///   • `.footer` — rendered as a text button on the
        ///     LEADING side of the action footer, next to the
        ///     counter. Sits parallel to the trailing Done
        ///     button. Reads as "a management action, peer of
        ///     Done." Use when the accessory routes to a
        ///     manager screen (e.g. "+ New category" that
        ///     pushes CategoriesScreen) rather than performing
        ///     an inline create. Empty-state branch falls back
        ///     to `.row` behaviour for `.footer` accessories
        ///     too — when there are zero choices an empty-state
        ///     CTA still reads cleaner than a hidden footer
        ///     button on a blank surface.
        public enum Placement: Sendable {
            case row
            case footer
        }

        public let title: String
        public let systemImage: String?
        public let placement: Placement

        public init(
            title: String,
            systemImage: String? = nil,
            placement: Placement = .row
        ) {
            self.title = title
            self.systemImage = systemImage
            self.placement = placement
        }
    }

    /// Result of `presentMulti(...accessory:)`. Three outcomes:
    ///
    ///   • `.picked(set)` — user tapped Done. `set` is the
    ///     final selection (may be empty if user unticked
    ///     everything — that's a valid pick, distinct from
    ///     cancellation).
    ///   • `.accessory` — user tapped the "+New" affordance.
    ///     Caller handles the create flow, then optionally
    ///     re-presents the picker with refreshed choices.
    ///   • `.cancelled` — tap-outside dismiss. Caller does
    ///     nothing.
    public enum MultiPickResult<T: Hashable & Sendable>: Sendable {
        case picked(Set<T>)
        case accessory
        case cancelled
    }

    @MainActor
    public static func presentMulti<T: Hashable & Sendable>(
        title: String,
        message: String? = nil,
        choices: [Choice<T>],
        selected: Set<T> = [],
        accessory: PickerAccessory
    ) async -> MultiPickResult<T> {
        await withCheckedContinuation { continuation in
            guard let window = activeWindow() else {
                continuation.resume(returning: .cancelled)
                return
            }
            let controller = ChoiceDialogController(
                title: title,
                message: message,
                mode: .multi(initial: Set(selected.map(AnyHashable.init))),
                choices: choices,
                accessory: accessory
            ) { result in
                switch result {
                case .accessory:
                    continuation.resume(returning: .accessory)
                case .multi(let raw):
                    let values = raw.compactMap { $0.base as? T }
                    continuation.resume(returning: .picked(Set(values)))
                case .cancelled, .single, .triState:
                    continuation.resume(returning: .cancelled)
                }
            }
            controller.present(in: window)
        }
    }

    // MARK: - Tri-state

    @MainActor
    public static func presentTriState<T: Hashable & Sendable>(
        title: String,
        message: String? = nil,
        choices: [Choice<T>],
        states: [T: TriState] = [:]
    ) async -> [T: TriState]? {
        await withCheckedContinuation { continuation in
            guard let window = activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let initial: [AnyHashable: TriState] = states.reduce(into: [:]) { acc, kv in
                acc[AnyHashable(kv.key)] = kv.value
            }
            let controller = ChoiceDialogController(
                title: title,
                message: message,
                mode: .triState(initial: initial),
                choices: choices
            ) { result in
                switch result {
                case .triState(let raw):
                    var typed: [T: TriState] = [:]
                    for (k, v) in raw {
                        if let key = k.base as? T {
                            typed[key] = v
                        }
                    }
                    continuation.resume(returning: typed)
                default:
                    continuation.resume(returning: nil)
                }
            }
            controller.present(in: window)
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
    }
}

// MARK: - Internal mode + result types

@MainActor
enum DialogMode {
    case single(initial: AnyHashable?)
    case multi(initial: Set<AnyHashable>)
    case triState(initial: [AnyHashable: TriState])
}

@MainActor
enum DialogResult {
    case single(AnyHashable?)
    case multi(Set<AnyHashable>)
    case triState([AnyHashable: TriState])
    case accessory          // user tapped the accessory affordance
    case cancelled
}

// Type-erased choice used inside ChoiceDialogController.
// AnyHashable isn't Sendable, so we can't reuse the public
// `Choice<T: Hashable & Sendable>` here — define a parallel
// internal struct that drops the Sendable constraint. It
// only lives on the main actor anyway (the whole dialog is
// MainActor), so we don't actually need cross-actor safety.

@MainActor
struct AnyChoice {
    let value: AnyHashable
    let title: String
    let subtitle: String?
    let badge: String?
    let colorSwatch: UIColor?
    let previewImage: UIImage?
    let isDisabled: Bool
}

extension Choice {
    @MainActor
    func erased() -> AnyChoice {
        AnyChoice(
            value: AnyHashable(value),
            title: title,
            subtitle: subtitle,
            badge: badge,
            colorSwatch: colorSwatch?.color,
            previewImage: previewImage,
            isDisabled: isDisabled
        )
    }
}
