import UIKit
import Sumi

// DialogChrome — internal visuals shared by all presentation
// classes in `SumiDialog`.
//
//   • `DialogTextButton`         — flat text-style button
//                                  (no background, no border).
//   • `DialogButtonsRow`         — right-aligned horizontal row
//                                  with 8pt spacing between
//                                  buttons.
//   • `OutlinedTextField`        — Material-3-style field with
//                                  floating label + optional
//                                  required indicator.

// MARK: - DialogIconBanner
//
// Material 3's "icon-on-top" variant — a small SF Symbol
// centred above the title. Distinct from `DialogImageView`
// (which shows a 160pt large preview like a manga cover);
// the icon banner is a tight 28pt symbol for semantic
// signalling on important moments (warnings, permissions,
// completions).
//
// When an icon banner is present, the presentation switches
// title alignment from left to centred for a "hero" hierarchy
// — icon above, title centred, message below.

@MainActor
func makeDialogIconBanner(icon: UIImage, tint: UIColor?) -> UIView {
    let imageView = UIImageView(image: icon)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.tintColor = tint ?? Sumi.Color.accent
    imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
        pointSize: 28,
        weight: .regular
    )

    let wrapper = UIView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(imageView)
    NSLayoutConstraint.activate([
        wrapper.heightAnchor.constraint(equalToConstant: 32),
        imageView.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
        imageView.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        imageView.widthAnchor.constraint(lessThanOrEqualTo: wrapper.widthAnchor),
        imageView.heightAnchor.constraint(lessThanOrEqualTo: wrapper.heightAnchor)
    ])
    return wrapper
}

// MARK: - DialogImageView
//
// Optional image preview shown at the top of the card —
// "Replace cover?" style dialogs. Caps height at 160pt with
// aspect-fit so portrait manga covers (typically 2:3) stay
// readable without dominating the dialog. Rounded corners
// at 12pt give the image its own visual block.

@MainActor
func makeDialogImageView(image: UIImage) -> UIView {
    let imageView = UIImageView(image: image)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.contentMode = .scaleAspectFit
    imageView.layer.cornerRadius = 12
    imageView.layer.cornerCurve = .continuous
    imageView.clipsToBounds = true

    // Wrapper so height can be capped without forcing the
    // imageView itself to a non-intrinsic size — keeps aspect
    // ratio intact via scaleAspectFit.
    let wrapper = UIView()
    wrapper.translatesAutoresizingMaskIntoConstraints = false
    wrapper.addSubview(imageView)
    NSLayoutConstraint.activate([
        imageView.topAnchor.constraint(equalTo: wrapper.topAnchor),
        imageView.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        imageView.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
        imageView.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
        wrapper.heightAnchor.constraint(equalToConstant: 160)
    ])
    return wrapper
}

// MARK: - DialogTextButton
//
// Material 3 "text button": no background, no border, just a
// tinted label with a touch-down highlight overlay. 40pt tall
// (Material spec) with 12pt horizontal padding inside the
// label.

@MainActor
final class DialogTextButton: UIView {

    let action: SumiDialog.Action
    var onTap: (() -> Void)?

    private let label = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var isEnabledState: Bool = true
    var isEnabled: Bool {
        get { isEnabledState }
        set {
            isEnabledState = newValue
            label.alpha = newValue ? 1.0 : 0.35
        }
    }

    init(action: SumiDialog.Action) {
        self.action = action
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let color: UIColor
        switch action.style {
        case .default:     color = Sumi.Color.accent
        case .primary:     color = Sumi.Color.accent
        case .destructive: color = Sumi.Color.danger
        case .cancel:      color = Sumi.Color.accent  // Material text buttons all use the same tint
        }

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = action.title
        label.font = Sumi.Font.bodyEmphasised().sumiSized(14)
        label.textColor = color
        label.textAlignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)

        // Spinner for async loading state. Hidden by default;
        // shown by `setLoading(true)` when the action's
        // asyncHandler is running. Tinted to match label colour
        // so the spinner reads as "this button is working".
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        spinner.color = color
        addSubview(spinner)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc private func tapped() {
        guard isEnabledState else { return }
        onTap?()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isEnabledState else { return }
        UIView.animate(withDuration: 0.08) {
            self.backgroundColor = Sumi.Color.pressOverlay
        }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        // Track-and-update highlight on drag — a press-tracking
        // pattern: drag finger OUT of the button → highlight
        // clears immediately. Drag BACK IN → highlight returns.
        // Without this the press overlay would persist for the
        // whole drag duration and only clear on release.
        //
        // The tap itself is still gated by UITapGestureRecognizer's
        // built-in ~10pt movement tolerance — once a drag passes
        // that, the recogniser fails and the action won't fire
        // even if the finger returns inside the bounds.
        guard isEnabledState, let touch = touches.first else { return }
        let inside = bounds.contains(touch.location(in: self))
        UIView.animate(withDuration: 0.10) {
            self.backgroundColor = inside ? Sumi.Color.pressOverlay : .clear
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.16) {
            self.backgroundColor = .clear
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.12) {
            self.backgroundColor = .clear
        }
    }

    /// Crossfade between label and spinner. Both alphas animate
    /// in parallel — spinner doesn't linger at full visibility
    /// while the label fades back in.
    func setLoading(_ loading: Bool, animated: Bool = true) {
        let labelTarget: CGFloat = loading ? 0 : 1
        let spinnerTarget: CGFloat = loading ? 1 : 0
        if loading {
            spinner.alpha = 0
            spinner.startAnimating()
        }
        let block = {
            self.label.alpha = labelTarget
            self.spinner.alpha = spinnerTarget
        }
        if animated && !Sumi.Motion.isReduced {
            UIView.animate(withDuration: 0.18, animations: block) { _ in
                if !loading {
                    self.spinner.stopAnimating()
                    self.spinner.alpha = 1
                }
            }
        } else {
            block()
            if !loading { spinner.stopAnimating(); spinner.alpha = 1 }
        }
    }

    /// Dim non-loading buttons while a sibling's async handler
    /// runs.
    func setDimmed(_ dimmed: Bool, animated: Bool) {
        let target: CGFloat = dimmed ? 0.35 : 1
        let block = { self.alpha = target }
        if animated && !Sumi.Motion.isReduced {
            UIView.animate(withDuration: 0.15, animations: block)
        } else {
            block()
        }
    }
}

// MARK: - DialogButtonsRow
//
// Horizontal stack pinned to the right, 8pt spacing between
// buttons. Apple convention puts cancel on the left of primary;
// Material 3 likewise (Cancel left, OK/Confirm right). When
// the dialog has 3 buttons (e.g. "Edit | Cancel | OK" from the
// a multi-select categories screen), they stay in supplied
// order with cancel sandwiched.

@MainActor
final class DialogButtonsRow: UIView {

    private let buttons: [DialogTextButton]
    private let onPick: (SumiDialog.Action) -> Void

    init(
        actions: [SumiDialog.Action],
        onPick: @escaping (SumiDialog.Action) -> Void
    ) {
        // Order: non-cancel actions in supplied order, then
        // cancel last (Material 3 + iOS both put cancel just
        // left of the primary affirmative action, which sits
        // rightmost). For 2 buttons, this yields [Cancel, OK].
        let nonCancel = actions.filter { $0.style != .cancel }
        let cancel = actions.filter { $0.style == .cancel }
        let ordered = cancel + nonCancel

        self.buttons = ordered.map { DialogTextButton(action: $0) }
        self.onPick = onPick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center
        addSubview(stack)

        for btn in buttons {
            btn.onTap = { [weak self] in self?.onPick(btn.action) }
            stack.addArrangedSubview(btn)
        }

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 40),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Disable the PRIMARY action (last non-cancel) — used by
    /// the text dialog when a required field is empty.
    func setPrimaryEnabled(_ enabled: Bool) {
        // Find the primary action: explicit `.primary`, else last
        // non-cancel. Buttons array is already in display order
        // (cancel first, then non-cancel).
        let nonCancelButtons = buttons.filter { $0.action.style != .cancel }
        let primary: DialogTextButton? = nonCancelButtons.last { $0.action.style == .primary }
            ?? nonCancelButtons.last
        primary?.isEnabled = enabled
    }

    private weak var loadingButton: DialogTextButton?
    /// True while an async action handler is running.
    var isLoading: Bool { loadingButton != nil }

    /// Enter loading state for the button matching `action`.
    /// Spins that button, dims & disables all others, and
    /// blocks input on the whole row (no double-tap of the
    /// spinning button or accidental tap of the dimmed cancel).
    func startLoading(for action: SumiDialog.Action) {
        guard let target = buttons.first(where: {
            $0.action.title == action.title && $0.action.style == action.style
        }) else { return }
        loadingButton = target
        target.setLoading(true, animated: true)
        for btn in buttons where btn !== target {
            btn.setDimmed(true, animated: true)
        }
        isUserInteractionEnabled = false
    }

    /// Exit loading state — restore all buttons. Called when
    /// the async handler throws so the user can retry.
    func stopLoading() {
        guard let target = loadingButton else { return }
        target.setLoading(false, animated: true)
        for btn in buttons where btn !== target {
            btn.setDimmed(false, animated: true)
        }
        loadingButton = nil
        isUserInteractionEnabled = true
    }
}
