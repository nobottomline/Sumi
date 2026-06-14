import UIKit
import Sumi

// DialogTextFields — three text-field styles + shared base.
//
// Why a base class instead of three independent UIViews:
//
//   • Shared UITextField configuration (keyboard type,
//     autocapitalisation, secure mode, font, tint) lives in
//     one place — subclasses only describe LAYOUT.
//
//   • Shared delegate machinery (return key handler, focus
//     change hooks) lives in one place — subclasses opt in to
//     specific behaviours via `onBeginEditing()`/`onEndEditing()`
//     overrides.
//
//   • The presentation layer (TextDialogPresentation,
//     FormDialogPresentation) treats every field as the same
//     `DialogTextFieldView` type, removing dispatch boilerplate.
//
// Styles:
//
//   • `OutlinedTextField` — Material 3 outlined with floating
//     cutout label.
//   • `InsetTextField`    — static label above + cream-filled
//                           inset rounded rect. iOS-idiomatic.
//   • `StampTextField`    — Sumi-unique: small "stamp" tag
//                           overlapping the field's top-left
//                           corner like a hanko on paper.

// MARK: - Base class

@MainActor
class DialogTextFieldView: UIView, UITextFieldDelegate {

    /// Concrete UITextField shared across all styles. Subclasses
    /// position it inside their own layout. Presentation layer
    /// reaches into this directly for focus / return-key /
    /// resignFirstResponder.
    final let textField = UITextField()

    final let config: SumiDialog.TextFieldConfig

    /// Fires on every `editingChanged` event. Presentation uses
    /// this to refresh the primary-button-enabled state when
    /// `isRequired` is set.
    var onTextChanged: ((String) -> Void)?

    /// Fires when the user taps Return on the keyboard.
    /// Presentation routes this to "focus next field" or
    /// "fire primary action" based on context.
    var onReturn: (() -> Void)?

    var isEmpty: Bool { (textField.text ?? "").isEmpty }

    init(config: SumiDialog.TextFieldConfig) {
        self.config = config
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        configureSharedTextField()
        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Shared text-field configuration (keyboard, font, tint).
    /// Padding/leftView is per-style, set in subclass layout.
    private func configureSharedTextField() {
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.text = config.initialValue
        textField.keyboardType = config.keyboardType
        textField.autocapitalizationType = config.autocapitalization
        textField.isSecureTextEntry = config.isSecure
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.font = Sumi.Font.body().sumiSized(16)
        textField.textColor = Sumi.Color.textPrimary
        textField.tintColor = Sumi.Color.accent
        textField.delegate = self
        textField.addTarget(self, action: #selector(textChangedShared), for: .editingChanged)
        textField.returnKeyType = .done
        // Use an attributed placeholder so the hint text reads
        // in the same secondary colour as the surrounding
        // chrome (the OS default for `placeholder` is a much
        // higher-contrast grey that fights with our label
        // hierarchy).
        if let placeholder = config.placeholder {
            textField.attributedPlaceholder = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: Sumi.Color.textSecondary.withAlphaComponent(0.65),
                    .font: Sumi.Font.body().sumiSized(16)
                ]
            )
        }
    }

    /// Subclasses MUST override to build their visual hierarchy
    /// (border, labels, etc.) and add the inherited `textField`
    /// to the appropriate position.
    func buildLayout() {
        fatalError("Subclasses of DialogTextFieldView must override buildLayout()")
    }

    /// Hook for subclass-specific focus styling — accent border,
    /// label float, stamp pulse, etc. Default: no-op.
    func onBeginEditing() {}

    /// Hook for subclass-specific blur styling.
    func onEndEditing() {}

    /// Hook for subclass-specific layout updates on text edits
    /// (e.g. Material 3 label float when text empties).
    func onTextChangedInternal() {}

    /// Apply the focused visual UPFRONT — before
    /// `becomeFirstResponder` actually fires. Inset / stamp
    /// override this because their focus signal is STATIC (a
    /// border, a stamp tweak) and the ~0.5s wait for the
    /// spring-then-keyboard-then-onBeginEditing chain reads
    /// as "the field forgot to highlight". The outlined style
    /// keeps the default no-op since its float-label
    /// transition IS the entry animation — running it at
    /// dialog-appear time would skip the nice transition.
    func applyInitialFocusVisual() {}

    // MARK: UITextFieldDelegate — final, route to override hooks

    final func textFieldDidBeginEditing(_ tf: UITextField) {
        onBeginEditing()
    }
    final func textFieldDidEndEditing(_ tf: UITextField) {
        onEndEditing()
    }
    final func textFieldShouldReturn(_ tf: UITextField) -> Bool {
        onReturn?()
        return true
    }

    @objc private func textChangedShared() {
        onTextChangedInternal()
        onTextChanged?(textField.text ?? "")
    }

    // MARK: - Internal padding helper

    /// Build a fixed-width inert spacer for use as UITextField's
    /// leftView / rightView (UITextField has no native
    /// horizontal-padding API).
    static func textPad(width: CGFloat) -> UIView {
        UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
    }
}

// MARK: - Factory

@MainActor
func makeDialogTextField(config: SumiDialog.TextFieldConfig) -> DialogTextFieldView {
    switch config.style {
    case .outlined: return OutlinedTextField(config: config)
    case .inset:    return InsetTextField(config: config)
    case .stamp:    return StampTextField(config: config)
    }
}

// MARK: - OutlinedTextField (Material 3 with cutout label)
//
// A rounded rect border with the field's label floating either
// inside (placeholder position when empty + unfocused) or on
// top of the border (focused or filled). The label's background
// matches the dialog surface, painting over the border line for
// the cutout illusion.

@MainActor
final class OutlinedTextField: DialogTextFieldView {

    private let borderView = UIView()
    private let floatingLabel = UILabel()
    private let requiredLabel = UILabel()
    private var labelIsFloating: Bool = false

    override func buildLayout() {
        // Border — UIView with stroke. 6pt corner radius.
        borderView.translatesAutoresizingMaskIntoConstraints = false
        borderView.backgroundColor = .clear
        borderView.layer.cornerRadius = 6
        borderView.layer.cornerCurve = .continuous
        borderView.layer.borderColor = Sumi.Color.textSecondary.cgColor
        borderView.layer.borderWidth = 1.5
        borderView.isUserInteractionEnabled = false
        addSubview(borderView)

        textField.leftView = Self.textPad(width: 12)
        textField.rightView = Self.textPad(width: 12)
        textField.leftViewMode = .always
        textField.rightViewMode = .always
        addSubview(textField)

        floatingLabel.translatesAutoresizingMaskIntoConstraints = false
        floatingLabel.text = config.label
        floatingLabel.font = Sumi.Font.body().sumiSized(16)
        floatingLabel.textColor = Sumi.Color.textSecondary
        floatingLabel.backgroundColor = Sumi.Color.surfaceElevated
        floatingLabel.layer.zPosition = 1
        addSubview(floatingLabel)

        requiredLabel.translatesAutoresizingMaskIntoConstraints = false
        requiredLabel.text = "*required"
        requiredLabel.font = Sumi.Font.caption().sumiSized(12)
        requiredLabel.textColor = Sumi.Color.textSecondary
        requiredLabel.isHidden = !config.displaysRequiredIndicator
        addSubview(requiredLabel)

        NSLayoutConstraint.activate([
            borderView.topAnchor.constraint(equalTo: topAnchor),
            borderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            borderView.heightAnchor.constraint(equalToConstant: 56),

            textField.leadingAnchor.constraint(equalTo: borderView.leadingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: borderView.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: borderView.centerYAnchor),
            textField.heightAnchor.constraint(equalToConstant: 44),

            floatingLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            floatingLabel.centerYAnchor.constraint(equalTo: borderView.centerYAnchor),

            requiredLabel.topAnchor.constraint(equalTo: borderView.bottomAnchor, constant: 4),
            requiredLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bottomAnchor.constraint(equalTo: config.displaysRequiredIndicator ? requiredLabel.bottomAnchor : borderView.bottomAnchor, constant: 0)
        ])

        updateLabelState(animated: false, force: true)
    }

    override func onBeginEditing() {
        borderView.layer.borderColor = Sumi.Color.accent.cgColor
        borderView.layer.borderWidth = 2.0
        floatingLabel.textColor = Sumi.Color.accent
        updateLabelState(animated: true)
    }

    override func onEndEditing() {
        borderView.layer.borderColor = Sumi.Color.textSecondary.cgColor
        borderView.layer.borderWidth = 1.5
        floatingLabel.textColor = Sumi.Color.textSecondary
        updateLabelState(animated: true)
    }

    override func onTextChangedInternal() {
        updateLabelState(animated: true)
    }

    private func updateLabelState(animated: Bool, force: Bool = false) {
        let shouldFloat = textField.isFirstResponder || !isEmpty
        if shouldFloat == labelIsFloating && !force { return }
        labelIsFloating = shouldFloat

        let scale: CGFloat = shouldFloat ? (12.0 / 16.0) : 1.0
        let labelWidth = floatingLabel.intrinsicContentSize.width
        let translateX: CGFloat = shouldFloat
            ? -(labelWidth * (1 - scale) / 2) + (12 - 16)
            : 0
        let translateY: CGFloat = shouldFloat ? -28 : 0

        let block = {
            self.floatingLabel.transform = CGAffineTransform
                .identity
                .translatedBy(x: translateX, y: translateY)
                .scaledBy(x: scale, y: scale)
            self.floatingLabel.layoutMargins = shouldFloat
                ? UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
                : .zero
        }

        if animated && !Sumi.Motion.isReduced {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                options: [.curveEaseInOut, .allowUserInteraction],
                animations: block
            )
        } else {
            block()
        }
    }
}

// MARK: - InsetTextField (static label above, cream-filled)
//
// Sumi's default text-field style. Static label sits above the
// field, always visible. The field itself is a cream-filled
// inset rounded rect — no border, no animations on focus
// other than a subtle background lift. iOS-idiomatic (Apple
// Settings and similar modern forms) and distinctly NOT
// Material 3 — no cutout, no float.

@MainActor
final class InsetTextField: DialogTextFieldView {

    private let topLabel = UILabel()
    private let fieldBackground = UIView()
    private let requiredLabel = UILabel()

    /// Non-nil only when `config.focusAnimation == .tracing`. Owns the
    /// drawn-outline focus affordance; when present it REPLACES the
    /// instant `layer.border*` focus signal.
    private var trace: FocusTraceBorder?

    override func buildLayout() {
        // Top label — caption-sized, always visible.
        topLabel.translatesAutoresizingMaskIntoConstraints = false
        topLabel.text = config.label
        topLabel.font = Sumi.Font.captionEmphasised()
        topLabel.textColor = Sumi.Color.textSecondary
        topLabel.numberOfLines = 1
        addSubview(topLabel)

        // Field background — the inset rounded rect.
        fieldBackground.translatesAutoresizingMaskIntoConstraints = false
        fieldBackground.backgroundColor = Sumi.Color.surfaceSubtle
        fieldBackground.layer.cornerRadius = 12
        fieldBackground.layer.cornerCurve = .continuous
        fieldBackground.isUserInteractionEnabled = false
        addSubview(fieldBackground)

        // Expert focus affordance — the magnetic field-line trace.
        // Lives on the field background; path is sized in layoutSubviews.
        if config.focusAnimation == .tracing {
            let trace = FocusTraceBorder(
                cornerRadius: fieldBackground.layer.cornerRadius,
                lineWidth: 2,
                color: Sumi.Color.accent
            )
            trace.install(in: fieldBackground)
            self.trace = trace
        }

        // Text field overlays the background. 16pt H padding,
        // 14pt vertical (via height constraint).
        textField.leftView = Self.textPad(width: 16)
        textField.rightView = Self.textPad(width: 16)
        textField.leftViewMode = .always
        textField.rightViewMode = .always
        addSubview(textField)

        requiredLabel.translatesAutoresizingMaskIntoConstraints = false
        requiredLabel.text = "*required"
        requiredLabel.font = Sumi.Font.caption().sumiSized(12)
        requiredLabel.textColor = Sumi.Color.textSecondary
        requiredLabel.isHidden = !config.displaysRequiredIndicator
        addSubview(requiredLabel)

        NSLayoutConstraint.activate([
            topLabel.topAnchor.constraint(equalTo: topAnchor),
            topLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            topLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),

            fieldBackground.topAnchor.constraint(equalTo: topLabel.bottomAnchor, constant: 6),
            fieldBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            fieldBackground.heightAnchor.constraint(equalToConstant: 48),

            textField.topAnchor.constraint(equalTo: fieldBackground.topAnchor),
            textField.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor),

            requiredLabel.topAnchor.constraint(equalTo: fieldBackground.bottomAnchor, constant: 4),
            requiredLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            bottomAnchor.constraint(equalTo: config.displaysRequiredIndicator ? requiredLabel.bottomAnchor : fieldBackground.bottomAnchor)
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep the focus trace path in sync with the field's bounds.
        trace?.updatePath(for: fieldBackground.bounds)
    }

    override func onBeginEditing() {
        if let trace {
            // Drawn-outline focus signal. Make sure the path is current
            // (initial focus can fire right after the dialog's
            // layoutIfNeeded), then play the magnetic trace.
            trace.updatePath(for: fieldBackground.bounds)
            trace.animateIn(reduceMotion: Sumi.Motion.isReduced)
        } else {
            // Earlier attempt: shift bg to `surfaceElevated` on
            // focus → that's the SAME colour as the dialog's card,
            // so the field visually merged with the dialog. Switch
            // to a snap-in 2pt accent border + label-colour fade —
            // unambiguous focus signal without bg conflict.
            fieldBackground.layer.borderColor = Sumi.Color.accent.cgColor
            fieldBackground.layer.borderWidth = 2.0
        }
        let labelFade = { self.topLabel.textColor = Sumi.Color.accent }
        if Sumi.Motion.isReduced {
            labelFade()
        } else {
            UIView.animate(withDuration: 0.18, animations: labelFade)
        }
    }

    override func onEndEditing() {
        if let trace {
            trace.animateOut(reduceMotion: Sumi.Motion.isReduced)
        } else {
            fieldBackground.layer.borderColor = UIColor.clear.cgColor
            fieldBackground.layer.borderWidth = 0
        }
        let labelFade = { self.topLabel.textColor = Sumi.Color.textSecondary }
        if Sumi.Motion.isReduced {
            labelFade()
        } else {
            UIView.animate(withDuration: 0.18, animations: labelFade)
        }
    }

    /// Pre-apply focus visual at dialog-appear time — without
    /// this, the user sees ~0.5s of unhighlighted field while
    /// the card's spring settles + `becomeFirstResponder`
    /// fires in completion. Triggering onBeginEditing here
    /// makes the focus signal land WITH the dialog's
    /// appearance.
    override func applyInitialFocusVisual() {
        onBeginEditing()
    }
}

// MARK: - StampTextField (manga sticker)
//
// Experimental Sumi-unique style. The field's label sits as a
// small accent-coloured "stamp" tag in the top-left corner,
// slightly rotated and shadow-lifted — like a hanko mark on a
// printed form. Distinct from any other design system's text
// field: not Material, not iOS-native, not Bootstrap.
//
// The field itself is a more rounded (14pt corners) cream-
// filled rect with extra top padding so the stamp doesn't
// overlap text.

@MainActor
final class StampTextField: DialogTextFieldView {

    private let fieldBackground = UIView()
    private let stampView = UIView()
    private let stampLabel = UILabel()
    private let requiredLabel = UILabel()

    override func buildLayout() {
        // Field background — slightly more rounded than inset
        // variant to make space for the stamp's corner overlap.
        fieldBackground.translatesAutoresizingMaskIntoConstraints = false
        fieldBackground.backgroundColor = Sumi.Color.surfaceSubtle
        fieldBackground.layer.cornerRadius = 14
        fieldBackground.layer.cornerCurve = .continuous
        fieldBackground.isUserInteractionEnabled = false
        addSubview(fieldBackground)

        // Text field — extra TOP padding so user text doesn't
        // collide with the stamp. Using leftView for H padding,
        // and positioning textField inset 18pt from field top
        // (stamp eats top space).
        textField.leftView = Self.textPad(width: 16)
        textField.rightView = Self.textPad(width: 16)
        textField.leftViewMode = .always
        textField.rightViewMode = .always
        addSubview(textField)

        // Stamp tag — small rounded rect with accent bg + onAccent
        // text. Positioned over the top-left of the field, with
        // a small rotation and shadow for the "stamped on paper"
        // feel.
        stampView.translatesAutoresizingMaskIntoConstraints = false
        stampView.backgroundColor = Sumi.Color.accent
        stampView.layer.cornerRadius = 4
        stampView.layer.cornerCurve = .continuous
        stampView.layer.shadowColor = Sumi.Brand.umberShadow.cgColor
        stampView.layer.shadowOpacity = 0.20
        stampView.layer.shadowRadius = 3
        stampView.layer.shadowOffset = CGSize(width: 0, height: 1.5)
        // Slight CCW rotation — hand-stamped feel, not printer-
        // perfect alignment.
        stampView.transform = CGAffineTransform(rotationAngle: -2.5 * .pi / 180)
        addSubview(stampView)

        stampLabel.translatesAutoresizingMaskIntoConstraints = false
        stampLabel.text = config.label.uppercased()
        stampLabel.font = Sumi.Font.captionEmphasised().sumiSized(11)
        stampLabel.textColor = Sumi.Color.onAccent
        // Slight letter-spacing for stamped/printed look.
        stampLabel.attributedText = NSAttributedString(
            string: config.label.uppercased(),
            attributes: [
                .font: Sumi.Font.captionEmphasised().sumiSized(11),
                .foregroundColor: Sumi.Color.onAccent,
                .kern: 0.6
            ]
        )
        stampView.addSubview(stampLabel)

        requiredLabel.translatesAutoresizingMaskIntoConstraints = false
        requiredLabel.text = "*required"
        requiredLabel.font = Sumi.Font.caption().sumiSized(12)
        requiredLabel.textColor = Sumi.Color.textSecondary
        requiredLabel.isHidden = !config.displaysRequiredIndicator
        addSubview(requiredLabel)

        NSLayoutConstraint.activate([
            fieldBackground.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            fieldBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            fieldBackground.trailingAnchor.constraint(equalTo: trailingAnchor),
            fieldBackground.heightAnchor.constraint(equalToConstant: 56),

            textField.topAnchor.constraint(equalTo: fieldBackground.topAnchor, constant: 12),
            textField.bottomAnchor.constraint(equalTo: fieldBackground.bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: fieldBackground.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: fieldBackground.trailingAnchor),

            // Stamp positioned to overlap the field's top edge.
            // y = topAnchor (overlaps by ~6pt since field starts
            // at topAnchor + 6).
            stampView.topAnchor.constraint(equalTo: topAnchor),
            stampView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),

            stampLabel.topAnchor.constraint(equalTo: stampView.topAnchor, constant: 4),
            stampLabel.bottomAnchor.constraint(equalTo: stampView.bottomAnchor, constant: -4),
            stampLabel.leadingAnchor.constraint(equalTo: stampView.leadingAnchor, constant: 10),
            stampLabel.trailingAnchor.constraint(equalTo: stampView.trailingAnchor, constant: -10),

            requiredLabel.topAnchor.constraint(equalTo: fieldBackground.bottomAnchor, constant: 4),
            requiredLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            bottomAnchor.constraint(equalTo: config.displaysRequiredIndicator ? requiredLabel.bottomAnchor : fieldBackground.bottomAnchor)
        ])
    }

    override func onBeginEditing() {
        // Focus signal is the stamp's pulse alone — the stamp
        // is already a strong always-visible affordance, no
        // need to also shift the field bg (which would merge
        // with the dialog's `surfaceElevated` and make the
        // field disappear).
        guard !Sumi.Motion.isReduced else {
            stampView.transform = .identity.scaledBy(x: 1.03, y: 1.03)
            return
        }
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.5
        ) {
            // Straighten + grow slightly — stamp "wakes up".
            self.stampView.transform = CGAffineTransform.identity
                .scaledBy(x: 1.03, y: 1.03)
        }
    }

    override func onEndEditing() {
        let restoreRotation = CGAffineTransform(rotationAngle: -2.5 * .pi / 180)
        if Sumi.Motion.isReduced {
            stampView.transform = restoreRotation
        } else {
            UIView.animate(withDuration: 0.22) {
                self.stampView.transform = restoreRotation
            }
        }
    }

    /// Trigger the stamp's pulse at dialog-appear time so the
    /// focus cue lands with the card's appearance, not ~0.5s
    /// later when the spring settles + becomeFirstResponder
    /// fires in completion.
    override func applyInitialFocusVisual() {
        onBeginEditing()
    }
}
