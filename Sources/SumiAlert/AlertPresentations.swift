import UIKit
import Sumi

// AlertPresentations — presentation classes driving the alert
// lifecycle: build card hierarchy, attach to window, animate
// in, accept user input, complete back to caller.
//
// One class per VARIANT (basic, text, form, toggle, stepper,
// hold, expandable). Each owns its own state machine and result
// type; sharing happens through `AlertChrome` for visuals and
// the `Alert` API enum for types.
//
// Class registry:
//
//   • AlertPresentation           — Alert.present(...)
//   • TextAlertPresentation       — Alert.presentText(...)
//   • FormAlertPresentation       — Alert.presentForm(...)
//   • ToggleAlertPresentation     — Alert.presentWithToggles(...)
//   • StepperAlertPresentation    — Alert.presentStepper(...)
//   • ExpandableAlertPresentation — Alert.presentExpandable(...)
//   • HoldAlertPresentation       — Alert.presentHoldToConfirm(...)
//   • SumiProgressAlert           — owned by caller (own lifecycle)

// MARK: - Basic alert presentation

@MainActor
final class AlertPresentation {

    // Live presentations — strong references kept here so the
    // controller stays alive between `attach()` returning and
    // the user tapping a button. Without this the local
    // `presentation` var inside `Alert.present(...)` is the
    // only owner; once `attach()` returns it deallocates, and
    // button taps fire `[weak self] in self?.complete(...)` on
    // a nil self — alert never closes. UIKit's
    // UIAlertController does the same trick internally.
    private static var live: [AlertPresentation] = []

    private let title: String?
    private let message: Sumi.RichText?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let customContent: UIView?
    private let linkHandler: ((URL) -> Void)?
    private let actions: [Alert.Action]
    private let completion: (Alert.Action?) -> Void

    private let dimmer = UIView()
    // Outer card: no clip (shadow needs to escape bounds),
    // transparent — only used for animation + shadow.
    private let card = UIView()
    // Inner clip container: rounded + clipsToBounds=true.
    // Holds all visual content. Press feedback overlays on
    // buttons render INSIDE this view, so they're clipped to
    // the rounded silhouette — no more gray tails poking past
    // the corners.
    //
    // Why a separate inner view (vs setting card.clipsToBounds
    // = true): when masksToBounds=true on a layer, the rendered
    // shadow gets clipped too. Setting `shadowPath` explicitly
    // is supposed to render shadow outside the clip, but the
    // result is inconsistent on iOS in practice (varies by
    // version, by GPU, by cornerCurve). The two-layer pattern
    // — outer for shadow, inner for clipping — is the proven
    // pattern (same one `SumiToast` uses).
    private let cardClip = UIView()
    /// Inline error shown when an `asyncHandler` throws. Hidden
    /// initially; revealed by `showError` and hidden again
    /// when the user picks a new action.
    private let errorLabel = UILabel()
    private weak var buttonsView: AlertButtonsView?
    private var asyncTask: Task<Void, Never>?
    private var didComplete = false

    init(
        title: String?,
        message: Sumi.RichText?,
        icon: UIImage?,
        iconTint: UIColor?,
        customContent: UIView?,
        linkHandler: ((URL) -> Void)?,
        actions: [Alert.Action],
        completion: @escaping (Alert.Action?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.customContent = customContent
        self.linkHandler = linkHandler
        self.actions = actions
        self.completion = completion
    }

    func attach(to window: UIWindow) {
        Self.live.append(self)
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20),
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 280)
        ])

        // Reduce Motion: skip the 0.88× scale-in, do a plain
        // crossfade of card + dimmer. Same duration so the
        // alert appears at the same moment users expect.
        if Sumi.Motion.isReduced {
            card.transform = .identity
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.alpha = 1
            }
        } else {
            card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.transform = .identity
                self.card.alpha = 1
            }
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Sets the shadow's explicit path so Core Animation renders
    /// it along the rounded outline of the inner `cardClip`,
    /// not as a rectangle around the outer transparent card
    /// (which would draw a square shadow under a rounded card).
    ///
    /// Must be called AFTER `layoutIfNeeded` so `card.bounds`
    /// reflects the resolved auto-layout size.
    private func applyShadowPath() {
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath
    }

    private func configureCard() {
        // Outer card — transparent, no clip, just owns the shadow.
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        // Inner clip — visible card surface. All content goes
        // here so press overlays are clipped to rounded shape.
        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = Sumi.Radius.card
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = Sumi.Spacing.s
        content.alignment = .fill

        if let icon {
            let iconView = makeAlertIconView(icon: icon, tint: iconTint)
            content.addArrangedSubview(iconView)
            // Slightly larger gap between icon and title so the
            // icon reads as a separate visual block, not crammed
            // against the headline.
            content.setCustomSpacing(Sumi.Spacing.m, after: iconView)
        }

        if let title = title, !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = Sumi.Font.bodyEmphasised().sumiSized(17)
            titleLabel.textColor = Sumi.Color.textPrimary
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            content.addArrangedSubview(titleLabel)
        }

        if let message = message, !message.isEmpty {
            // LinkAwareLabel for tap-on-link support. Plain
            // `.plain(...)` messages still pass through but
            // skip the hit-testing path internally.
            let messageLabel = LinkAwareLabel()
            messageLabel.attributedText = Sumi.render(
                message,
                context: Sumi.RichTextContext(
                    baseFont: Sumi.Font.body().sumiSized(14),
                    textColor: Sumi.Color.textSecondary,
                    accent: Sumi.Color.accent,
                    codeBackgroundColor: Sumi.Color.surfaceSubtle,
                    alignment: .center
                )
            )
            messageLabel.textAlignment = .center
            messageLabel.numberOfLines = 0
            messageLabel.onLinkTap = { [weak self] url in
                self?.linkHandler?(url)
            }
            content.addArrangedSubview(messageLabel)
        }

        // Custom content slot — caller-provided arbitrary view
        // sits between message and the action buttons. Used for
        // tables (SumiTable), inline charts, custom previews,
        // etc. The slot doesn't enforce any visual constraints
        // beyond stack positioning — caller owns the embedded
        // view's intrinsic size.
        if let customContent {
            customContent.translatesAutoresizingMaskIntoConstraints = false
            content.addArrangedSubview(customContent)
            content.setCustomSpacing(Sumi.Spacing.m, after: customContent)
        }

        // Error label — last child of `content`. Hidden by
        // default; shown when an `asyncHandler` throws.
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = Sumi.Font.caption()
        errorLabel.textColor = Sumi.Color.danger
        errorLabel.textAlignment = .center
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        content.addArrangedSubview(errorLabel)

        cardClip.addSubview(content)
        // When an icon is present, pull the content up slightly
        // — icon + title + message stack is taller, and the
        // standard xl top padding makes the card feel bottom-
        // heavy.
        let topInset: CGFloat = (icon != nil) ? Sumi.Spacing.l : Sumi.Spacing.xl
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: topInset),
            content.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            content.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // iOS convention: non-cancel actions first in the order
        // given, cancel last in vertical layout. In horizontal
        // layout (exactly 2), cancel is placed on the left,
        // primary on the right.
        let useHorizontal = actions.count == 2
        let orderedActions: [Alert.Action] = {
            let nonCancel = actions.filter { $0.style != .cancel }
            let cancel = actions.filter { $0.style == .cancel }
            return useHorizontal ? cancel + nonCancel : nonCancel + cancel
        }()
        let emphasisedIndex: Int? = {
            for (i, a) in orderedActions.enumerated().reversed() where a.style == .primary {
                return i
            }
            // Fall back to last default if no explicit primary.
            for (i, a) in orderedActions.enumerated().reversed()
                where a.style == .default {
                return i
            }
            return nil
        }()

        let buttonsView = AlertButtonsView(
            actions: orderedActions,
            emphasisedIndex: emphasisedIndex,
            layout: useHorizontal ? .horizontal : .vertical,
            onPick: { [weak self] action in self?.handlePick(action) }
        )
        self.buttonsView = buttonsView
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        cardClip.addSubview(buttonsView)
        NSLayoutConstraint.activate([
            buttonsView.topAnchor.constraint(equalTo: content.bottomAnchor, constant: Sumi.Spacing.l),
            buttonsView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor),
            buttonsView.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor)
        ])
    }

    /// Routes a picked action to either the async path (if
    /// `asyncHandler` is set) or the immediate-complete path.
    private func handlePick(_ action: Alert.Action) {
        guard let handler = action.asyncHandler else {
            // Sync path: dismiss immediately. The error label,
            // if visible from a prior failed try, stays put —
            // the whole card is about to fade out anyway, and
            // hiding it first would shrink the card a beat
            // before the dismiss animation runs (visible as
            // a two-step "shrink then fade").
            complete(with: action)
            return
        }

        // Async path: clear any leftover error from a previous
        // failed try before starting a new attempt — otherwise
        // the user sees both the old error AND the new spinner.
        if !errorLabel.isHidden {
            errorLabel.isHidden = true
            errorLabel.text = nil
        }
        // Spin the button, gate input, run handler.
        buttonsView?.startLoading(for: action)
        asyncTask = Task { [weak self] in
            do {
                try await handler()
                guard let self else { return }
                self.complete(with: action)
            } catch {
                guard let self else { return }
                self.showError(error)
                self.buttonsView?.stopLoading()
            }
            self?.asyncTask = nil
        }
    }

    private func showError(_ error: Error) {
        // Localised description if available, else the type
        // name as a fallback. Short — the alert is small.
        let text = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        errorLabel.text = text
        // Animate height change so the new label slots in
        // gracefully. Spring damping high enough to not bounce.
        let animations: () -> Void = {
            self.errorLabel.isHidden = false
            self.card.superview?.layoutIfNeeded()
        }
        if Sumi.Motion.isReduced {
            animations()
            applyShadowPath()
        } else {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.95,
                initialSpringVelocity: 0.3,
                options: [.allowUserInteraction],
                animations: animations
            ) { _ in
                // Re-fit shadow to the now-taller card.
                self.applyShadowPath()
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func complete(with action: Alert.Action?) {
        guard !didComplete else { return }
        didComplete = true
        asyncTask?.cancel()
        // Reduce Motion: pure fade out, no scale-down.
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(action)
            Self.live.removeAll { $0 === self }
        }
    }
}

// MARK: - Text alert presentation
//
// Mirror of `AlertPresentation` with an inset text field
// between message and buttons. Auto-focuses the field on
// appear, shifts the card up when the keyboard would cover
// it, and reads the field's text at action time so each
// button pick carries the final value back to the caller.
//
// Kept as a separate class (rather than a mode-flag on
// AlertPresentation) because the keyboard observers,
// first-responder management, and lifetime of the
// `UITextField` belong to ONE presentation case — bolting
// them onto the plain alert would complicate every code
// path for a feature only the text variant uses.

@MainActor
final class TextAlertPresentation {

    private static var live: [TextAlertPresentation] = []

    private let title: String?
    private let message: String?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let textFieldConfig: Alert.TextFieldConfig
    private let actions: [Alert.Action]
    private let completion: (Alert.TextPick?) -> Void

    private let dimmer = UIView()
    // Two-layer card to keep press-overlay clipping clean —
    // outer owns shadow, inner clips to rounded shape. See
    // `AlertPresentation` for the full rationale; same pattern.
    private let card = UIView()
    private let cardClip = UIView()
    private let textField = UITextField()
    private var cardCenterY: NSLayoutConstraint?
    private var didComplete = false
    private weak var hostWindow: UIWindow?

    init(
        title: String?,
        message: String?,
        icon: UIImage?,
        iconTint: UIColor?,
        textField: Alert.TextFieldConfig,
        actions: [Alert.Action],
        completion: @escaping (Alert.TextPick?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.textFieldConfig = textField
        self.actions = actions
        self.completion = completion
    }

    // MARK: Present

    func attach(to window: UIWindow) {
        Self.live.append(self)
        self.hostWindow = window

        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        let centerY = card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20)
        self.cardCenterY = centerY
        NSLayoutConstraint.activate([
            centerY,
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 280)
        ])

        // Reduce Motion: skip the scale-in. The keyboard slide
        // is system-driven and respects Reduce Motion already
        // (Apple shortens it), so this is the only decorative
        // bit we control.
        if Sumi.Motion.isReduced {
            card.transform = .identity
        } else {
            card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }
        card.alpha = 0
        window.layoutIfNeeded()
        // Set shadow path to follow the rounded silhouette of
        // the inner `cardClip` (outer `card` is transparent and
        // rectangular). The inner clip already cuts press
        // overlays to the rounded shape — no `clipsToBounds`
        // needed on the outer card.
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath

        // CRITICAL ORDERING: subscribe to keyboard notifications
        // BEFORE becoming first responder.
        //
        // `becomeFirstResponder` synchronously dispatches the
        // `keyboardWillShowNotification` (immediately on iPad,
        // and on iPhone in tight timing windows). If we register
        // observers AFTER that call, the notification has
        // already fired and our handler never runs — the card
        // stays centered, behind the keyboard. Users see this as
        // "alert doesn't lift, I have to dismiss the keyboard
        // and tap the field again to make it lift".
        //
        // Tested across iPhone (timing varies, ~5% reproduction
        // rate) and iPad (deterministic, 100% reproduction in
        // landscape with hardware-keyboard-free pop). Reordering
        // fixes both.
        registerKeyboardObservers()
        textField.becomeFirstResponder()

        let animateBlock: () -> Void = {
            self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
            self.card.transform = .identity
            self.card.alpha = 1
        }
        let completionBlock: (Bool) -> Void = { _ in
            // Reserved for future post-present work.
        }
        if Sumi.Motion.isReduced {
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: animateBlock,
                completion: completionBlock
            )
        } else {
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction],
                animations: animateBlock,
                completion: completionBlock
            )
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: Card

    private func configureCard() {
        // Outer card — transparent, owns shadow only.
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        // Inner clip — visible card surface. All content goes
        // here so press feedback overlays on buttons are cut to
        // the rounded shape.
        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = Sumi.Radius.card
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = Sumi.Spacing.s
        content.alignment = .fill

        if let icon {
            let iconView = makeAlertIconView(icon: icon, tint: iconTint)
            content.addArrangedSubview(iconView)
            content.setCustomSpacing(Sumi.Spacing.m, after: iconView)
        }

        if let title = title, !title.isEmpty {
            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = Sumi.Font.bodyEmphasised().sumiSized(17)
            titleLabel.textColor = Sumi.Color.textPrimary
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0
            content.addArrangedSubview(titleLabel)
        }

        if let message = message, !message.isEmpty {
            let messageLabel = UILabel()
            messageLabel.text = message
            messageLabel.font = Sumi.Font.body().sumiSized(14)
            messageLabel.textColor = Sumi.Color.textSecondary
            messageLabel.textAlignment = .center
            messageLabel.numberOfLines = 0
            content.addArrangedSubview(messageLabel)
        }

        // Text field — inset rounded rect, surface-subtle bg.
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.placeholder = textFieldConfig.placeholder
        textField.text = textFieldConfig.initialValue
        textField.keyboardType = textFieldConfig.keyboardType
        textField.autocapitalizationType = textFieldConfig.autocapitalization
        textField.isSecureTextEntry = textFieldConfig.isSecure
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.font = Sumi.Font.body()
        textField.textColor = Sumi.Color.textPrimary
        textField.tintColor = Sumi.Color.accent
        textField.backgroundColor = Sumi.Color.surfaceSubtle
        textField.layer.cornerRadius = 10
        textField.layer.cornerCurve = .continuous
        // Inset for left/right text padding — UITextField has
        // no native horizontal-padding API, so use leftView /
        // rightView of fixed width as spacers.
        let pad: CGFloat = Sumi.Spacing.m
        let leftPad = UIView(frame: CGRect(x: 0, y: 0, width: pad, height: 40))
        let rightPad = UIView(frame: CGRect(x: 0, y: 0, width: pad, height: 40))
        textField.leftView = leftPad
        textField.rightView = rightPad
        textField.leftViewMode = .always
        textField.rightViewMode = .always
        // Return-key handler — fires primary action (last
        // non-cancel action) on Enter. Matches native Apple
        // alert behaviour.
        textField.returnKeyType = .done
        textField.addTarget(self, action: #selector(returnKeyPressed), for: .editingDidEndOnExit)
        textField.heightAnchor.constraint(equalToConstant: 40).isActive = true

        let fieldHolder = UIView()
        fieldHolder.translatesAutoresizingMaskIntoConstraints = false
        fieldHolder.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: fieldHolder.topAnchor),
            textField.bottomAnchor.constraint(equalTo: fieldHolder.bottomAnchor),
            textField.leadingAnchor.constraint(equalTo: fieldHolder.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: fieldHolder.trailingAnchor)
        ])
        content.addArrangedSubview(fieldHolder)
        content.setCustomSpacing(Sumi.Spacing.m, after: content.arrangedSubviews[content.arrangedSubviews.count - 2])

        cardClip.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: Sumi.Spacing.xl),
            content.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            content.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // Buttons — same ordering rules as `AlertPresentation`.
        let useHorizontal = actions.count == 2
        let orderedActions: [Alert.Action] = {
            let nonCancel = actions.filter { $0.style != .cancel }
            let cancel = actions.filter { $0.style == .cancel }
            return useHorizontal ? cancel + nonCancel : nonCancel + cancel
        }()
        let emphasisedIndex: Int? = {
            for (i, a) in orderedActions.enumerated().reversed() where a.style == .primary {
                return i
            }
            for (i, a) in orderedActions.enumerated().reversed()
                where a.style == .default {
                return i
            }
            return nil
        }()

        let buttonsView = AlertButtonsView(
            actions: orderedActions,
            emphasisedIndex: emphasisedIndex,
            layout: useHorizontal ? .horizontal : .vertical,
            onPick: { [weak self] action in self?.completeWithAction(action) }
        )
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        cardClip.addSubview(buttonsView)
        NSLayoutConstraint.activate([
            buttonsView.topAnchor.constraint(equalTo: content.bottomAnchor, constant: Sumi.Spacing.l),
            buttonsView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor),
            buttonsView.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor)
        ])
    }

    // MARK: Keyboard

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ note: Notification) {
        guard let window = hostWindow,
              let frameValue = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let durationValue = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        // Centre the card in the visible CONTENT area — between
        // the top safe-area inset (notch / status bar) and the
        // keyboard's top edge. Computing centre from the
        // keyboard alone would ignore the safe-area inset and
        // put the card ~24pt above the visual centre on
        // notched iPhones.
        //
        // Math:
        //   visibleCentreY = (safeTop + keyboardTop) / 2
        //   constant       = visibleCentreY - windowCentreY
        let keyboardFrameInWindow = window.convert(frameValue.cgRectValue, from: nil)
        let keyboardTop = keyboardFrameInWindow.minY
        let safeTop = window.safeAreaInsets.top
        let visibleCentreY = (safeTop + keyboardTop) / 2
        let target = visibleCentreY - window.bounds.height / 2
        UIView.animate(withDuration: durationValue) {
            self.cardCenterY?.constant = target
            window.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        guard let window = hostWindow,
              let durationValue = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        // Back to the resting position: slightly above window
        // centre for the "optical centring" feel that bottom-
        // heavy modals need to feel balanced.
        UIView.animate(withDuration: durationValue) {
            self.cardCenterY?.constant = -20
            window.layoutIfNeeded()
        }
    }

    @objc private func returnKeyPressed() {
        // Fire the same action `AlertButtonsView` would treat
        // as "emphasised" — last non-cancel action.
        let nonCancel = actions.filter { $0.style != .cancel }
        guard let primary = nonCancel.last else { return }
        completeWithAction(primary)
    }

    // MARK: Completion

    private func completeWithAction(_ action: Alert.Action) {
        guard !didComplete else { return }
        didComplete = true
        let pick: Alert.TextPick? = (action.style == .cancel)
            ? nil
            : Alert.TextPick(action: action, text: textField.text ?? "")
        animateOut(picked: pick)
    }

    private func animateOut(picked: Alert.TextPick?) {
        textField.resignFirstResponder()
        NotificationCenter.default.removeObserver(self)
        // Reduce Motion: pure fade out, no scale-down.
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(picked)
            Self.live.removeAll { $0 === self }
        }
    }
}

// MARK: - Form alert presentation (multi text fields)
//
// Generalises `TextAlertPresentation` to N text fields stacked
// vertically. Tab order: first field auto-focuses on appear,
// Return on a non-last field focuses the next, Return on the
// last field fires the primary action.
//
// Keyboard handling is the same as TextAlertPresentation —
// card recentres in visible area above the keyboard. The
// returned `FormPick.values` mirrors the input `textFields:`
// order, so the caller can decompose by index.

@MainActor
final class FormAlertPresentation: NSObject, UITextFieldDelegate {

    private static var live: [FormAlertPresentation] = []

    private let title: String?
    private let message: String?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let fieldConfigs: [Alert.TextFieldConfig]
    private let actions: [Alert.Action]
    private let completion: (Alert.FormPick?) -> Void

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private var textFields: [UITextField] = []
    private var cardCenterY: NSLayoutConstraint?
    private var didComplete = false
    private weak var hostWindow: UIWindow?

    init(
        title: String?,
        message: String?,
        icon: UIImage?,
        iconTint: UIColor?,
        textFields: [Alert.TextFieldConfig],
        actions: [Alert.Action],
        completion: @escaping (Alert.FormPick?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.fieldConfigs = textFields
        self.actions = actions
        self.completion = completion
        super.init()
    }

    func attach(to window: UIWindow) {
        Self.live.append(self)
        self.hostWindow = window
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        let centerY = card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20)
        self.cardCenterY = centerY
        NSLayoutConstraint.activate([
            centerY,
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 280)
        ])

        if Sumi.Motion.isReduced {
            card.transform = .identity
        } else {
            card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        }
        card.alpha = 0
        window.layoutIfNeeded()
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath

        // Register keyboard observers BEFORE first responder —
        // see `TextAlertPresentation.attach()` for the full
        // story. iPad pops keyboard synchronously inside
        // `becomeFirstResponder`; observers must already be
        // attached or we miss the show notification and the
        // alert stays centered behind the keyboard.
        registerKeyboardObservers()
        textFields.first?.becomeFirstResponder()

        let animateBlock: () -> Void = {
            self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
            self.card.transform = .identity
            self.card.alpha = 1
        }
        let completionBlock: (Bool) -> Void = { _ in
            // Reserved for future post-present work.
        }
        if Sumi.Motion.isReduced {
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: animateBlock,
                completion: completionBlock
            )
        } else {
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction],
                animations: animateBlock,
                completion: completionBlock
            )
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func configureCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = Sumi.Radius.card
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = Sumi.Spacing.s
        content.alignment = .fill

        if let icon {
            let iconView = makeAlertIconView(icon: icon, tint: iconTint)
            content.addArrangedSubview(iconView)
            content.setCustomSpacing(Sumi.Spacing.m, after: iconView)
        }
        if let title = title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = Sumi.Font.bodyEmphasised().sumiSized(17)
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = .center
            l.numberOfLines = 0
            content.addArrangedSubview(l)
        }
        if let message = message, !message.isEmpty {
            let l = UILabel()
            l.text = message
            l.font = Sumi.Font.body().sumiSized(14)
            l.textColor = Sumi.Color.textSecondary
            l.textAlignment = .center
            l.numberOfLines = 0
            content.addArrangedSubview(l)
        }

        // Build a text field per config. Each gets `returnKeyType
        // = .next` until the LAST, which gets `.done`. Delegate
        // forwards return events to focus-next-or-fire-primary.
        for (idx, config) in fieldConfigs.enumerated() {
            let tf = UITextField()
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.placeholder = config.placeholder
            tf.text = config.initialValue
            tf.keyboardType = config.keyboardType
            tf.autocapitalizationType = config.autocapitalization
            tf.isSecureTextEntry = config.isSecure
            tf.autocorrectionType = .no
            tf.spellCheckingType = .no
            tf.font = Sumi.Font.body()
            tf.textColor = Sumi.Color.textPrimary
            tf.tintColor = Sumi.Color.accent
            tf.backgroundColor = Sumi.Color.surfaceSubtle
            tf.layer.cornerRadius = 10
            tf.layer.cornerCurve = .continuous
            let pad: CGFloat = Sumi.Spacing.m
            let leftPad = UIView(frame: CGRect(x: 0, y: 0, width: pad, height: 40))
            let rightPad = UIView(frame: CGRect(x: 0, y: 0, width: pad, height: 40))
            tf.leftView = leftPad
            tf.rightView = rightPad
            tf.leftViewMode = .always
            tf.rightViewMode = .always
            tf.returnKeyType = (idx == fieldConfigs.count - 1) ? .done : .next
            tf.delegate = self
            tf.heightAnchor.constraint(equalToConstant: 40).isActive = true
            textFields.append(tf)
            content.addArrangedSubview(tf)
        }
        // Custom spacing before the LAST text field's neighbour
        // (the message above the first field) — keeps fields
        // visually close to each other and slightly detached
        // from the message.
        if let lastBeforeFields = content.arrangedSubviews
            .dropLast(fieldConfigs.count).last {
            content.setCustomSpacing(Sumi.Spacing.m, after: lastBeforeFields)
        }

        cardClip.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: Sumi.Spacing.xl),
            content.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            content.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        let useHorizontal = actions.count == 2
        let orderedActions: [Alert.Action] = {
            let nonCancel = actions.filter { $0.style != .cancel }
            let cancel = actions.filter { $0.style == .cancel }
            return useHorizontal ? cancel + nonCancel : nonCancel + cancel
        }()
        let emphasisedIndex: Int? = {
            for (i, a) in orderedActions.enumerated().reversed() where a.style == .primary {
                return i
            }
            for (i, a) in orderedActions.enumerated().reversed()
                where a.style == .default {
                return i
            }
            return nil
        }()

        let buttonsView = AlertButtonsView(
            actions: orderedActions,
            emphasisedIndex: emphasisedIndex,
            layout: useHorizontal ? .horizontal : .vertical,
            onPick: { [weak self] action in self?.completeWithAction(action) }
        )
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        cardClip.addSubview(buttonsView)
        NSLayoutConstraint.activate([
            buttonsView.topAnchor.constraint(equalTo: content.bottomAnchor, constant: Sumi.Spacing.l),
            buttonsView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor),
            buttonsView.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor)
        ])
    }

    // MARK: UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard let idx = textFields.firstIndex(of: textField) else { return true }
        if idx < textFields.count - 1 {
            textFields[idx + 1].becomeFirstResponder()
        } else {
            // Last field → fire primary action.
            let nonCancel = actions.filter { $0.style != .cancel }
            if let primary = nonCancel.last {
                completeWithAction(primary)
            } else {
                textField.resignFirstResponder()
            }
        }
        return true
    }

    // MARK: Keyboard (mirrors TextAlertPresentation)

    private func registerKeyboardObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil
        )
    }

    @objc private func keyboardWillShow(_ note: Notification) {
        guard let window = hostWindow,
              let frameValue = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue,
              let durationValue = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        let keyboardFrameInWindow = window.convert(frameValue.cgRectValue, from: nil)
        let keyboardTop = keyboardFrameInWindow.minY
        let safeTop = window.safeAreaInsets.top
        let visibleCentreY = (safeTop + keyboardTop) / 2
        let target = visibleCentreY - window.bounds.height / 2

        // `keyboardWillShowNotification` fires not just on
        // initial keyboard appearance but ALSO when the
        // keyboard's frame changes between fields — most
        // notably when QuickType / autofill suggestions
        // appear/disappear (a non-secure field can show
        // password autofill, a secure field can't; their
        // suggestion bars differ in height). Re-running the
        // re-centre animation on every such delta causes a
        // visible jerk when the user taps between username
        // and password inputs. Skip if the change is small —
        // the visual cost of a slightly-off centre is much
        // less than the jerk of an unprovoked re-animation.
        if let current = cardCenterY?.constant, abs(current - target) < 24 {
            return
        }

        UIView.animate(withDuration: durationValue) {
            self.cardCenterY?.constant = target
            window.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ note: Notification) {
        guard let window = hostWindow,
              let durationValue = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        UIView.animate(withDuration: durationValue) {
            self.cardCenterY?.constant = -20
            window.layoutIfNeeded()
        }
    }

    // MARK: Completion

    private func completeWithAction(_ action: Alert.Action) {
        guard !didComplete else { return }
        didComplete = true
        let pick: Alert.FormPick? = (action.style == .cancel)
            ? nil
            : Alert.FormPick(action: action, values: textFields.map { $0.text ?? "" })
        animateOut(picked: pick)
    }

    private func animateOut(picked: Alert.FormPick?) {
        for tf in textFields { tf.resignFirstResponder() }
        NotificationCenter.default.removeObserver(self)
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(picked)
            Self.live.removeAll { $0 === self }
        }
    }
}

// MARK: - Hold-to-confirm alert presentation
//
// Card layout: standard header (icon + title + message) +
// HoldToConfirmButton + optional Cancel link. The hold button
// owns its own touch tracking and fires `onConfirmed`; the
// alert just dismisses with `true`. Cancel dismisses with
// `false`. Tap-outside-dimmer also dismisses with `false`.

@MainActor
final class HoldAlertPresentation {

    private static var live: [HoldAlertPresentation] = []

    private let title: String?
    private let message: String?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let holdAction: Alert.HoldAction
    private let cancelTitle: String?
    private let completion: (Bool) -> Void

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private var didComplete = false

    init(
        title: String?,
        message: String?,
        icon: UIImage?,
        iconTint: UIColor?,
        holdAction: Alert.HoldAction,
        cancelTitle: String?,
        completion: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.holdAction = holdAction
        self.cancelTitle = cancelTitle
        self.completion = completion
    }

    func attach(to window: UIWindow) {
        Self.live.append(self)
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])
        // Tap-outside-dimmer cancels.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmerTapped))
        dimmer.addGestureRecognizer(tap)

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20),
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 280)
        ])

        if Sumi.Motion.isReduced {
            card.transform = .identity
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.alpha = 1
            }
        } else {
            card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.transform = .identity
                self.card.alpha = 1
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func applyShadowPath() {
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath
    }

    private func configureCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = Sumi.Radius.card
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        let header = UIStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .vertical
        header.spacing = Sumi.Spacing.s
        header.alignment = .fill

        if let icon {
            let iconView = makeAlertIconView(icon: icon, tint: iconTint)
            header.addArrangedSubview(iconView)
            header.setCustomSpacing(Sumi.Spacing.m, after: iconView)
        }
        if let title = title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = Sumi.Font.bodyEmphasised().sumiSized(17)
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = .center
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        if let message = message, !message.isEmpty {
            let l = UILabel()
            l.text = message
            l.font = Sumi.Font.body().sumiSized(14)
            l.textColor = Sumi.Color.textSecondary
            l.textAlignment = .center
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        cardClip.addSubview(header)
        let topInset: CGFloat = (icon != nil) ? Sumi.Spacing.l : Sumi.Spacing.xl
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: topInset),
            header.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            header.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // Hold-to-confirm button
        let actionColor: UIColor
        switch holdAction.style {
        case .destructive: actionColor = Sumi.Color.danger
        case .primary, .default: actionColor = Sumi.Color.accent
        case .cancel: actionColor = Sumi.Color.textSecondary  // unusual but valid
        }
        let holdButton = HoldToConfirmButton(
            title: holdAction.title,
            duration: holdAction.duration,
            fillColor: actionColor
        )
        holdButton.onConfirmed = { [weak self] in self?.complete(confirmed: true) }
        cardClip.addSubview(holdButton)
        NSLayoutConstraint.activate([
            holdButton.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Sumi.Spacing.l),
            holdButton.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            holdButton.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // Optional Cancel link
        if let cancelTitle, !cancelTitle.isEmpty {
            let cancelBtn = UIButton(type: .system)
            cancelBtn.translatesAutoresizingMaskIntoConstraints = false
            cancelBtn.setTitle(cancelTitle, for: .normal)
            cancelBtn.setTitleColor(Sumi.Color.textSecondary, for: .normal)
            cancelBtn.titleLabel?.font = Sumi.Font.body()
            cancelBtn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            cardClip.addSubview(cancelBtn)
            NSLayoutConstraint.activate([
                cancelBtn.topAnchor.constraint(equalTo: holdButton.bottomAnchor, constant: Sumi.Spacing.s),
                cancelBtn.centerXAnchor.constraint(equalTo: cardClip.centerXAnchor),
                cancelBtn.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor, constant: -Sumi.Spacing.l),
                cancelBtn.heightAnchor.constraint(equalToConstant: 36)
            ])
        } else {
            holdButton.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor, constant: -Sumi.Spacing.l).isActive = true
        }
    }

    @objc private func dimmerTapped() { complete(confirmed: false) }
    @objc private func cancelTapped() { complete(confirmed: false) }

    private func complete(confirmed: Bool) {
        guard !didComplete else { return }
        didComplete = true
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(confirmed)
            Self.live.removeAll { $0 === self }
        }
    }
}

// MARK: - Expandable alert presentation
//
// Basic alert + an inline "Show details ▼" disclosure that
// reveals a scrollable technical-details block. Card height
// animates between collapsed and expanded states. The toggle
// keeps the alert lightweight by default while making the
// extra context one tap away.

@MainActor
final class ExpandableAlertPresentation {

    private static var live: [ExpandableAlertPresentation] = []

    private let title: String?
    private let message: String?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let details: String
    private let actions: [Alert.Action]
    private let completion: (Alert.Action?) -> Void

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private let detailsContainer = UIView()
    private let detailsText = UITextView()
    private let disclosureButton = UIButton(type: .system)
    private var detailsHeight: NSLayoutConstraint!
    private var isExpanded = false
    private var didComplete = false
    private weak var hostWindow: UIWindow?

    init(
        title: String?,
        message: String?,
        icon: UIImage?,
        iconTint: UIColor?,
        details: String,
        actions: [Alert.Action],
        completion: @escaping (Alert.Action?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.details = details
        self.actions = actions
        self.completion = completion
    }

    func attach(to window: UIWindow) {
        Self.live.append(self)
        self.hostWindow = window
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20),
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 280)
        ])

        if Sumi.Motion.isReduced {
            card.transform = .identity
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.alpha = 1
            }
        } else {
            card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.transform = .identity
                self.card.alpha = 1
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func applyShadowPath() {
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath
    }

    private func configureCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = Sumi.Radius.card
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        let header = UIStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .vertical
        header.spacing = Sumi.Spacing.s
        header.alignment = .fill

        if let icon {
            let iconView = makeAlertIconView(icon: icon, tint: iconTint)
            header.addArrangedSubview(iconView)
            header.setCustomSpacing(Sumi.Spacing.m, after: iconView)
        }
        if let title = title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = Sumi.Font.bodyEmphasised().sumiSized(17)
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = .center
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        if let message = message, !message.isEmpty {
            let l = UILabel()
            l.text = message
            l.font = Sumi.Font.body().sumiSized(14)
            l.textColor = Sumi.Color.textSecondary
            l.textAlignment = .center
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        cardClip.addSubview(header)
        let topInset: CGFloat = (icon != nil) ? Sumi.Spacing.l : Sumi.Spacing.xl
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: topInset),
            header.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            header.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // Disclosure button: "Show details ▼" / "Hide details ▲"
        disclosureButton.translatesAutoresizingMaskIntoConstraints = false
        disclosureButton.tintColor = Sumi.Color.accent
        disclosureButton.titleLabel?.font = Sumi.Font.body().sumiSized(13)
        disclosureButton.contentHorizontalAlignment = .center
        disclosureButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        refreshDisclosureTitle()
        cardClip.addSubview(disclosureButton)
        NSLayoutConstraint.activate([
            disclosureButton.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Sumi.Spacing.m),
            disclosureButton.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            disclosureButton.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l),
            disclosureButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        // Details container — height animates between 0 (collapsed)
        // and natural content height (expanded). Scrollable text
        // view inside so long content doesn't blow up the card.
        detailsContainer.translatesAutoresizingMaskIntoConstraints = false
        detailsContainer.backgroundColor = Sumi.Color.surfaceSubtle
        detailsContainer.layer.cornerRadius = 10
        detailsContainer.layer.cornerCurve = .continuous
        detailsContainer.clipsToBounds = true
        cardClip.addSubview(detailsContainer)

        detailsText.translatesAutoresizingMaskIntoConstraints = false
        detailsText.text = details
        detailsText.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        detailsText.textColor = Sumi.Color.textPrimary
        detailsText.backgroundColor = .clear
        detailsText.isEditable = false
        detailsText.isSelectable = true
        detailsText.textContainerInset = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        detailsText.showsVerticalScrollIndicator = true
        detailsText.alwaysBounceVertical = false
        detailsContainer.addSubview(detailsText)
        NSLayoutConstraint.activate([
            detailsText.topAnchor.constraint(equalTo: detailsContainer.topAnchor),
            detailsText.bottomAnchor.constraint(equalTo: detailsContainer.bottomAnchor),
            detailsText.leadingAnchor.constraint(equalTo: detailsContainer.leadingAnchor),
            detailsText.trailingAnchor.constraint(equalTo: detailsContainer.trailingAnchor)
        ])

        detailsHeight = detailsContainer.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            detailsHeight,
            detailsContainer.topAnchor.constraint(equalTo: disclosureButton.bottomAnchor, constant: Sumi.Spacing.s),
            detailsContainer.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            detailsContainer.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // Buttons row
        let useHorizontal = actions.count == 2
        let orderedActions: [Alert.Action] = {
            let nonCancel = actions.filter { $0.style != .cancel }
            let cancel = actions.filter { $0.style == .cancel }
            return useHorizontal ? cancel + nonCancel : nonCancel + cancel
        }()
        let emphasisedIndex: Int? = {
            for (i, a) in orderedActions.enumerated().reversed() where a.style == .primary {
                return i
            }
            for (i, a) in orderedActions.enumerated().reversed()
                where a.style == .default {
                return i
            }
            return nil
        }()

        let buttonsView = AlertButtonsView(
            actions: orderedActions,
            emphasisedIndex: emphasisedIndex,
            layout: useHorizontal ? .horizontal : .vertical,
            onPick: { [weak self] action in self?.complete(with: action) }
        )
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        cardClip.addSubview(buttonsView)
        NSLayoutConstraint.activate([
            buttonsView.topAnchor.constraint(equalTo: detailsContainer.bottomAnchor, constant: Sumi.Spacing.l),
            buttonsView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor),
            buttonsView.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor)
        ])
    }

    private func refreshDisclosureTitle() {
        let chevron = isExpanded ? "▲" : "▼"
        let title = isExpanded ? "Hide details" : "Show details"
        disclosureButton.setTitle("\(title)  \(chevron)", for: .normal)
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
        refreshDisclosureTitle()
        // Cap expansion at 180pt so long traces don't blow the
        // card past sensible screen real estate — scroll handles
        // overflow inside.
        let target: CGFloat = isExpanded ? 180 : 0
        let heightDelta = target - detailsHeight.constant

        if Sumi.Motion.isReduced {
            detailsHeight.constant = target
            card.superview?.layoutIfNeeded()
            applyShadowPath()
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }

        // Animate the shadow path IN PARALLEL with the card-
        // height animation. Setting `shadowPath` only at the
        // animation's completion would leave the shadow stuck
        // at the old silhouette for the duration and snap to
        // the new one at the end — a visible lag.
        //
        // How it lines up:
        //   • Compute the post-animation card bounds from the
        //     known heightDelta (no temporary layout passes —
        //     other content is fixed-height, so card.height
        //     just grows/shrinks by exactly the delta).
        //   • Drive `layer.shadowPath` with a CABasicAnimation
        //     matching the UIView.animate duration and curve.
        //   • Use `.curveEaseInOut` for the layout animation
        //     (not spring) so the two animations have an
        //     identical timing function — a spring would
        //     diverge from the path's linear-ish interpolation
        //     mid-animation.
        let duration = Sumi.Motion.standard
        let oldBounds = card.bounds
        let newBounds = CGRect(
            x: 0, y: 0,
            width: oldBounds.width,
            height: oldBounds.height + heightDelta
        )
        let newPath = UIBezierPath(
            roundedRect: newBounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath
        let oldPath = card.layer.shadowPath ?? UIBezierPath(
            roundedRect: oldBounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath

        let pathAnim = CABasicAnimation(keyPath: "shadowPath")
        pathAnim.fromValue = oldPath
        pathAnim.toValue = newPath
        pathAnim.duration = duration
        pathAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        card.layer.shadowPath = newPath
        card.layer.add(pathAnim, forKey: "shadowPath")

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .allowUserInteraction]
        ) {
            self.detailsHeight.constant = target
            self.card.superview?.layoutIfNeeded()
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func complete(with action: Alert.Action) {
        guard !didComplete else { return }
        didComplete = true
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(action.style == .cancel ? nil : action)
            Self.live.removeAll { $0 === self }
        }
    }
}

// MARK: - Stepper alert presentation
//
// Numeric [-] [VALUE] [+] control between message and buttons.
// Tap +/- to change by `step`. Long-press accelerates (50ms
// repeat after 400ms hold) — matches native UIStepper feel
// without UIStepper's limited styling.

@MainActor
final class StepperAlertPresentation {

    private static var live: [StepperAlertPresentation] = []

    private let title: String?
    private let message: String?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let stepperConfig: Alert.StepperConfig
    private let actions: [Alert.Action]
    private let completion: (Alert.StepperPick?) -> Void

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private var currentValue: Int
    private weak var valueLabel: UILabel?
    private weak var minusButton: UIButton?
    private weak var plusButton: UIButton?
    private var didComplete = false

    init(
        title: String?,
        message: String?,
        icon: UIImage?,
        iconTint: UIColor?,
        stepper: Alert.StepperConfig,
        actions: [Alert.Action],
        completion: @escaping (Alert.StepperPick?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.stepperConfig = stepper
        self.actions = actions
        self.completion = completion
        self.currentValue = stepper.initial
    }

    func attach(to window: UIWindow) {
        Self.live.append(self)
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20),
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 280)
        ])

        if Sumi.Motion.isReduced {
            card.transform = .identity
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.alpha = 1
            }
        } else {
            card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.transform = .identity
                self.card.alpha = 1
            }
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func applyShadowPath() {
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath
    }

    private func configureCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = Sumi.Radius.card
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        let header = UIStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .vertical
        header.spacing = Sumi.Spacing.s
        header.alignment = .fill

        if let icon {
            let iconView = makeAlertIconView(icon: icon, tint: iconTint)
            header.addArrangedSubview(iconView)
            header.setCustomSpacing(Sumi.Spacing.m, after: iconView)
        }
        if let title = title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = Sumi.Font.bodyEmphasised().sumiSized(17)
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = .center
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        if let message = message, !message.isEmpty {
            let l = UILabel()
            l.text = message
            l.font = Sumi.Font.body().sumiSized(14)
            l.textColor = Sumi.Color.textSecondary
            l.textAlignment = .center
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        cardClip.addSubview(header)
        let topInset: CGFloat = (icon != nil) ? Sumi.Spacing.l : Sumi.Spacing.xl
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: topInset),
            header.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            header.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // Stepper row: [-]  VALUE  [+]
        let stepperRow = UIView()
        stepperRow.translatesAutoresizingMaskIntoConstraints = false

        let minus = makeStepperButton(symbol: "minus")
        minus.addTarget(self, action: #selector(decrement), for: .touchUpInside)
        stepperRow.addSubview(minus)
        self.minusButton = minus

        let plus = makeStepperButton(symbol: "plus")
        plus.addTarget(self, action: #selector(increment), for: .touchUpInside)
        stepperRow.addSubview(plus)
        self.plusButton = plus

        let value = UILabel()
        value.translatesAutoresizingMaskIntoConstraints = false
        value.font = Sumi.Font.title()
        value.textColor = Sumi.Color.textPrimary
        value.textAlignment = .center
        value.adjustsFontSizeToFitWidth = true
        value.minimumScaleFactor = 0.7
        stepperRow.addSubview(value)
        self.valueLabel = value

        NSLayoutConstraint.activate([
            minus.leadingAnchor.constraint(equalTo: stepperRow.leadingAnchor),
            minus.centerYAnchor.constraint(equalTo: stepperRow.centerYAnchor),
            minus.widthAnchor.constraint(equalToConstant: 44),
            minus.heightAnchor.constraint(equalToConstant: 44),

            plus.trailingAnchor.constraint(equalTo: stepperRow.trailingAnchor),
            plus.centerYAnchor.constraint(equalTo: stepperRow.centerYAnchor),
            plus.widthAnchor.constraint(equalToConstant: 44),
            plus.heightAnchor.constraint(equalToConstant: 44),

            value.leadingAnchor.constraint(equalTo: minus.trailingAnchor, constant: Sumi.Spacing.s),
            value.trailingAnchor.constraint(equalTo: plus.leadingAnchor, constant: -Sumi.Spacing.s),
            value.topAnchor.constraint(equalTo: stepperRow.topAnchor),
            value.bottomAnchor.constraint(equalTo: stepperRow.bottomAnchor)
        ])

        cardClip.addSubview(stepperRow)
        NSLayoutConstraint.activate([
            stepperRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Sumi.Spacing.l),
            stepperRow.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            stepperRow.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l),
            stepperRow.heightAnchor.constraint(equalToConstant: 56)
        ])

        refreshValueLabel()
        refreshButtonStates()

        // Buttons — same ordering as the basic alert.
        let useHorizontal = actions.count == 2
        let orderedActions: [Alert.Action] = {
            let nonCancel = actions.filter { $0.style != .cancel }
            let cancel = actions.filter { $0.style == .cancel }
            return useHorizontal ? cancel + nonCancel : nonCancel + cancel
        }()
        let emphasisedIndex: Int? = {
            for (i, a) in orderedActions.enumerated().reversed() where a.style == .primary {
                return i
            }
            for (i, a) in orderedActions.enumerated().reversed()
                where a.style == .default {
                return i
            }
            return nil
        }()

        let buttonsView = AlertButtonsView(
            actions: orderedActions,
            emphasisedIndex: emphasisedIndex,
            layout: useHorizontal ? .horizontal : .vertical,
            onPick: { [weak self] action in self?.complete(with: action) }
        )
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        cardClip.addSubview(buttonsView)
        NSLayoutConstraint.activate([
            buttonsView.topAnchor.constraint(equalTo: stepperRow.bottomAnchor, constant: Sumi.Spacing.l),
            buttonsView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor),
            buttonsView.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor)
        ])
    }

    private func makeStepperButton(symbol: String) -> UIButton {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.tintColor = Sumi.Color.accent
        btn.backgroundColor = Sumi.Color.surfaceSubtle
        btn.layer.cornerRadius = 10
        btn.layer.cornerCurve = .continuous
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        btn.setImage(UIImage(systemName: symbol, withConfiguration: config), for: .normal)
        return btn
    }

    @objc private func decrement() {
        let candidate = currentValue - stepperConfig.step
        guard candidate >= stepperConfig.range.lowerBound else { return }
        currentValue = candidate
        afterStep()
    }

    @objc private func increment() {
        let candidate = currentValue + stepperConfig.step
        guard candidate <= stepperConfig.range.upperBound else { return }
        currentValue = candidate
        afterStep()
    }

    private func afterStep() {
        refreshValueLabel()
        refreshButtonStates()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func refreshValueLabel() {
        if let suffix = stepperConfig.suffix {
            valueLabel?.text = "\(currentValue) \(suffix)"
        } else {
            valueLabel?.text = "\(currentValue)"
        }
    }

    private func refreshButtonStates() {
        minusButton?.isEnabled = currentValue - stepperConfig.step >= stepperConfig.range.lowerBound
        plusButton?.isEnabled = currentValue + stepperConfig.step <= stepperConfig.range.upperBound
        minusButton?.alpha = (minusButton?.isEnabled == true) ? 1.0 : 0.35
        plusButton?.alpha = (plusButton?.isEnabled == true) ? 1.0 : 0.35
    }

    private func complete(with action: Alert.Action) {
        guard !didComplete else { return }
        didComplete = true
        let pick: Alert.StepperPick? = (action.style == .cancel)
            ? nil
            : Alert.StepperPick(action: action, value: currentValue)
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(pick)
            Self.live.removeAll { $0 === self }
        }
    }
}

// MARK: - Toggle alert presentation
//
// Adds checkbox rows between message and buttons. State is
// tracked locally; the picked action returns it via TogglePick.
// The card chrome (dimmer, two-layer card, shadow, animations)
// mirrors AlertPresentation — only the middle content differs.

@MainActor
final class ToggleAlertPresentation {

    private static var live: [ToggleAlertPresentation] = []

    private let title: String?
    private let message: String?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let toggles: [Alert.ToggleOption]
    private let actions: [Alert.Action]
    private let completion: (Alert.TogglePick?) -> Void

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private var toggleStates: [String: Bool] = [:]
    private var didComplete = false

    init(
        title: String?,
        message: String?,
        icon: UIImage?,
        iconTint: UIColor?,
        toggles: [Alert.ToggleOption],
        actions: [Alert.Action],
        completion: @escaping (Alert.TogglePick?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.toggles = toggles
        self.actions = actions
        self.completion = completion
        for t in toggles { toggleStates[t.id] = t.initial }
    }

    func attach(to window: UIWindow) {
        Self.live.append(self)
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20),
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 280)
        ])

        if Sumi.Motion.isReduced {
            card.transform = .identity
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.alpha = 1
            }
        } else {
            card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.transform = .identity
                self.card.alpha = 1
            }
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func applyShadowPath() {
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath
    }

    private func configureCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = Sumi.Radius.card
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        let header = UIStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .vertical
        header.spacing = Sumi.Spacing.s
        header.alignment = .fill

        if let icon {
            let iconView = makeAlertIconView(icon: icon, tint: iconTint)
            header.addArrangedSubview(iconView)
            header.setCustomSpacing(Sumi.Spacing.m, after: iconView)
        }
        if let title = title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = Sumi.Font.bodyEmphasised().sumiSized(17)
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = .center
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        if let message = message, !message.isEmpty {
            let l = UILabel()
            l.text = message
            l.font = Sumi.Font.body().sumiSized(14)
            l.textColor = Sumi.Color.textSecondary
            l.textAlignment = .center
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        cardClip.addSubview(header)
        let topInset: CGFloat = (icon != nil) ? Sumi.Spacing.l : Sumi.Spacing.xl
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: topInset),
            header.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            header.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // Toggle rows — vertical stack between header and buttons.
        let togglesStack = UIStackView()
        togglesStack.translatesAutoresizingMaskIntoConstraints = false
        togglesStack.axis = .vertical
        togglesStack.spacing = 0
        togglesStack.alignment = .fill
        for option in toggles {
            let row = ToggleRow(option: option) { [weak self] isOn in
                self?.toggleStates[option.id] = isOn
            }
            togglesStack.addArrangedSubview(row)
        }
        cardClip.addSubview(togglesStack)
        NSLayoutConstraint.activate([
            togglesStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: Sumi.Spacing.l),
            togglesStack.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: Sumi.Spacing.l),
            togglesStack.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        // Buttons — same ordering rules as AlertPresentation.
        let useHorizontal = actions.count == 2
        let orderedActions: [Alert.Action] = {
            let nonCancel = actions.filter { $0.style != .cancel }
            let cancel = actions.filter { $0.style == .cancel }
            return useHorizontal ? cancel + nonCancel : nonCancel + cancel
        }()
        let emphasisedIndex: Int? = {
            for (i, a) in orderedActions.enumerated().reversed() where a.style == .primary {
                return i
            }
            for (i, a) in orderedActions.enumerated().reversed()
                where a.style == .default {
                return i
            }
            return nil
        }()

        let buttonsView = AlertButtonsView(
            actions: orderedActions,
            emphasisedIndex: emphasisedIndex,
            layout: useHorizontal ? .horizontal : .vertical,
            onPick: { [weak self] action in self?.complete(with: action) }
        )
        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        cardClip.addSubview(buttonsView)
        NSLayoutConstraint.activate([
            buttonsView.topAnchor.constraint(equalTo: togglesStack.bottomAnchor, constant: Sumi.Spacing.l),
            buttonsView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor),
            buttonsView.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor)
        ])
    }

    private func complete(with action: Alert.Action) {
        guard !didComplete else { return }
        didComplete = true
        let pick: Alert.TogglePick? = (action.style == .cancel)
            ? nil
            : Alert.TogglePick(action: action, toggles: toggleStates)
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(pick)
            Self.live.removeAll { $0 === self }
        }
    }
}

// MARK: - Toggle row
//
// Single tappable checkbox row inside `ToggleAlertPresentation`.
// Tap anywhere flips the state; the indicator icon is the
// always-mutating checkmark.square.fill / square pair.

@MainActor
private final class ToggleRow: UIView {

    private let option: Alert.ToggleOption
    private let onChange: (Bool) -> Void
    private let indicator = AlertIndicatorBox()
    private let label = UILabel()
    private(set) var isOn: Bool

    init(option: Alert.ToggleOption, onChange: @escaping (Bool) -> Void) {
        self.option = option
        self.onChange = onChange
        self.isOn = option.initial
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        // Use the same rounded-square indicator SumiPicker uses
        // for checkboxes — same visual language across the
        // design system.
        indicator.setState(isOn ? .on : .off, animated: false)
        addSubview(indicator)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = option.label
        label.font = Sumi.Font.body().sumiSized(14)
        label.textColor = Sumi.Color.textPrimary
        label.numberOfLines = 0
        addSubview(label)

        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: leadingAnchor),
            indicator.centerYAnchor.constraint(equalTo: centerYAnchor),

            label.leadingAnchor.constraint(equalTo: indicator.trailingAnchor, constant: Sumi.Spacing.m),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: Sumi.Spacing.s),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Sumi.Spacing.s)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc private func tapped() {
        isOn.toggle()
        indicator.setState(isOn ? .on : .off, animated: true)
        UISelectionFeedbackGenerator().selectionChanged()
        onChange(isOn)
    }
}

// MARK: - Progress alert presentation
//
// iOS-native sibling of `SumiProgressDialog` from the
// `SumiDialog` module.
//
// Same API surface (init / present / update / dismiss / Mode),
// different chrome:
//
//                  SumiProgressDialog       SumiProgressAlert
//   Corners        24pt                     16pt (matches Alert)
//   Width          280pt                    280pt
//   Cancel button  Centred text button      Full-width with hairline
//                                           divider above (UIAlertController)
//   Padding        Generous (24pt)          Tight (16-20pt)
//   Aesthetic      Material card            iOS Alert
//
// Use case dispatch:
//
//   • Pair with `SumiAlert.*` decisions → use `SumiProgressAlert`
//     for visual continuity ("Migrate library" alert chain).
//   • Pair with `SumiDialog.*` flows → use `SumiProgressDialog`.
//
// Both share the modal-signal contract: tap-outside is a no-op,
// caller owns the lifecycle, ring percentage on determinate mode.
//
// Note: the consumer of this class owns its lifecycle — unlike
// the `*AlertPresentation` family above which is driven by
// `Alert.present(...)` and disposed automatically.

@MainActor
public final class SumiProgressAlert {

    public enum Mode: Sendable {
        case indeterminate
        case determinate
    }

    private static var live: [SumiProgressAlert] = []

    public var onCancel: (() -> Void)?

    private let title: String
    private var message: String?
    private let mode: Mode
    private let cancellable: Bool

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let ringContainer = UIView()
    private let ringTrackLayer = CAShapeLayer()
    private let ringFillLayer = CAShapeLayer()
    private let percentLabel = UILabel()
    private var currentProgress: Double = 0
    private weak var hostWindow: UIWindow?
    private var didDismiss = false

    public init(
        title: String,
        message: String? = nil,
        mode: Mode = .indeterminate,
        cancellable: Bool = false
    ) {
        self.title = title
        self.message = message
        self.mode = mode
        self.cancellable = cancellable
    }

    // MARK: Lifecycle

    public func present() {
        guard hostWindow == nil else { return }
        guard let window = Self.activeWindow() else { return }
        Self.live.append(self)
        self.hostWindow = window

        configure(in: window)

        if Sumi.Motion.isReduced {
            card.transform = .identity
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.alpha = 1
            }
        } else {
            card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.84,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                self.card.transform = .identity
                self.card.alpha = 1
            }
        }
        if mode == .indeterminate {
            spinner.startAnimating()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func updateProgress(_ value: Double, animated: Bool = true) {
        guard mode == .determinate else { return }
        let clamped = max(0, min(1, value))
        let from = currentProgress
        currentProgress = clamped
        percentLabel.text = "\(Int(round(clamped * 100)))%"

        if animated && !Sumi.Motion.isReduced {
            let anim = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue = from
            anim.toValue = clamped
            anim.duration = 0.3
            anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            ringFillLayer.strokeEnd = clamped
            ringFillLayer.add(anim, forKey: "progress")
        } else {
            ringFillLayer.strokeEnd = clamped
        }
    }

    public func update(message: String, animated: Bool = true) {
        self.message = message
        guard animated && !Sumi.Motion.isReduced else {
            messageLabel.text = message
            return
        }
        UIView.transition(
            with: messageLabel,
            duration: 0.18,
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) {
            self.messageLabel.text = message
        }
    }

    public func update(title: String, animated: Bool = true) {
        guard animated && !Sumi.Motion.isReduced else {
            titleLabel.text = title
            return
        }
        UIView.transition(
            with: titleLabel,
            duration: 0.18,
            options: [.transitionCrossDissolve, .allowUserInteraction]
        ) {
            self.titleLabel.text = title
        }
    }

    /// Fire-and-forget dismissal. Use this from synchronous
    /// contexts (gesture callbacks, timers) where wrapping a
    /// `Task { await dismiss() }` would be noise. Wraps the
    /// awaitable `dismiss()` in an internal `Task`.
    public func dismissImmediately() {
        Task { await dismiss() }
    }

    public func dismiss() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            guard !didDismiss else {
                continuation.resume()
                return
            }
            didDismiss = true
            if mode == .indeterminate { spinner.stopAnimating() }
            UIView.animate(
                withDuration: Sumi.Motion.fast,
                delay: 0,
                options: [.curveEaseIn, .allowUserInteraction]
            ) {
                self.dimmer.backgroundColor = .clear
                self.card.alpha = 0
                if !Sumi.Motion.isReduced {
                    self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
                }
            } completion: { _ in
                self.card.removeFromSuperview()
                self.dimmer.removeFromSuperview()
                Self.live.removeAll { $0 === self }
                continuation.resume()
            }
        }
    }

    // MARK: Internals

    private func configure(in window: UIWindow) {
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        // Tap-outside is intentionally a no-op — progress is
        // a signal, not a dismissible alert.
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20),
            card.widthAnchor.constraint(equalToConstant: 280)
        ])
    }

    private func configureCard() {
        // Two-layer card (outer = shadow, inner = clip) — same
        // pattern as the rest of the design system.
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = Sumi.Radius.card  // 16pt — iOS Alert
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        // Progress affordance — spinner or ring.
        let progressView: UIView
        switch mode {
        case .indeterminate:
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.color = Sumi.Color.accent
            cardClip.addSubview(spinner)
            progressView = spinner
        case .determinate:
            ringContainer.translatesAutoresizingMaskIntoConstraints = false
            cardClip.addSubview(ringContainer)
            configureRing()
            progressView = ringContainer
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = Sumi.Font.bodyEmphasised().sumiSized(17)
        titleLabel.textColor = Sumi.Color.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        cardClip.addSubview(titleLabel)

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = message
        messageLabel.font = Sumi.Font.body().sumiSized(14)
        messageLabel.textColor = Sumi.Color.textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = (message == nil)
        cardClip.addSubview(messageLabel)

        // Tighter iOS Alert padding (20pt top, 16pt around text)
        // vs Dialog's 28/24.
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: 20),
            progressView.centerXAnchor.constraint(equalTo: cardClip.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -16),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            messageLabel.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 16),
            messageLabel.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -16)
        ])

        if cancellable {
            // iOS Alert cancel button — full-width, separated
            // from content by a 1px hairline divider above.
            // Matches `UIAlertController`'s native chrome AND
            // the press-overlay highlight used by all other
            // SumiAlert action buttons (`AlertButton`).
            let divider = UIView()
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.backgroundColor = Sumi.Color.separator
            cardClip.addSubview(divider)

            let cancelRow = ProgressAlertCancelRow()
            cancelRow.onTap = { [weak self] in
                // Fire consumer callback (cleanup) then auto-dismiss.
                self?.onCancel?()
                self?.dismissImmediately()
            }
            cardClip.addSubview(cancelRow)

            NSLayoutConstraint.activate([
                divider.topAnchor.constraint(equalTo: messageLabel.isHidden ? titleLabel.bottomAnchor : messageLabel.bottomAnchor, constant: 16),
                divider.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor),
                divider.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor),
                divider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),

                cancelRow.topAnchor.constraint(equalTo: divider.bottomAnchor),
                cancelRow.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor),
                cancelRow.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor),
                cancelRow.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor),
                cancelRow.heightAnchor.constraint(equalToConstant: 50)
            ])
        } else {
            // No cancel button — pin bottom directly to message
            // (or title) with iOS-tight padding.
            let bottomAnchorTarget = messageLabel.isHidden ? titleLabel.bottomAnchor : messageLabel.bottomAnchor
            bottomAnchorTarget.constraint(
                equalTo: cardClip.bottomAnchor, constant: -20
            ).isActive = true
        }
    }

    /// Same ring path / track / fill setup as
    /// `SumiProgressDialog` — see that class for the rationale.
    /// Slightly smaller diameter (56pt vs 64pt) to fit the
    /// tighter iOS Alert padding.
    private func configureRing() {
        let ringSize: CGFloat = 56
        let lineWidth: CGFloat = 5.5
        let radius = (ringSize - lineWidth) / 2
        let centre = CGPoint(x: ringSize / 2, y: ringSize / 2)

        let path = UIBezierPath(
            arcCenter: centre,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + .pi * 2,
            clockwise: true
        ).cgPath

        ringTrackLayer.path = path
        ringTrackLayer.strokeColor = Sumi.Color.accent.withAlphaComponent(0.18).cgColor
        ringTrackLayer.fillColor = UIColor.clear.cgColor
        ringTrackLayer.lineWidth = lineWidth
        ringTrackLayer.lineCap = .round
        ringContainer.layer.addSublayer(ringTrackLayer)

        ringFillLayer.path = path
        ringFillLayer.strokeColor = Sumi.Color.accent.cgColor
        ringFillLayer.fillColor = UIColor.clear.cgColor
        ringFillLayer.lineWidth = lineWidth
        ringFillLayer.lineCap = .round
        ringFillLayer.strokeEnd = 0
        ringContainer.layer.addSublayer(ringFillLayer)

        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.text = "0%"
        percentLabel.font = Sumi.Font.bodyEmphasised().sumiSized(14)
        percentLabel.textColor = Sumi.Color.textPrimary
        percentLabel.textAlignment = .center
        ringContainer.addSubview(percentLabel)

        NSLayoutConstraint.activate([
            ringContainer.widthAnchor.constraint(equalToConstant: ringSize),
            ringContainer.heightAnchor.constraint(equalToConstant: ringSize),
            percentLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor)
        ])

        ringTrackLayer.frame = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)
        ringFillLayer.frame = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)
    }

    private func applyShadowPath() {
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath
    }

    @MainActor
    private static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
    }
}

// MARK: - Progress alert cancel row
//
// Single-button row reused by `SumiProgressAlert`. Wraps an
// `AlertButton` (visual: text colour, font, dimming behaviour
// match the rest of the alert family) and adds finger-drag
// highlight tracking — touchesBegan tints the row with
// `Sumi.Color.pressOverlay`, dragging out clears it, dragging
// back in restores it. Same UX as `UIAlertController` and as
// every other tappable surface in the design system.
//
// Why not just attach a tap gesture? UITapGestureRecognizer
// has no "press in progress" state — it only fires on a
// completed tap, so the user gets no visual feedback during
// the press. The press overlay is what makes the button feel
// responsive.

@MainActor
private final class ProgressAlertCancelRow: UIView {

    var onTap: (() -> Void)?
    private let button: AlertButton

    init() {
        self.button = AlertButton(
            action: Alert.Action(title: "Cancel", style: .cancel),
            emphasised: true  // Cancel row should read with weight
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        button.translatesAutoresizingMaskIntoConstraints = false
        // Disable button's own user interaction — we own touch
        // tracking on this wrapper so the highlight matches the
        // row's bounds (full-width), not the AlertButton's intrinsic.
        button.isUserInteractionEnabled = false
        addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        button.setHighlighted(true, animated: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let touch = touches.first else { return }
        let inside = bounds.contains(touch.location(in: self))
        button.setHighlighted(inside, animated: false)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let inside = touches.first.map { bounds.contains($0.location(in: self)) } ?? false
        button.setHighlighted(false, animated: true)
        if inside { onTap?() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        button.setHighlighted(false, animated: true)
    }
}
