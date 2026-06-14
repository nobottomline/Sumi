import UIKit
import Sumi

// SumiAlert — custom modal dialog with async/await API.
//
// File map for this module (all in the same `SumiAlert` SPM
// target, just split for navigation):
//
//   • `Alert.swift`              — this file: public API enum,
//                                  configs/result types, entry
//                                  points (`present`, `presentText`).
//   • `AlertChrome.swift`        — shared internal visuals:
//                                  AlertButton, AlertButtonsView,
//                                  icon helper.
//   • `AlertPresentations.swift` — presentation classes that
//                                  build the card hierarchy and
//                                  drive lifecycle (attach,
//                                  animate in/out, complete).
//
// Modern equivalent of `UIAlertController(style: .alert)` with
// our own visual identity (centered card on dimmed backdrop)
// and a structured Swift API:
//
//   ```swift
//   let pick = await Alert.present(
//       title: "Delete chapter?",
//       message: "Removes the downloaded file but keeps your reading progress.",
//       actions: [
//           .init(title: "Cancel", style: .cancel),
//           .init(title: "Delete", style: .destructive)
//       ]
//   )
//   if pick?.style == .destructive { ... }
//   ```
//
// Why async/await over completion closures:
//   • No "did the user cancel" closure parameter to forget.
//   • Composable with other async work (`if await confirm() { await delete() }`).
//   • Easier to read in a long flow.
//
// Layout rules:
//   • Cancel action is always rendered LAST and visually
//     separated (bold or distinct).
//   • Destructive actions colour the title in `Color.danger`.
//   • Default actions use `Color.accent` for the primary
//     (last non-cancel) and `Color.textPrimary` for the rest.
//   • Two actions → horizontal layout (matches iOS).
//   • 3+ actions → vertical stack (matches iOS).

public enum Alert {

    public struct Action: Sendable {

        public enum Style: Sendable {
            case `default`
            case primary       // emphasised (bold) — usually the affirmative choice
            case destructive
            case cancel
        }

        public let title: String
        public let style: Style
        /// Optional async work to run when the user picks this
        /// action. If non-nil, the alert KEEPS its presentation
        /// while the handler runs: the button replaces its
        /// label with a spinner, other buttons are dimmed, and
        /// touch on the alert is gated. On success the alert
        /// dismisses normally; on throw, the spinner reverts to
        /// the label, an inline error message appears below
        /// the message, and the user can try a different
        /// action.
        ///
        /// Use cases: "Save" that validates against a server,
        /// "Add repository" that fetches metadata first,
        /// "Sign in" that POSTs credentials. Available on
        /// `Alert.present(...)` only — text/form/stepper/etc.
        /// variants are simpler shapes; the async pattern adds
        /// disproportionate complexity for those.
        public let asyncHandler: (@MainActor @Sendable () async throws -> Void)?

        public init(title: String, style: Style = .default) {
            self.title = title
            self.style = style
            self.asyncHandler = nil
        }

        public init(
            title: String,
            style: Style = .default,
            asyncHandler: @escaping @MainActor @Sendable () async throws -> Void
        ) {
            self.title = title
            self.style = style
            self.asyncHandler = asyncHandler
        }
    }

    /// Present an alert with title + body + actions.
    ///
    /// `message` accepts a `Sumi.RichText` value — pass a string
    /// literal (treated as `.plain`) for plain text, or
    /// `.markdown("...")` for inline `**bold**`, `*italic*`,
    /// `` `code` ``, and `[text](url)`. Link taps fire
    /// `linkHandler`.
    ///
    /// `customContent` injects an arbitrary view between the
    /// message and the action row. Use for tables (`SumiTableView`),
    /// previews, charts — anything tabular or visual that doesn't
    /// fit the plain-text message line. The view's intrinsic size
    /// drives its rendered height.
    @MainActor
    public static func present(
        title: String?,
        message: Sumi.RichText?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        customContent: UIView? = nil,
        linkHandler: ((URL) -> Void)? = nil,
        actions: [Action]
    ) async -> Action? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = AlertPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                customContent: customContent,
                linkHandler: linkHandler,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Text input variant
    //
    // Canonical replacement for `UIAlertController.addTextField`.
    // Use cases: "Add repository URL", "Rename chapter", "New
    // category name" — anywhere you need a single-line input
    // attached to a confirm/cancel choice.
    //
    // For LIST selection ("pick a language") use `SumiPicker`
    // instead — alerts are for decisions, not data browsing.

    public struct TextFieldConfig: Sendable {
        public let placeholder: String?
        public let initialValue: String?
        public let keyboardType: UIKeyboardType
        public let autocapitalization: UITextAutocapitalizationType
        public let isSecure: Bool

        public init(
            placeholder: String? = nil,
            initialValue: String? = nil,
            keyboardType: UIKeyboardType = .default,
            autocapitalization: UITextAutocapitalizationType = .sentences,
            isSecure: Bool = false
        ) {
            self.placeholder = placeholder
            self.initialValue = initialValue
            self.keyboardType = keyboardType
            self.autocapitalization = autocapitalization
            self.isSecure = isSecure
        }
    }

    public struct TextPick: Sendable {
        public let action: Action
        public let text: String
    }

    /// Presents an alert with a single text input field above
    /// the action buttons. Returns the picked action plus the
    /// field's text, or `nil` if cancelled.
    @MainActor
    public static func presentText(
        title: String?,
        message: String?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        textField: TextFieldConfig,
        actions: [Action]
    ) async -> TextPick? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = TextAlertPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                textField: textField,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Hold-to-confirm variant
    //
    // Nuclear-action pattern: a single primary button that fills
    // with progress while the user holds, completes on full
    // hold, resets on release before full. Pair with an optional
    // Cancel button (text alongside the hold button, NOT a
    // second action). Use sparingly — for true point-of-no-return
    // ops where a one-tap destructive confirmation is too easy
    // to misclick: factory reset, delete entire library, log out
    // and forget all data.

    public struct HoldAction: Sendable {
        public let title: String
        /// How long the user must hold to confirm. Sweet spot
        /// is 1.2–1.8 s — long enough that an accidental swipe
        /// won't trigger, short enough that intentional hold
        /// doesn't feel punishing.
        public let duration: TimeInterval
        /// Visual style applied to the button (controls colour).
        /// Default `.destructive` covers most use cases since
        /// hold-to-confirm exists for irreversible operations.
        public let style: Action.Style

        public init(
            title: String,
            duration: TimeInterval = 1.5,
            style: Action.Style = .destructive
        ) {
            self.title = title
            self.duration = duration
            self.style = style
        }
    }

    /// Presents an alert with a hold-to-confirm primary button.
    /// Returns `true` if the user held long enough to confirm,
    /// `false` if cancelled (dismissed via tap-outside or the
    /// optional Cancel button).
    @MainActor
    public static func presentHoldToConfirm(
        title: String?,
        message: String?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        holdAction: HoldAction,
        cancelTitle: String? = "Cancel"
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: false)
                return
            }
            let presentation = HoldAlertPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                holdAction: holdAction,
                cancelTitle: cancelTitle
            ) { confirmed in
                continuation.resume(returning: confirmed)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Expandable details variant
    //
    // Basic alert + a collapsible "details" block. For
    // technical / power-user information that's relevant to the
    // decision but shouldn't be the headline: server error
    // traces, file paths, version details, debug output. The
    // alert defaults to collapsed — visually identical to the
    // basic variant. Tapping the chevron reveals the details
    // text in a scrollable block beneath the message.

    /// Presents an alert with a collapsible technical-details
    /// block between message and buttons.
    @MainActor
    public static func presentExpandable(
        title: String?,
        message: String?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        details: String,
        actions: [Action]
    ) async -> Action? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = ExpandableAlertPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                details: details,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Stepper variant
    //
    // Numeric input with [-] [VALUE] [+] controls. Use for
    // bounded discrete numbers where a slider feels too coarse
    // and a text field too cumbersome: prefetch chapter count,
    // page-cache size, retry attempts, etc.

    public struct StepperConfig: Sendable {
        public let range: ClosedRange<Int>
        public let step: Int
        public let initial: Int
        /// Optional suffix shown after the value ("chapters",
        /// "min", "%"). Localise at call site.
        public let suffix: String?

        public init(
            range: ClosedRange<Int>,
            step: Int = 1,
            initial: Int,
            suffix: String? = nil
        ) {
            precondition(range.contains(initial), "initial must be inside range")
            precondition(step > 0, "step must be positive")
            self.range = range
            self.step = step
            self.initial = initial
            self.suffix = suffix
        }
    }

    public struct StepperPick: Sendable {
        public let action: Action
        public let value: Int
    }

    /// Presents an alert with a numeric stepper control above
    /// the action buttons. Returns the picked action plus the
    /// final value, or `nil` if cancelled.
    @MainActor
    public static func presentStepper(
        title: String?,
        message: String?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        stepper: StepperConfig,
        actions: [Action]
    ) async -> StepperPick? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = StepperAlertPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                stepper: stepper,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Multi-text-field (form) variant
    //
    // Same as `presentText` but with N fields stacked
    // vertically. First field auto-focuses on appear; Return
    // moves to the next field, and Return on the LAST field
    // fires the primary action. Use for short forms: login
    // (username + password), rename + description, etc.
    //
    // Note: for anything beyond ~3 fields, prefer a dedicated
    // sheet/screen — alerts are decision moments, not data-
    // entry surfaces.

    public struct FormPick: Sendable {
        public let action: Action
        /// Final text of each field, in the same order as the
        /// `textFields:` array passed to `presentForm`.
        public let values: [String]
    }

    /// Presents an alert with multiple text input fields above
    /// the action buttons. Returns the picked action plus each
    /// field's text, or `nil` if cancelled.
    @MainActor
    public static func presentForm(
        title: String?,
        message: String?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        textFields: [TextFieldConfig],
        actions: [Action]
    ) async -> FormPick? {
        precondition(!textFields.isEmpty, "presentForm requires at least one text field")
        return await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = FormAlertPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                textFields: textFields,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Toggle/checkbox variant
    //
    // Confirmation alert with one or more checkbox rows between
    // message and buttons. Native iOS has no equivalent — Apple
    // forces you to chain Alert → Sheet or build custom. Common
    // pattern in modern apps: "Delete manga [✓] Also delete
    // 873 downloaded chapters". The toggle is independent of
    // the action choice, returned as part of `TogglePick`.

    public struct ToggleOption: Sendable {
        public let id: String
        public let label: String
        public let initial: Bool

        public init(id: String, label: String, initial: Bool = false) {
            self.id = id
            self.label = label
            self.initial = initial
        }
    }

    public struct TogglePick: Sendable {
        public let action: Action
        /// Toggle state at the moment the action was picked,
        /// keyed by `ToggleOption.id`.
        public let toggles: [String: Bool]
    }

    /// Presents an alert with checkbox rows above the action
    /// buttons. Returns the picked action plus each toggle's
    /// final state, or `nil` if cancelled.
    @MainActor
    public static func presentWithToggles(
        title: String?,
        message: String?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        toggles: [ToggleOption],
        actions: [Action]
    ) async -> TogglePick? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = ToggleAlertPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                toggles: toggles,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Internal helpers

    @MainActor
    static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
    }
}
