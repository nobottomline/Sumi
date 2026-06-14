import UIKit
import Sumi

// SumiDialog — Material-3-influenced dialog.
//
// Sibling to `SumiAlert`. Same job (modal decision moment with
// title + message + actions), different visual identity:
//
//                  SumiAlert (iOS-native)       SumiDialog (Material 3)
//   Buttons        Full-width, edge-to-edge     Right-aligned text buttons
//   Tap outside    Does NOT dismiss             DOES dismiss (Material default)
//   Text field     Inset rounded rect           Outlined with floating label
//   Padding        Tight                        Generous (24pt all sides)
//   Corner radius  16pt                         24pt (softer feel)
//   Aesthetic      Critical decisions           Form prompts, softer choices
//
// Use cases that fit `SumiDialog` better than `SumiAlert`:
//   • "Add repository URL" / "Add category" / "Rename" — form
//     prompts where tap-outside-to-cancel is the expected escape
//     hatch.
//   • Confirmations that aren't destructive nuclear actions.
//
// Use cases that still belong to `SumiAlert`:
//   • Destructive confirmations ("Delete chapter?") — full-width
//     buttons read as committing decisions, and tap-outside
//     dismissing a destructive prompt is risky.
//   • Anything needing icon variant / hold-to-confirm / async
//     loading state — those features live on `SumiAlert`.
//
// File map (same shape as SumiAlert):
//   • Dialog.swift              — this file: public API
//   • DialogChrome.swift        — shared internals: action row,
//                                 button, outlined text field.
//   • DialogPresentations.swift — presentation classes.

public enum SumiDialog {

    public struct Action: Sendable {

        public enum Style: Sendable {
            case `default`
            case primary       // emphasised text colour (accent)
            case destructive
            case cancel
        }

        public let title: String
        public let style: Style
        /// Optional async work to run when the user picks this
        /// action. If non-nil, the dialog KEEPS its presentation
        /// while the handler runs: the button replaces its
        /// label with a spinner, other buttons + tap-outside
        /// are gated. On success the dialog dismisses normally;
        /// on throw, the spinner reverts to the label and an
        /// inline error message appears below the input — the
        /// user can fix and retry.
        ///
        /// Stored shape: closure receives a single String —
        /// the current text-field value for `presentText`, an
        /// empty string for the plain `present(...)`. Form
        /// dialogs use `asyncFormHandler` instead (one closure
        /// per row would be ambiguous).
        ///
        /// Available on `present(...)` / `presentText` /
        /// `presentForm`. Use cases: "Add" that validates a URL
        /// against a server, "Sign in" that POSTs credentials.
        public let asyncHandler: (@MainActor @Sendable (String) async throws -> Void)?
        /// Form-dialog variant of `asyncHandler` — receives every
        /// field's current value in declaration order. Used by
        /// `presentForm`; nil for non-form dialogs.
        public let asyncFormHandler: (@MainActor @Sendable ([String]) async throws -> Void)?

        public init(title: String, style: Style = .default) {
            self.title = title
            self.style = style
            self.asyncHandler = nil
            self.asyncFormHandler = nil
        }

        /// Plain async handler — fires on action pick, no input
        /// passed through. Kept as a separate overload so simple
        /// confirmations don't have to ignore an `_: String`
        /// parameter for a value they never read.
        public init(
            title: String,
            style: Style = .default,
            asyncHandler: @escaping @MainActor @Sendable () async throws -> Void
        ) {
            self.title = title
            self.style = style
            // Bridge to the shared text-aware storage by wrapping
            // and dropping the input. Lets the presentation layer
            // call a single uniform `handler(text)` signature
            // regardless of which overload built the action.
            self.asyncHandler = { _ in try await asyncHandler() }
            self.asyncFormHandler = nil
        }

        /// Text-aware async handler — receives the current
        /// `presentText` field value. The handler decides
        /// validity: throw on bad input (URL doesn't end in
        /// .json, malformed URL, server rejected) and the dialog
        /// stays open with an inline error so the user can fix
        /// without retyping.
        ///
        /// On non-text dialogs the handler receives an empty
        /// string — same overload works for both, but you'd
        /// typically use the plain `asyncHandler` for those.
        public init(
            title: String,
            style: Style = .default,
            asyncHandlerWithText: @escaping @MainActor @Sendable (String) async throws -> Void
        ) {
            self.title = title
            self.style = style
            self.asyncHandler = asyncHandlerWithText
            self.asyncFormHandler = nil
        }

        /// Form-aware async handler — receives current values of
        /// every `presentForm` field in declaration order. Throw
        /// to keep the dialog open with an inline error; return
        /// normally to dismiss.
        public init(
            title: String,
            style: Style = .default,
            asyncFormHandler: @escaping @MainActor @Sendable ([String]) async throws -> Void
        ) {
            self.title = title
            self.style = style
            self.asyncHandler = nil
            self.asyncFormHandler = asyncFormHandler
        }
    }

    /// Present a Material-3-styled dialog.
    ///
    /// `message` accepts a `Sumi.RichText` value — string literals
    /// pass through as plain text; `.markdown("...")` enables
    /// inline `**bold**`, `*italic*`, `` `code` ``, and
    /// `[text](url)`. Link taps fire `linkHandler`.
    ///
    /// `customContent` injects an arbitrary view between the
    /// message and the action row — ideal for `SumiTableView`
    /// or any caller-provided UIView. Its intrinsic size drives
    /// the dialog's height in that region.
    @MainActor
    public static func present(
        title: String?,
        message: Sumi.RichText?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        image: UIImage? = nil,
        customContent: UIView? = nil,
        linkHandler: ((URL) -> Void)? = nil,
        actions: [Action]
    ) async -> Action? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = DialogPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                image: image,
                customContent: customContent,
                linkHandler: linkHandler,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Outlined text field variant
    //
    // Material 3 outlined text field with floating label. When
    // `isRequired` is set, an inline "*required" indicator
    // shows below the field and the primary action is disabled
    // until the field is non-empty.

    /// Visual style of the dialog's text field. Three options
    /// each fit different visual languages:
    ///
    ///   • `.inset` (default) — static label above + cream-filled
    ///     inset rounded rect. iOS-idiomatic (Apple's Settings,
    ///     and similar modern forms). Best general-purpose.
    ///
    ///   • `.outlined` — Material 3 outlined field with floating
    ///     cutout label. Beautiful but recognisable as Material;
    ///     use when you want to leverage that familiarity.
    ///
    ///   • `.stamp` — experimental Sumi-unique: the label sits
    ///     as a small "stamp" tag overlapping the top-left of
    ///     the field, like a hanko mark on paper. Manga
    ///     aesthetic, distinct from any other design system.
    ///
    /// Defaults to `.inset` because it's the canonical iOS form
    /// pattern and doesn't carry baggage from another OS's
    /// design language.
    public enum TextFieldStyle: Sendable {
        case inset
        case outlined
        case stamp
    }

    /// How the focus accent appears when a field becomes first
    /// responder. Opt-in — the default stays the instant snap-in so
    /// existing call sites are unchanged.
    public enum FocusBorderAnimation: Sendable {
        /// Border appears at full extent immediately (current default).
        case instant
        /// Expert / experimental: the accent outline is *drawn* — it
        /// springs from the field's top-centre and sweeps down both
        /// sides at once, sealing at the bottom-centre like field
        /// lines wrapping a magnet (~0.4s). Currently honoured by the
        /// `.inset` style.
        case tracing
    }

    public struct TextFieldConfig: Sendable {
        /// Label shown above the field (`.inset`), floated on
        /// the border (`.outlined`), or as a stamp tag
        /// (`.stamp`). Always visible regardless of style —
        /// users keep context after typing.
        public let label: String
        /// Hint text shown INSIDE the empty field. Distinct
        /// from `label` (which is always-visible chrome around
        /// the field): placeholder is the iOS-classic
        /// "tap-and-it-disappears" affordance. nil = no
        /// placeholder (empty field renders blank).
        public let placeholder: String?
        public let initialValue: String?
        public let keyboardType: UIKeyboardType
        public let autocapitalization: UITextAutocapitalizationType
        public let isSecure: Bool
        /// When true, disables the primary action while the
        /// field is empty. Pair with `showsRequiredIndicator`
        /// to decide whether the visual "*required" caption
        /// also renders.
        public let isRequired: Bool
        /// Visual companion to `isRequired`. When `isRequired`
        /// is true:
        ///   • `true`  (default) — renders the inline
        ///     "*required" caption below the field.
        ///   • `false` — caption is hidden; gating still
        ///     applies. Use for compact forms where the
        ///     disabled button is signal enough (e.g. login —
        ///     "Log in" stays grey until both fields are
        ///     typed) and an explicit "*required" tag would
        ///     visually shout.
        ///
        /// When `isRequired == false`, this flag is ignored —
        /// no indicator regardless.
        public let showsRequiredIndicator: Bool
        public let style: TextFieldStyle
        /// Focus-accent animation. Defaults to `.instant`; set
        /// `.tracing` for the magnetic field-line draw-in.
        public let focusAnimation: FocusBorderAnimation

        public init(
            label: String,
            placeholder: String? = nil,
            initialValue: String? = nil,
            keyboardType: UIKeyboardType = .default,
            autocapitalization: UITextAutocapitalizationType = .sentences,
            isSecure: Bool = false,
            isRequired: Bool = false,
            showsRequiredIndicator: Bool = true,
            style: TextFieldStyle = .inset,
            focusAnimation: FocusBorderAnimation = .instant
        ) {
            self.label = label
            self.placeholder = placeholder
            self.initialValue = initialValue
            self.keyboardType = keyboardType
            self.autocapitalization = autocapitalization
            self.isSecure = isSecure
            self.isRequired = isRequired
            self.showsRequiredIndicator = showsRequiredIndicator
            self.style = style
            self.focusAnimation = focusAnimation
        }

        /// Internal: render the "*required" caption only when
        /// gating IS active AND the caller hasn't opted out.
        var displaysRequiredIndicator: Bool {
            isRequired && showsRequiredIndicator
        }
    }

    public struct TextPick: Sendable {
        public let action: Action
        public let text: String
    }

    /// Presents a dialog with a single outlined floating-label
    /// text field above the action buttons. Returns the picked
    /// action plus the field text, or `nil` if cancelled.
    ///
    /// `confirmDiscardIfEdited`: when true AND the user has
    /// typed something, tapping the dimmer (outside the card)
    /// surfaces a quick confirm before dismissing. Use for
    /// forms where accidentally losing typed text would be
    /// painful ("Add repo URL" with a half-typed URL).
    @MainActor
    public static func presentText(
        title: String?,
        message: String?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        image: UIImage? = nil,
        textField: TextFieldConfig,
        confirmDiscardIfEdited: Bool = false,
        actions: [Action]
    ) async -> TextPick? {
        await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = TextDialogPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                image: image,
                textField: textField,
                confirmDiscardIfEdited: confirmDiscardIfEdited,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    // MARK: - Multi-text-field (form) variant
    //
    // N outlined floating-label fields stacked between header
    // and buttons. Return on a non-last field focuses the next;
    // return on the last fires the primary action. `isRequired`
    // on any field gates the primary button — all required
    // fields must be non-empty before primary becomes tappable.

    public struct FormPick: Sendable {
        public let action: Action
        /// Final text of each field, same order as `textFields:`.
        public let values: [String]
    }

    @MainActor
    public static func presentForm(
        title: String?,
        message: String?,
        icon: UIImage? = nil,
        iconTint: UIColor? = nil,
        image: UIImage? = nil,
        textFields: [TextFieldConfig],
        confirmDiscardIfEdited: Bool = false,
        actions: [Action]
    ) async -> FormPick? {
        precondition(!textFields.isEmpty, "presentForm requires at least one text field")
        return await withCheckedContinuation { continuation in
            guard let window = Self.activeWindow() else {
                continuation.resume(returning: nil)
                return
            }
            let presentation = FormDialogPresentation(
                title: title,
                message: message,
                icon: icon,
                iconTint: iconTint,
                image: image,
                textFields: textFields,
                confirmDiscardIfEdited: confirmDiscardIfEdited,
                actions: actions
            ) { picked in
                continuation.resume(returning: picked)
            }
            presentation.attach(to: window)
        }
    }

    @MainActor
    static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
    }
}
