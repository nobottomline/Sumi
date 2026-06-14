import UIKit
import Sumi

// DialogPresentations — Material-3-styled presentation classes.
//
// Differences from SumiAlert presentations:
//   • Card corner radius 24pt (vs Alert's 16pt) — softer feel.
//   • 24pt padding all sides (vs Alert's tight padding).
//   • Buttons row at bottom-right (vs Alert's full-width row).
//   • Tap-outside-dimmer DISMISSES (vs Alert: no-op).
//   • Text variant uses DialogTextFieldView (vs Alert's inset
//     surface-subtle field).
//
// Class registry:
//   • DialogPresentation     — SumiDialog.present(...)
//   • TextDialogPresentation — SumiDialog.presentText(...)
//   • FormDialogPresentation — SumiDialog.presentForm(...)
//   • SumiProgressDialog     — owned by caller (own lifecycle)

// MARK: - Basic dialog presentation

@MainActor
final class DialogPresentation {

    private static var live: [DialogPresentation] = []

    private let title: String?
    private let message: Sumi.RichText?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let image: UIImage?
    private let customContent: UIView?
    private let linkHandler: ((URL) -> Void)?
    private let actions: [SumiDialog.Action]
    private let completion: (SumiDialog.Action?) -> Void

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private var didComplete = false

    init(
        title: String?,
        message: Sumi.RichText?,
        icon: UIImage?,
        iconTint: UIColor?,
        image: UIImage?,
        customContent: UIView?,
        linkHandler: ((URL) -> Void)?,
        actions: [SumiDialog.Action],
        completion: @escaping (SumiDialog.Action?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.image = image
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
        // Tap-outside-dimmer dismisses — the key Material 3
        // behaviour that distinguishes a dialog from an alert.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmerTapped))
        dimmer.addGestureRecognizer(tap)

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20),
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 312)
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
            card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.86,
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

    @objc private func dimmerTapped() {
        complete(with: nil)
    }

    private func applyShadowPath() {
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: 24
        ).cgPath
    }

    private func configureCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = 24
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        // Optional image preview at top of card (e.g. "Replace
        // cover?" with the new cover shown above the prompt).
        var topAnchorForHeader = cardClip.topAnchor
        var topInsetForHeader: CGFloat = 24
        if let image = image {
            let imageView = makeDialogImageView(image: image)
            cardClip.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: 24),
                imageView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
                imageView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
            ])
            topAnchorForHeader = imageView.bottomAnchor
            topInsetForHeader = 16
        }

        let header = UIStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .vertical
        header.spacing = 16
        header.alignment = .fill

        // Material 3 icon-on-top variant: a small SF Symbol
        // centred above the title turns the dialog into a
        // "hero" prompt. When present, title + message switch
        // to centred alignment to match the icon's centre axis.
        let headerAlignment: NSTextAlignment = (icon != nil) ? .center : .left
        if let icon = icon {
            let iconBanner = makeDialogIconBanner(icon: icon, tint: iconTint)
            header.addArrangedSubview(iconBanner)
            // Smaller gap between icon and title (default 16pt
            // would over-space them).
            header.setCustomSpacing(8, after: iconBanner)
        }

        if let title = title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = Sumi.Font.title()  // Material headlineSmall ≈ 24pt
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = headerAlignment
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        if let message = message, !message.isEmpty {
            // LinkAwareLabel: handles tap-on-link for markdown
            // `[text](url)` segments. Plain `.plain(...)` messages
            // skip the tap-tracking fast path internally.
            let l = LinkAwareLabel()
            l.attributedText = Sumi.render(
                message,
                context: Sumi.RichTextContext(
                    baseFont: Sumi.Font.body().sumiSized(14),
                    textColor: Sumi.Color.textSecondary,
                    accent: Sumi.Color.accent,
                    codeBackgroundColor: Sumi.Color.surfaceSubtle,
                    alignment: headerAlignment
                )
            )
            l.textAlignment = headerAlignment
            l.numberOfLines = 0
            l.onLinkTap = { [weak self] url in
                self?.linkHandler?(url)
            }
            header.addArrangedSubview(l)
        }

        // Custom content slot — caller-provided UIView between
        // message and the actions row. Used for tables (SumiTable),
        // previews, inline graphs. Sits inside the same header
        // stack so the title/message/customContent flow vertically
        // with consistent spacing.
        if let customContent {
            customContent.translatesAutoresizingMaskIntoConstraints = false
            header.addArrangedSubview(customContent)
        }

        cardClip.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchorForHeader, constant: topInsetForHeader),
            header.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
        ])

        // No actions provided → the card has no buttons row. Used
        // by self-committing dialogs (e.g. a stepper that saves
        // on dismiss; the custom content is the entire
        // interaction surface). In that case anchor the header
        // directly to the cardClip's bottom and skip the row
        // entirely — otherwise we'd render an 80pt empty band
        // (24 top gap + 40 row height + 16 bottom inset) below
        // the customContent.
        if actions.isEmpty {
            NSLayoutConstraint.activate([
                header.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor, constant: -24)
            ])
            return
        }
        let buttonsRow = DialogButtonsRow(actions: actions) { [weak self] action in
            self?.complete(with: action)
        }
        cardClip.addSubview(buttonsRow)
        NSLayoutConstraint.activate([
            buttonsRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            buttonsRow.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            buttonsRow.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24),
            buttonsRow.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor, constant: -16)
        ])
    }

    private func complete(with action: SumiDialog.Action?) {
        guard !didComplete else { return }
        didComplete = true
        let result: SumiDialog.Action? = (action?.style == .cancel) ? nil : action
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(result)
            Self.live.removeAll { $0 === self }
        }
    }
}

// MARK: - Text dialog presentation
//
// Same chrome as DialogPresentation + an `DialogTextFieldView`
// between header and buttons. Auto-focuses the field on appear
// and shifts the card up if the keyboard would cover it.

@MainActor
final class TextDialogPresentation {

    private static var live: [TextDialogPresentation] = []

    private let title: String?
    private let message: String?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let image: UIImage?
    private let textFieldConfig: SumiDialog.TextFieldConfig
    private let confirmDiscardIfEdited: Bool
    private let actions: [SumiDialog.Action]
    private let completion: (SumiDialog.TextPick?) -> Void

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private var dialogField: DialogTextFieldView!
    private var buttonsRow: DialogButtonsRow!
    private let errorLabel = UILabel()
    private var asyncTask: Task<Void, Never>?
    private var cardCenterY: NSLayoutConstraint?
    private var didComplete = false
    private weak var hostWindow: UIWindow?

    init(
        title: String?,
        message: String?,
        icon: UIImage?,
        iconTint: UIColor?,
        image: UIImage?,
        textField: SumiDialog.TextFieldConfig,
        confirmDiscardIfEdited: Bool,
        actions: [SumiDialog.Action],
        completion: @escaping (SumiDialog.TextPick?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.image = image
        self.textFieldConfig = textField
        self.confirmDiscardIfEdited = confirmDiscardIfEdited
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmerTapped))
        dimmer.addGestureRecognizer(tap)

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        let centerY = card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20)
        self.cardCenterY = centerY
        NSLayoutConstraint.activate([
            centerY,
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 312)
        ])

        if Sumi.Motion.isReduced {
            card.transform = .identity
        } else {
            card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
        card.alpha = 0
        window.layoutIfNeeded()
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: 24
        ).cgPath

        // Pre-apply focus visual to the field BEFORE the spring
        // starts — visuals land with the dialog's appearance.
        dialogField.applyInitialFocusVisual()

        // CRITICAL ORDERING: keyboard observers must be attached
        // BEFORE `becomeFirstResponder`. On iPad (and in tight
        // timing windows on iPhone) `becomeFirstResponder`
        // synchronously fires `keyboardWillShowNotification`; if
        // our handler isn't yet subscribed the notification is
        // lost and the dialog stays centered behind the
        // keyboard. The user has to dismiss the keyboard and
        // tap the field again to "kick" the lift.
        registerKeyboardObservers()
        dialogField.textField.becomeFirstResponder()

        let animate: () -> Void = {
            self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
            self.card.transform = .identity
            self.card.alpha = 1
        }
        let onDone: (Bool) -> Void = { _ in
            // Reserved for future post-present work.
        }
        if Sumi.Motion.isReduced {
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: animate,
                completion: onDone
            )
        } else {
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction],
                animations: animate,
                completion: onDone
            )
        }

        // Initial primary enabled state for `isRequired` fields.
        refreshPrimaryEnabled()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func dimmerTapped() {
        // Block dismiss while an async action is running —
        // the user is mid-validate, dismissing now would leave
        // the work uncancelled and the call site hanging.
        if buttonsRow.isLoading { return }
        // If user hasn't typed anything (or didn't ask for the
        // confirm flag), dismiss straight away. Otherwise show
        // a small "Discard?" confirm — losing typed text on an
        // accidental tap-outside is painful.
        let typedText = dialogField.textField.text ?? ""
        let original = textFieldConfig.initialValue ?? ""
        let hasEdited = typedText != original
        if confirmDiscardIfEdited && hasEdited {
            presentDiscardConfirm()
        } else {
            animateOut(picked: nil)
        }
    }

    private func presentDiscardConfirm() {
        Task { [weak self] in
            let pick = await SumiDialog.present(
                title: "Discard changes?",
                message: "Anything you've typed will be lost.",
                actions: [
                    .init(title: "Keep editing", style: .cancel),
                    .init(title: "Discard", style: .destructive)
                ]
            )
            guard let self else { return }
            if pick?.style == .destructive {
                self.animateOut(picked: nil)
            }
            // else: keep the original dialog open
        }
    }

    private func configureCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = 24
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        var topAnchorForHeader = cardClip.topAnchor
        var topInsetForHeader: CGFloat = 24
        if let image = image {
            let imageView = makeDialogImageView(image: image)
            cardClip.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: 24),
                imageView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
                imageView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
            ])
            topAnchorForHeader = imageView.bottomAnchor
            topInsetForHeader = 16
        }

        let header = UIStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .vertical
        header.spacing = 16
        header.alignment = .fill

        // Material 3 icon-on-top — see `DialogPresentation`
        // for full reasoning. Icon centred above title flips
        // title + message alignment to centred too.
        let headerAlignment: NSTextAlignment = (icon != nil) ? .center : .left
        if let icon = icon {
            let iconBanner = makeDialogIconBanner(icon: icon, tint: iconTint)
            header.addArrangedSubview(iconBanner)
            header.setCustomSpacing(8, after: iconBanner)
        }

        if let title = title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = Sumi.Font.title()
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = headerAlignment
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        if let message = message, !message.isEmpty {
            let l = UILabel()
            l.text = message
            l.font = Sumi.Font.body().sumiSized(14)
            l.textColor = Sumi.Color.textSecondary
            l.textAlignment = headerAlignment
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        cardClip.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchorForHeader, constant: topInsetForHeader),
            header.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
        ])

        dialogField = makeDialogTextField(config: textFieldConfig)
        dialogField.onTextChanged = { [weak self] _ in self?.refreshPrimaryEnabled() }
        dialogField.onReturn = { [weak self] in self?.firePrimary() }
        cardClip.addSubview(dialogField)
        NSLayoutConstraint.activate([
            dialogField.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            dialogField.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            dialogField.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
        ])

        // Inline error label for async-action failures. Hidden
        // by default; revealed by `showError` when an
        // asyncHandler throws. Sits between the field and the
        // buttons row so it reads as "this is what went wrong
        // with what you typed".
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = Sumi.Font.caption().sumiSized(12)
        errorLabel.textColor = Sumi.Color.danger
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        cardClip.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.topAnchor.constraint(equalTo: dialogField.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
        ])

        buttonsRow = DialogButtonsRow(actions: actions) { [weak self] action in
            self?.handlePick(action)
        }
        cardClip.addSubview(buttonsRow)
        NSLayoutConstraint.activate([
            buttonsRow.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
            buttonsRow.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            buttonsRow.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24),
            buttonsRow.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor, constant: -16)
        ])
    }

    /// Routes a picked action through either the sync (existing
    /// `completeWithAction`) or async path. Async path runs the
    /// handler with the button spinning; on success → dismiss,
    /// on throw → inline error + restore. The current text-field
    /// value is captured each retry so re-tries see the latest
    /// edits (the user fixes a bad URL → taps Add → handler
    /// sees the corrected text, not the originally-bad one).
    private func handlePick(_ action: SumiDialog.Action) {
        guard let handler = action.asyncHandler else {
            completeWithAction(action)
            return
        }
        // Clear any error from a prior failed attempt before
        // showing the spinner for a new try.
        hideErrorIfVisible()
        buttonsRow.startLoading(for: action)
        let currentText = dialogField.textField.text ?? ""
        asyncTask = Task { [weak self] in
            do {
                try await handler(currentText)
                guard let self else { return }
                self.completeWithAction(action)
            } catch {
                guard let self else { return }
                self.showError(error)
                self.buttonsRow.stopLoading()
            }
            self?.asyncTask = nil
        }
    }

    private func showError(_ error: Error) {
        let text = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        errorLabel.text = text
        let block = {
            self.errorLabel.isHidden = false
            self.card.superview?.layoutIfNeeded()
        }
        if Sumi.Motion.isReduced {
            block()
            card.layer.shadowPath = UIBezierPath(
                roundedRect: card.bounds, cornerRadius: 24
            ).cgPath
        } else {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.95,
                initialSpringVelocity: 0.3,
                options: [.allowUserInteraction],
                animations: block
            ) { _ in
                // Card height grew — refit shadow to new outline.
                self.card.layer.shadowPath = UIBezierPath(
                    roundedRect: self.card.bounds, cornerRadius: 24
                ).cgPath
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func hideErrorIfVisible() {
        guard !errorLabel.isHidden else { return }
        errorLabel.isHidden = true
        errorLabel.text = nil
    }

    private func refreshPrimaryEnabled() {
        if textFieldConfig.isRequired {
            buttonsRow.setPrimaryEnabled(!dialogField.isEmpty)
        }
    }

    private func firePrimary() {
        let nonCancel = actions.filter { $0.style != .cancel }
        guard let primary = nonCancel.last else {
            dialogField.textField.resignFirstResponder()
            return
        }
        if textFieldConfig.isRequired && dialogField.isEmpty {
            // Required and empty — flash the field's border to
            // signal "fill me in" instead of closing.
            dialogField.textField.becomeFirstResponder()
            return
        }
        // Route through handlePick so async handler (if any)
        // fires correctly instead of dismissing immediately.
        handlePick(primary)
    }

    private func completeWithAction(_ action: SumiDialog.Action) {
        let pick: SumiDialog.TextPick? = (action.style == .cancel)
            ? nil
            : SumiDialog.TextPick(action: action, text: dialogField.textField.text ?? "")
        animateOut(picked: pick)
    }

    /// Single dismissal path — used by action picks AND dimmer
    /// taps. The `didComplete` flag at the top makes a second
    /// call (e.g. user taps Cancel mid-dismiss-from-tap-outside)
    /// a no-op.
    private func animateOut(picked: SumiDialog.TextPick?) {
        guard !didComplete else { return }
        didComplete = true
        dialogField.textField.resignFirstResponder()
        NotificationCenter.default.removeObserver(self)
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(picked)
            Self.live.removeAll { $0 === self }
        }
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
        let keyboardFrameInWindow = window.convert(frameValue.cgRectValue, from: nil)
        let keyboardTop = keyboardFrameInWindow.minY
        let safeTop = window.safeAreaInsets.top
        let visibleCentreY = (safeTop + keyboardTop) / 2
        let target = visibleCentreY - window.bounds.height / 2

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
}

// MARK: - Form dialog presentation
//
// Generalised text variant with N outlined floating-label
// fields stacked vertically. Return key on a non-last field
// focuses the next field; return on the last fires the
// primary action. Primary is gated by `isRequired`: any
// required field empty → primary disabled.
//
// Same image + confirmDiscardIfEdited support as
// TextDialogPresentation.

@MainActor
final class FormDialogPresentation {

    private static var live: [FormDialogPresentation] = []

    private let title: String?
    private let message: String?
    private let icon: UIImage?
    private let iconTint: UIColor?
    private let image: UIImage?
    private let textFieldConfigs: [SumiDialog.TextFieldConfig]
    private let confirmDiscardIfEdited: Bool
    private let actions: [SumiDialog.Action]
    private let completion: (SumiDialog.FormPick?) -> Void

    private let dimmer = UIView()
    private let card = UIView()
    private let cardClip = UIView()
    private var fields: [DialogTextFieldView] = []
    private var buttonsRow: DialogButtonsRow!
    private let errorLabel = UILabel()
    private var asyncTask: Task<Void, Never>?
    private var cardCenterY: NSLayoutConstraint?
    private var didComplete = false
    private weak var hostWindow: UIWindow?

    init(
        title: String?,
        message: String?,
        icon: UIImage?,
        iconTint: UIColor?,
        image: UIImage?,
        textFields: [SumiDialog.TextFieldConfig],
        confirmDiscardIfEdited: Bool,
        actions: [SumiDialog.Action],
        completion: @escaping (SumiDialog.FormPick?) -> Void
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.iconTint = iconTint
        self.image = image
        self.textFieldConfigs = textFields
        self.confirmDiscardIfEdited = confirmDiscardIfEdited
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmerTapped))
        dimmer.addGestureRecognizer(tap)

        configureCard()
        window.addSubview(card)
        card.sumi_enableDynamicType()
        let centerY = card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -20)
        self.cardCenterY = centerY
        NSLayoutConstraint.activate([
            centerY,
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 312)
        ])

        if Sumi.Motion.isReduced {
            card.transform = .identity
        } else {
            card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
        card.alpha = 0
        window.layoutIfNeeded()
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: 24
        ).cgPath

        // First field gets focus on appear — pre-apply its
        // focus visual so the highlight lands with the dialog.
        fields.first?.applyInitialFocusVisual()
        // Register keyboard observers BEFORE first responder.
        // On iPad `becomeFirstResponder` synchronously fires
        // the show notification; if our handler isn't yet
        // subscribed we miss it and the dialog stays centered
        // under the keyboard. See `TextDialogPresentation.attach()`.
        registerKeyboardObservers()
        fields.first?.textField.becomeFirstResponder()

        let animate: () -> Void = {
            self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
            self.card.transform = .identity
            self.card.alpha = 1
        }
        let onDone: (Bool) -> Void = { _ in
            // Reserved for future post-present work.
        }
        if Sumi.Motion.isReduced {
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: animate,
                completion: onDone
            )
        } else {
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.86,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction],
                animations: animate,
                completion: onDone
            )
        }

        refreshPrimaryEnabled()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func dimmerTapped() {
        // Block dismiss while an async action is running.
        if buttonsRow.isLoading { return }
        // Confirm-on-discard logic: if any required field has
        // been edited, surface a quick confirm before letting
        // the user dismiss.
        if confirmDiscardIfEdited && hasUserEdited() {
            presentDiscardConfirm()
        } else {
            animateOut(picked: nil)
        }
    }

    private func presentDiscardConfirm() {
        Task { [weak self] in
            let pick = await SumiDialog.present(
                title: "Discard changes?",
                message: "Anything you've typed will be lost.",
                actions: [
                    .init(title: "Keep editing", style: .cancel),
                    .init(title: "Discard", style: .destructive)
                ]
            )
            guard let self else { return }
            if pick?.style == .destructive {
                self.animateOut(picked: nil)
            }
        }
    }

    private func hasUserEdited() -> Bool {
        for (idx, field) in fields.enumerated() {
            let original = textFieldConfigs[idx].initialValue ?? ""
            let current = field.textField.text ?? ""
            if current != original { return true }
        }
        return false
    }

    private func configureCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = 24
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        var topAnchorForHeader = cardClip.topAnchor
        var topInsetForHeader: CGFloat = 24
        if let image = image {
            let imageView = makeDialogImageView(image: image)
            cardClip.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: 24),
                imageView.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
                imageView.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
            ])
            topAnchorForHeader = imageView.bottomAnchor
            topInsetForHeader = 16
        }

        let header = UIStackView()
        header.translatesAutoresizingMaskIntoConstraints = false
        header.axis = .vertical
        header.spacing = 16
        header.alignment = .fill

        // Material 3 icon-on-top — see `DialogPresentation`
        // for full reasoning. Icon centred above title flips
        // title + message alignment to centred too.
        let headerAlignment: NSTextAlignment = (icon != nil) ? .center : .left
        if let icon = icon {
            let iconBanner = makeDialogIconBanner(icon: icon, tint: iconTint)
            header.addArrangedSubview(iconBanner)
            header.setCustomSpacing(8, after: iconBanner)
        }

        if let title = title, !title.isEmpty {
            let l = UILabel()
            l.text = title
            l.font = Sumi.Font.title()
            l.textColor = Sumi.Color.textPrimary
            l.textAlignment = headerAlignment
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        if let message = message, !message.isEmpty {
            let l = UILabel()
            l.text = message
            l.font = Sumi.Font.body().sumiSized(14)
            l.textColor = Sumi.Color.textSecondary
            l.textAlignment = headerAlignment
            l.numberOfLines = 0
            header.addArrangedSubview(l)
        }
        cardClip.addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchorForHeader, constant: topInsetForHeader),
            header.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
        ])

        // Build N outlined fields stacked with 8pt spacing.
        let fieldsStack = UIStackView()
        fieldsStack.translatesAutoresizingMaskIntoConstraints = false
        fieldsStack.axis = .vertical
        fieldsStack.spacing = 8
        fieldsStack.alignment = .fill

        var builtFields: [DialogTextFieldView] = []
        for (idx, config) in textFieldConfigs.enumerated() {
            let isLast = (idx == textFieldConfigs.count - 1)
            let field = makeDialogTextField(config: config)
            field.textField.returnKeyType = isLast ? .done : .next
            field.onTextChanged = { [weak self] _ in self?.refreshPrimaryEnabled() }
            field.onReturn = { [weak self] in
                guard let self else { return }
                if isLast {
                    self.firePrimary()
                } else {
                    self.fields[idx + 1].textField.becomeFirstResponder()
                }
            }
            builtFields.append(field)
            fieldsStack.addArrangedSubview(field)
        }
        self.fields = builtFields

        cardClip.addSubview(fieldsStack)
        NSLayoutConstraint.activate([
            fieldsStack.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 16),
            fieldsStack.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            fieldsStack.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
        ])

        // Inline error label — see `TextDialogPresentation` for
        // reasoning. Hidden by default; revealed by `showError`
        // when an async handler throws.
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.font = Sumi.Font.caption().sumiSized(12)
        errorLabel.textColor = Sumi.Color.danger
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true
        cardClip.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            errorLabel.topAnchor.constraint(equalTo: fieldsStack.bottomAnchor, constant: 8),
            errorLabel.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
        ])

        buttonsRow = DialogButtonsRow(actions: actions) { [weak self] action in
            self?.handlePick(action)
        }
        cardClip.addSubview(buttonsRow)
        NSLayoutConstraint.activate([
            buttonsRow.topAnchor.constraint(equalTo: errorLabel.bottomAnchor, constant: 16),
            buttonsRow.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            buttonsRow.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24),
            buttonsRow.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor, constant: -16)
        ])
    }

    /// Async-aware pick routing — same pattern as
    /// `TextDialogPresentation.handlePick`, but prefers
    /// `asyncFormHandler` when set (since form dialogs carry
    /// N values, not one). Falls back to the single-text
    /// handler with an empty string if a plain `asyncHandler`
    /// was used (caller didn't care about field contents).
    private func handlePick(_ action: SumiDialog.Action) {
        let plain = action.asyncHandler
        let form = action.asyncFormHandler
        guard plain != nil || form != nil else {
            completeWithAction(action)
            return
        }
        hideErrorIfVisible()
        buttonsRow.startLoading(for: action)
        let currentValues = fields.map { $0.textField.text ?? "" }
        asyncTask = Task { [weak self] in
            do {
                if let form {
                    try await form(currentValues)
                } else if let plain {
                    try await plain(currentValues.first ?? "")
                }
                guard let self else { return }
                self.completeWithAction(action)
            } catch {
                guard let self else { return }
                self.showError(error)
                self.buttonsRow.stopLoading()
            }
            self?.asyncTask = nil
        }
    }

    private func showError(_ error: Error) {
        let text = (error as? LocalizedError)?.errorDescription
            ?? error.localizedDescription
        errorLabel.text = text
        let block = {
            self.errorLabel.isHidden = false
            self.card.superview?.layoutIfNeeded()
        }
        if Sumi.Motion.isReduced {
            block()
            card.layer.shadowPath = UIBezierPath(
                roundedRect: card.bounds, cornerRadius: 24
            ).cgPath
        } else {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.95,
                initialSpringVelocity: 0.3,
                options: [.allowUserInteraction],
                animations: block
            ) { _ in
                self.card.layer.shadowPath = UIBezierPath(
                    roundedRect: self.card.bounds, cornerRadius: 24
                ).cgPath
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    private func hideErrorIfVisible() {
        guard !errorLabel.isHidden else { return }
        errorLabel.isHidden = true
        errorLabel.text = nil
    }

    private func refreshPrimaryEnabled() {
        // Primary gated by required-fields-non-empty. Any field
        // marked required must be non-empty before primary
        // becomes tappable.
        let anyRequiredEmpty = zip(textFieldConfigs, fields).contains { config, field in
            config.isRequired && field.isEmpty
        }
        buttonsRow.setPrimaryEnabled(!anyRequiredEmpty)
    }

    private func firePrimary() {
        let nonCancel = actions.filter { $0.style != .cancel }
        guard let primary = nonCancel.last else {
            fields.forEach { $0.textField.resignFirstResponder() }
            return
        }
        // Required + any empty → focus the FIRST empty required
        // field instead of dismissing.
        for (idx, config) in textFieldConfigs.enumerated() {
            if config.isRequired && fields[idx].isEmpty {
                fields[idx].textField.becomeFirstResponder()
                return
            }
        }
        // Route through handlePick so async handler fires.
        handlePick(primary)
    }

    private func completeWithAction(_ action: SumiDialog.Action) {
        let pick: SumiDialog.FormPick? = (action.style == .cancel)
            ? nil
            : SumiDialog.FormPick(action: action, values: fields.map { $0.textField.text ?? "" })
        animateOut(picked: pick)
    }

    private func animateOut(picked: SumiDialog.FormPick?) {
        guard !didComplete else { return }
        didComplete = true
        fields.forEach { $0.textField.resignFirstResponder() }
        NotificationCenter.default.removeObserver(self)
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.alpha = 0
            if !Sumi.Motion.isReduced {
                self.card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(picked)
            Self.live.removeAll { $0 === self }
        }
    }

    // MARK: Keyboard (mirrors TextDialogPresentation)

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
}

// MARK: - Progress dialog presentation
//
// Different shape from the variants above: the consumer OWNS the
// lifecycle. `init()` configures it, `present()` attaches to the
// key window, `update(message:)` reflects progress, `dismiss()`
// animates out. No async return, no user action choices — this
// is a SIGNAL (something's happening), not a decision moment.
//
// Use cases:
//
//   • Library migrate to new source (5-30 s)
//   • Batch chapter download
//   • Sync / backup / restore
//   • Heavy import / extraction
//
// API:
//
//   ```swift
//   let progress = SumiProgressDialog(
//       title: "Migrating library...",
//       message: "0 of 142 manga processed",
//       cancellable: true
//   )
//   progress.onCancel = { migrationTask.cancel() }
//   progress.present()
//
//   for i in 0..<count {
//       try await Task.checkCancellation()
//       progress.update(message: "\(i) of \(count) manga processed")
//       try await migrateOne(i)
//   }
//
//   await progress.dismiss()
//   ```
//
// Lifecycle: NOT modal in the "blocks Swift" sense — caller
// keeps running on main actor between `present` and `dismiss`.
// User input on the rest of the app is blocked via full-screen
// dimmer (tap-outside is a no-op; this is a progress signal,
// not a dismissible dialog).

@MainActor
public final class SumiProgressDialog {

    /// Two visual modes:
    ///
    ///   • `.indeterminate` (default) — spinning circle.
    ///     Use when the work duration / step count is unknown
    ///     ("Connecting to server", "Loading manga details").
    ///
    ///   • `.determinate` — ring with percentage in centre.
    ///     Use when you can report progress as a fraction
    ///     ("Downloading 73 of 142 chapters", "Migrating 27%").
    ///     Drive via `updateProgress(_:)`.
    public enum Mode: Sendable {
        case indeterminate
        case determinate
    }

    private static var live: [SumiProgressDialog] = []

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
    private let cancelButton = DialogTextButton(
        action: .init(title: "Cancel", style: .cancel)
    )
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

    // MARK: Public lifecycle

    /// Attach to the key window and animate in. Idempotent —
    /// calling twice is a no-op.
    public func present() {
        guard hostWindow == nil else { return }
        guard let window = Self.activeWindow() else { return }
        Self.live.append(self)
        self.hostWindow = window

        configure(in: window)

        // Animation: fade dimmer, scale-up card with spring.
        // Same motion language as SumiDialog so the two
        // surfaces feel like siblings.
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
            card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            card.alpha = 0
            window.layoutIfNeeded()
            applyShadowPath()
            UIView.animate(
                withDuration: Sumi.Motion.standard,
                delay: 0,
                usingSpringWithDamping: 0.86,
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

    /// Update the determinate ring's progress. Pass values in
    /// 0.0...1.0. Animates from the previous progress to the
    /// new value over ~0.3 s (easeOut) so consecutive updates
    /// — e.g. "73%" then "74%" — feel continuous rather than
    /// jumpy. No-op when `mode == .indeterminate`.
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

    /// Update the message line while the dialog is visible.
    /// `animated` defaults true so the new text crossfades —
    /// less jarring than a snap during a multi-second operation.
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

    /// Update title while visible. Less common than message
    /// (title usually stays "Migrating..."), exposed for
    /// completeness.
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
    ///
    /// Use the async variant instead if you need to chain
    /// — e.g. dismiss the progress, then present a result alert.
    public func dismissImmediately() {
        Task { await dismiss() }
    }

    /// Animate out and clean up. Async so callers can `await`
    /// the dismissal before kicking off the next presentation
    /// (helpful in flows that chain progress → result alert).
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
                    self.card.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
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
        // Tap-outside is intentionally a NO-OP — progress
        // dialogs are signals, not dismissible. Caller is the
        // sole owner of "when does this go away".
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
        // Two-layer card: outer for shadow, inner for clip.
        // Matches `SumiDialog`'s pattern.
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .clear
        card.clipsToBounds = false
        card.layer.applySumiShadow(.modal)

        cardClip.translatesAutoresizingMaskIntoConstraints = false
        cardClip.backgroundColor = Sumi.Color.surfaceElevated
        cardClip.layer.cornerRadius = 24
        cardClip.layer.cornerCurve = .continuous
        cardClip.clipsToBounds = true
        card.addSubview(cardClip)
        NSLayoutConstraint.activate([
            cardClip.topAnchor.constraint(equalTo: card.topAnchor),
            cardClip.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            cardClip.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardClip.trailingAnchor.constraint(equalTo: card.trailingAnchor)
        ])

        // Progress affordance — either system UIActivityIndicator
        // (indeterminate) or a custom CAShapeLayer ring with
        // percentage label (determinate). Only one is added to
        // the view hierarchy based on `mode`.
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

        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: cardClip.topAnchor, constant: 28),
            progressView.centerXAnchor.constraint(equalTo: cardClip.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: cardClip.leadingAnchor, constant: 24),
            messageLabel.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -24)
        ])

        if cancellable {
            cancelButton.translatesAutoresizingMaskIntoConstraints = false
            cancelButton.onTap = { [weak self] in
                // Fire consumer callback FIRST so they can cancel
                // a Task / cleanup, then auto-dismiss immediately
                // so the user gets snappy visual feedback. Without
                // this auto-dismiss, the consumer would have to
                // notice the cancel flag from inside a sleep loop
                // before calling dismiss — that's a perceptible
                // lag for fast cancel taps.
                self?.onCancel?()
                self?.dismissImmediately()
            }
            cardClip.addSubview(cancelButton)
            // Right-aligned, matching the SumiDialog action-row
            // convention (cancel + primary sit bottom-right). The
            // 16pt inset matches SumiDialog's button row gutter.
            NSLayoutConstraint.activate([
                cancelButton.topAnchor.constraint(
                    equalTo: messageLabel.isHidden ? titleLabel.bottomAnchor : messageLabel.bottomAnchor,
                    constant: 12
                ),
                cancelButton.trailingAnchor.constraint(equalTo: cardClip.trailingAnchor, constant: -16),
                cancelButton.bottomAnchor.constraint(equalTo: cardClip.bottomAnchor, constant: -12)
            ])
        } else {
            // No cancel button — pin bottom directly to message
            // (or title if message hidden) with breathing room.
            let bottomAnchorTarget = messageLabel.isHidden ? titleLabel.bottomAnchor : messageLabel.bottomAnchor
            bottomAnchorTarget.constraint(
                equalTo: cardClip.bottomAnchor, constant: -28
            ).isActive = true
        }
    }

    /// Sets up the determinate ring: CAShapeLayer track (dim
    /// accent) + CAShapeLayer fill (full accent), with `strokeEnd`
    /// animated between progress values. Centre holds a
    /// percentage label.
    ///
    /// Note: the ring's circular path is built using the
    /// container's bounds — we layout the container at a fixed
    /// size (64×64pt) so the path is stable across rotations.
    private func configureRing() {
        let ringSize: CGFloat = 64
        let lineWidth: CGFloat = 6
        let radius = (ringSize - lineWidth) / 2
        let centre = CGPoint(x: ringSize / 2, y: ringSize / 2)

        // Path runs from top (-90°) clockwise — standard progress
        // ring orientation (12-o'clock start).
        let path = UIBezierPath(
            arcCenter: centre,
            radius: radius,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + .pi * 2,
            clockwise: true
        ).cgPath

        // Track — dim accent so the unfilled portion stays
        // visible against the cream card bg.
        ringTrackLayer.path = path
        ringTrackLayer.strokeColor = Sumi.Color.accent.withAlphaComponent(0.18).cgColor
        ringTrackLayer.fillColor = UIColor.clear.cgColor
        ringTrackLayer.lineWidth = lineWidth
        ringTrackLayer.lineCap = .round
        ringContainer.layer.addSublayer(ringTrackLayer)

        // Fill — animated portion of the ring. starts at 0,
        // grows toward 1 as `updateProgress` is called.
        ringFillLayer.path = path
        ringFillLayer.strokeColor = Sumi.Color.accent.cgColor
        ringFillLayer.fillColor = UIColor.clear.cgColor
        ringFillLayer.lineWidth = lineWidth
        ringFillLayer.lineCap = .round
        ringFillLayer.strokeEnd = 0
        ringContainer.layer.addSublayer(ringFillLayer)

        // Centre percentage label.
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        percentLabel.text = "0%"
        percentLabel.font = Sumi.Font.bodyEmphasised().sumiSized(15)
        percentLabel.textColor = Sumi.Color.textPrimary
        percentLabel.textAlignment = .center
        ringContainer.addSubview(percentLabel)

        NSLayoutConstraint.activate([
            ringContainer.widthAnchor.constraint(equalToConstant: ringSize),
            ringContainer.heightAnchor.constraint(equalToConstant: ringSize),
            percentLabel.centerXAnchor.constraint(equalTo: ringContainer.centerXAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: ringContainer.centerYAnchor)
        ])

        // Position sublayers — frames set once since ring's
        // container has a fixed size.
        ringTrackLayer.frame = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)
        ringFillLayer.frame = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)
    }

    private func applyShadowPath() {
        card.layer.shadowPath = UIBezierPath(
            roundedRect: card.bounds,
            cornerRadius: 24
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
