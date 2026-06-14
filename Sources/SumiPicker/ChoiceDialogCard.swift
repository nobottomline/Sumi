import UIKit
import Sumi

// ChoiceDialogCard — the visible modal card.
//
// Layout (top to bottom):
//   • Title row (title left, optional live counter right for
//     multi-select)
//   • Optional message
//   • Subtle divider
//   • Scrollable choice rows
//   • Footer (Done button bottom-right) — for multi / tri
//
// The card has a soft shadow and rounded corners; the
// internal contents are blur-less surface (no UIVisualEffect)
// for crispness — readability is critical for a dialog.

@MainActor
final class ChoiceDialogCard: UIView {

    var onSinglePicked: ((AnyHashable) -> Void)?
    var onMultiChanged: ((Set<AnyHashable>) -> Void)?
    var onTriChanged: (([AnyHashable: TriState]) -> Void)?
    var onDoneTapped: (() -> Void)?
    /// Fired when the user taps the trailing accessory row
    /// (or the empty-state CTA when `choices` is empty).
    var onAccessoryTapped: (() -> Void)?

    var initialSingleSelection: AnyHashable? {
        didSet { applyInitialState() }
    }
    var initialMultiSelection: Set<AnyHashable> = [] {
        didSet { applyInitialState() }
    }
    var initialTriStates: [AnyHashable: TriState] = [:] {
        didSet { applyInitialState() }
    }

    private let mode: DialogMode
    private let choices: [AnyChoice]
    private let accessory: ChoiceDialog.PickerAccessory?
    private var rows: [ChoiceRowView] = []
    private var emptyStateActive: Bool { choices.isEmpty && accessory != nil }

    private let counterLabel = UILabel()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let doneButton = UIButton(type: .system)
    /// Footer-placed accessory affordance (e.g. "+ New
    /// category"). Only realised + added to the view tree
    /// when the supplied accessory's placement == `.footer`
    /// AND the choice list is non-empty (empty-state branch
    /// promotes the accessory to its own centered CTA).
    private let footerAccessoryButton = UIButton(type: .system)
    private let selectionHaptic = UISelectionFeedbackGenerator()

    init(
        title: String,
        message: String?,
        mode: DialogMode,
        choices: [AnyChoice],
        accessory: ChoiceDialog.PickerAccessory? = nil
    ) {
        self.mode = mode
        self.choices = choices
        self.accessory = accessory
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Sumi.Color.surfaceElevated
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.applySumiShadow(.modal)

        // ---- Title row (just the title — counter now lives
        // inside the Done button label as "Done (N)" so the
        // title isn't truncated by a sibling element fighting
        // for horizontal space) ----
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold).sumiSized(17)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = Sumi.Color.textPrimary
        titleLabel.numberOfLines = 0
        addSubview(titleLabel)

        // counterLabel is now unused, kept hidden for backwards
        // compat in case any code references it. The live count
        // is reflected in `doneButton`'s title.
        counterLabel.isHidden = true

        // ---- Message ----
        let messageLabel: UILabel?
        if let message = message, !message.isEmpty {
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = message
            label.font = Sumi.Font.caption()
            label.textColor = Sumi.Color.textSecondary
            label.numberOfLines = 0
            addSubview(label)
            messageLabel = label
        } else {
            messageLabel = nil
        }

        // ---- Divider above scroll ----
        let topDivider = UIView()
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        topDivider.backgroundColor = Sumi.Color.separator
        addSubview(topDivider)

        // ---- Scroll content ----
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = false
        // `delaysContentTouches = true` (the default) is what
        // UITableView uses to disambiguate tap vs scroll on
        // tappable cells. Without it, the touch races to the
        // UIControl row immediately and the scrollView's pan
        // recogniser can't claim the gesture even on a clear
        // vertical drag — finger sticks on the row, no scroll.
        scrollView.delaysContentTouches = true
        // Explicit `canCancelContentTouches = true` (also the
        // default) — once scrollView's pan recogniser
        // recognises, it cancels the UIControl's touch and
        // takes over scrolling.
        scrollView.canCancelContentTouches = true
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .fill
        scrollView.addSubview(stack)

        for (index, choice) in choices.enumerated() {
            if index > 0 {
                let sep = UIView()
                sep.translatesAutoresizingMaskIntoConstraints = false
                sep.backgroundColor = Sumi.Color.separator
                sep.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
                stack.addArrangedSubview(sep)
            }
            let row = ChoiceRowView(
                choice: choice,
                indicatorStyle: indicatorStyleForMode()
            )
            row.onTap = { [weak self] in self?.handleTap(on: row) }
            rows.append(row)
            stack.addArrangedSubview(row)
        }

        if emptyStateActive, let accessory {
            // Empty-state branch — the accessory IS the empty
            // state regardless of its placement preference. A
            // hidden footer button on a blank canvas reads as
            // nothing useful, so for empty lists we ALWAYS
            // promote the accessory to the centered empty-state
            // CTA. The placement preference applies only when
            // there are choices to position relative to.
            let empty = makeEmptyStateView(accessory: accessory) { [weak self] in
                UISelectionFeedbackGenerator().selectionChanged()
                self?.onAccessoryTapped?()
            }
            stack.addArrangedSubview(empty)
        } else if let accessory, accessory.placement == .row {
            // `.row` placement (the default) — accessory rendered
            // as the last row in the list, separated by a SINGLE
            // hairline (same weight as the row separators above).
            // Visual distinction comes from the accent text colour
            // + leading plus-icon, not a thicker divider — matches
            // iOS Settings' "Add Account" pattern.
            let hairline = UIView()
            hairline.translatesAutoresizingMaskIntoConstraints = false
            hairline.backgroundColor = Sumi.Color.separator
            hairline.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
            stack.addArrangedSubview(hairline)

            let row = AccessoryRowView(accessory: accessory)
            row.onTap = { [weak self] in
                UISelectionFeedbackGenerator().selectionChanged()
                self?.onAccessoryTapped?()
            }
            stack.addArrangedSubview(row)
        }
        // `.footer` placement is wired further down — see the
        // footer-section block that adds `accessoryButton`
        // alongside the counter + Done button.

        // ---- Footer (counter + Done) ----
        // Counter lives in the footer (NOT the title row) so
        // it doesn't fight the title for horizontal space.
        // Counter + Done sit side-by-side: counter leading,
        // Done trailing. Both have stable, intrinsic widths
        // — rapid taps don't cause text truncation since the
        // counter label and button each lay out independently.
        counterLabel.translatesAutoresizingMaskIntoConstraints = false
        counterLabel.font = Sumi.Font.caption()
        counterLabel.textColor = Sumi.Color.textSecondary
        counterLabel.textAlignment = .left
        counterLabel.isHidden = !showsCounter
        addSubview(counterLabel)

        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle("Done", for: .normal)
        doneButton.titleLabel?.font = Sumi.Font.bodyEmphasised()
        doneButton.setTitleColor(Sumi.Color.accent, for: .normal)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneButton.isHidden = !needsDoneButton
        addSubview(doneButton)

        // ---- Footer accessory button (`.footer` placement only) ----
        // Same action surface as the `.row` accessory, just positioned
        // as a peer of Done on the leading side of the footer.
        // Visible only when the supplied accessory opted in via
        // `.placement = .footer` AND the choice list is non-empty
        // (empty-state branch promotes the accessory to a centered
        // CTA, already handled above).
        let usesFooterAccessory =
            !choices.isEmpty
            && (accessory?.placement == .footer)
            && accessory != nil
        if usesFooterAccessory, let accessory {
            footerAccessoryButton.translatesAutoresizingMaskIntoConstraints = false
            // Footer placement is INTENTIONALLY visually
            // subdued so it doesn't compete with the trailing
            // Done CTA for the user's eye. Two deliberate
            // departures from the row-placed accessory:
            //
            //   • No SF Symbol icon. Even at small sizes the
            //     leading glyph reads as a secondary primary
            //     action; here we want a tertiary nudge.
            //     `accessory.systemImage` is deliberately
            //     ignored for `.footer` placement.
            //   • Plain body weight (`Sumi.Font.body()`), not
            //     `.bodyEmphasised()`. Done uses emphasised —
            //     keeping the accessory at body weight gives
            //     a clear visual hierarchy: Done = primary CTA
            //     (bold), accessory = secondary text affordance
            //     (regular). Same pattern as Apple Mail's
            //     bottom action bar (Edit/Cancel/Done where Edit
            //     and Cancel are regular weight and Done is
            //     emphasised).
            footerAccessoryButton.setTitle(accessory.title, for: .normal)
            footerAccessoryButton.titleLabel?.font = Sumi.Font.body()
            footerAccessoryButton.tintColor = Sumi.Color.accent
            footerAccessoryButton.setTitleColor(Sumi.Color.accent, for: .normal)
            footerAccessoryButton.contentHorizontalAlignment = .leading
            footerAccessoryButton.addTarget(
                self,
                action: #selector(footerAccessoryTapped),
                for: .touchUpInside
            )
            addSubview(footerAccessoryButton)
        } else {
            footerAccessoryButton.isHidden = true
        }

        let bottomDivider = UIView()
        bottomDivider.translatesAutoresizingMaskIntoConstraints = false
        bottomDivider.backgroundColor = Sumi.Color.separator
        bottomDivider.isHidden = !needsDoneButton
        addSubview(bottomDivider)

        // ---- Layout ----
        let messageTop = messageLabel?.topAnchor ?? topDivider.topAnchor
        var constraints: [NSLayoutConstraint] = [
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Sumi.Spacing.l + 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.l),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Sumi.Spacing.l),

            topDivider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: topDivider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),

            // ScrollView height: measured AFTER the stack is
            // populated, then clamped to maxScrollHeight. The
            // earlier per-row estimate (52pt single / 60pt with
            // subtitle) was a few pixels off from the actual
            // Dynamic-Type body+footnote layout, so even tiny
            // dialogs (Thumbnail Quality, Theme) ended up with
            // contentSize > frame and a useless scroll engaged.
            // Real measurement is exact: small lists fit and
            // never scroll; long lists clamp and scroll cleanly.
            scrollView.heightAnchor.constraint(equalToConstant: computeScrollHeight())
        ]
        if let messageLabel {
            constraints += [
                messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
                messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.l),
                messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Sumi.Spacing.l),
                topDivider.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: Sumi.Spacing.m)
            ]
        } else {
            constraints.append(topDivider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: Sumi.Spacing.m))
        }
        if needsDoneButton {
            constraints += [
                bottomDivider.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale),
                bottomDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
                bottomDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
                bottomDivider.topAnchor.constraint(equalTo: scrollView.bottomAnchor),

                counterLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.l),
                counterLabel.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),

                doneButton.topAnchor.constraint(equalTo: bottomDivider.bottomAnchor),
                doneButton.bottomAnchor.constraint(equalTo: bottomAnchor),
                doneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Sumi.Spacing.l),
                doneButton.heightAnchor.constraint(equalToConstant: 48),

                // Counter must yield ground (truncate) before
                // the Done button shrinks — Done is the action
                // CTA, must always be fully readable.
                counterLabel.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -Sumi.Spacing.s)
            ]
            if usesFooterAccessory {
                // Footer accessory sits on the LEADING side of
                // the footer, centred vertically with Done. The
                // counter is hidden in callsites that use a
                // footer accessory (single .accent-coloured text
                // button reads cleaner than counter + button + Done).
                counterLabel.isHidden = true
                constraints += [
                    footerAccessoryButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.l),
                    footerAccessoryButton.centerYAnchor.constraint(equalTo: doneButton.centerYAnchor),
                    footerAccessoryButton.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -Sumi.Spacing.m)
                ]
            }
        } else {
            constraints.append(scrollView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Sumi.Spacing.s))
        }
        _ = messageTop  // silence unused warning
        NSLayoutConstraint.activate(constraints)

        selectionHaptic.prepare()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Mode helpers

    private var showsCounter: Bool {
        if case .multi = mode { return true }
        return false
    }

    private var needsDoneButton: Bool {
        // Empty-state mode has no rows to pick — the user can
        // only tap the accessory (or dismiss). Done would be a
        // dead button.
        if emptyStateActive { return false }
        switch mode {
        case .single:    return false
        case .multi, .triState: return true
        }
    }

    private func indicatorStyleForMode() -> IndicatorStyle {
        switch mode {
        case .single:    return .radio
        case .multi:     return .checkbox
        case .triState:  return .triState
        }
    }

    // MARK: - Initial state

    private func applyInitialState() {
        for row in rows {
            switch mode {
            case .single:
                row.setSelected(row.choice.value == initialSingleSelection, animated: false)
            case .multi:
                row.setSelected(initialMultiSelection.contains(row.choice.value), animated: false)
            case .triState:
                let state = initialTriStates[row.choice.value] ?? .off
                row.setTriState(state, animated: false)
            }
        }
        updateCounter()
    }

    private func updateCounter() {
        guard showsCounter else { return }
        let count = initialMultiSelection.count
        // "N selected" lives in its own label in the footer,
        // separated from the Done button. Both have stable
        // widths — Done doesn't resize between taps and
        // counter doesn't crowd the title.
        counterLabel.text = count == 0 ? "" : "\(count) selected"
    }

    // MARK: - Tap handling

    private func handleTap(on row: ChoiceRowView) {
        guard !row.choice.isDisabled else { return }
        selectionHaptic.selectionChanged()
        selectionHaptic.prepare()

        switch mode {
        case .single:
            // Set the picked row, clear all others.
            for other in rows where other !== row {
                other.setSelected(false, animated: true)
            }
            row.setSelected(true, animated: true)
            onSinglePicked?(row.choice.value)
        case .multi:
            let nowSelected = !row.isCurrentlySelected
            row.setSelected(nowSelected, animated: true)
            if nowSelected {
                initialMultiSelection.insert(row.choice.value)
            } else {
                initialMultiSelection.remove(row.choice.value)
            }
            updateCounter()
            onMultiChanged?(initialMultiSelection)
        case .triState:
            let next = (initialTriStates[row.choice.value] ?? .off).cyclingNext
            initialTriStates[row.choice.value] = next
            row.setTriState(next, animated: true)
            onTriChanged?(initialTriStates)
        }
    }

    @objc private func doneTapped() {
        onDoneTapped?()
    }

    /// Footer-placed accessory tap — fires the SAME callback
    /// as the row/empty-state accessory variants (`.onAccessoryTapped`)
    /// so callers don't need to branch on placement to know
    /// "an accessory was tapped." Selection haptic mirrors the
    /// row variant for consistency.
    @objc private func footerAccessoryTapped() {
        UISelectionFeedbackGenerator().selectionChanged()
        onAccessoryTapped?()
    }

    /// Caps the dialog's scrollable area at ~52% of screen
    /// height. With title + done bar + paddings the entire
    /// card lands at roughly 65% of screen — comfortable on
    /// every iPhone size and never approaches the safe-area
    /// edges.
    private func maxScrollHeight() -> CGFloat {
        let screen = UIScreen.main.bounds.height
        return floor(screen * 0.52)
    }

    /// Measures the stack's natural height at the dialog's
    /// fixed 300pt width (set by `ChoiceDialogController`),
    /// then clamps to `maxScrollHeight()`. Called once after
    /// all rows + separators are added to `stack`, before the
    /// scrollView height constraint is activated, so the
    /// measurement reflects real Dynamic-Type-driven row
    /// heights instead of a hand-tuned estimate.
    ///
    /// Small dialogs (≤ a few rows) → measured == content,
    /// scroll never engages. Long dialogs (e.g. 25 languages)
    /// → measured > max, clamped to max, scroll engages.
    private func computeScrollHeight() -> CGFloat {
        let cardWidth: CGFloat = 300
        let fitting = stack.systemLayoutSizeFitting(
            CGSize(width: cardWidth, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        )
        return min(fitting.height, maxScrollHeight())
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

// MARK: - Empty-state view
//
// Self-contained block shown when the picker has zero
// choices. Three vertically-stacked elements:
//
//   • Icon — large SF symbol in textTertiary, sets the visual
//     anchor of "empty".
//   • Helper text — single line, textSecondary, explains why
//     the list is empty.
//   • Primary CTA — accent-filled capsule with the accessory's
//     title centred. The user's only forward action; styling
//     it as a button (not a list row) makes the affordance
//     obvious. Capsule height matches Apple's "comfortable CTA"
//     dimensions (44pt — minimum tap target, never less).
//
// The whole block has generous vertical padding so it doesn't
// crowd into the title above or the bottom edge.

private extension ChoiceDialogCard {
    func makeEmptyStateView(
        accessory: ChoiceDialog.PickerAccessory,
        onTap: @escaping () -> Void
    ) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "tray"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = Sumi.Color.textTertiary
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 32, weight: .regular
        )
        container.addSubview(icon)

        let helper = UILabel()
        helper.translatesAutoresizingMaskIntoConstraints = false
        helper.text = "Nothing here yet"
        helper.font = Sumi.Font.caption()
        helper.textColor = Sumi.Color.textSecondary
        helper.textAlignment = .center
        helper.numberOfLines = 0
        container.addSubview(helper)

        let cta = EmptyStateCTAButton(accessory: accessory, onTap: onTap)
        container.addSubview(cta)

        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),

            helper.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 12),
            helper.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Sumi.Spacing.l),
            helper.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Sumi.Spacing.l),

            cta.topAnchor.constraint(equalTo: helper.bottomAnchor, constant: 20),
            cta.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            cta.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: Sumi.Spacing.l),
            cta.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -Sumi.Spacing.l),
            cta.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24)
        ])
        return container
    }
}

// MARK: - Empty-state CTA
//
// Accent-filled capsule button used as the empty-state primary
// action. Sized to its content (intrinsic) with 16pt horizontal
// padding around the title — matches Apple's "Pill" CTA style.
// Press feedback: 0.96 scale + alpha 0.85, springs back on
// release (same motion language as the primary button).

@MainActor
private final class EmptyStateCTAButton: UIView {

    private let label = UILabel()
    private let iconView = UIImageView()
    private let onTap: () -> Void

    init(accessory: ChoiceDialog.PickerAccessory, onTap: @escaping () -> Void) {
        self.onTap = onTap
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = Sumi.Color.accent
        // 32pt height capsule — Apple's "compact CTA" size,
        // not the 44pt "comfortable" tap target. Inside a
        // modal dialog the surrounding chrome (title, dimmer,
        // explicit Done) already telegraphs "this is the
        // primary thing", so the button itself can stay
        // minimal — closer to a tag pill than a hero button.
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 12, weight: .semibold
        )
        iconView.image = accessory.systemImage.flatMap { UIImage(systemName: $0) }
        let hasIcon = iconView.image != nil
        if hasIcon { addSubview(iconView) }

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = accessory.title
        // 13pt semibold — smaller than `body` (17pt), tighter
        // than `caption` (~12pt). Reads as a compact button
        // label, not a body-text run.
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.numberOfLines = 1
        addSubview(label)

        var c: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 32),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14)
        ]
        if hasIcon {
            c += [
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 13),
                iconView.heightAnchor.constraint(equalToConstant: 13),
                label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6)
            ]
        } else {
            c += [
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14)
            ]
        }
        NSLayoutConstraint.activate(c)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)

        accessibilityLabel = accessory.title
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(
            withDuration: 0.10,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
            self.alpha = 0.85
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        restoreFromPress()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        restoreFromPress()
    }
    private func restoreFromPress() {
        UIView.animate(
            withDuration: 0.20,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.3,
            options: [.allowUserInteraction]
        ) {
            self.transform = .identity
            self.alpha = 1
        }
    }

    @objc private func tapped() {
        onTap()
    }
}

// MARK: - Accessory row
//
// Tappable row used as the "+ New …" affordance when the
// picker already has choices. Styled to match iOS Settings'
// "Add Account" pattern — identical row height to choice
// rows, accent body-weight text, leading plus-icon at the
// indicator alignment, same gentle gray press highlight as
// regular choice rows. NO special background, NO bold weight,
// NO accent-tinted highlight — those reads as "trying too
// hard". The accent text colour alone is enough to mark it
// as an action, not a category.

@MainActor
private final class AccessoryRowView: UIView {

    var onTap: (() -> Void)?

    init(accessory: ChoiceDialog.PickerAccessory) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = Sumi.Color.accent
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        iconView.image = accessory.systemImage.flatMap { UIImage(systemName: $0) }
        let hasIcon = iconView.image != nil

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = accessory.title
        // Regular body weight — matches ChoiceRowView's title
        // styling, just with accent colour. Bold here would
        // make the accessory shout louder than the categories
        // above it.
        label.font = Sumi.Font.body()
        label.textColor = Sumi.Color.accent
        label.numberOfLines = 1

        if hasIcon { addSubview(iconView) }
        addSubview(label)

        // Indicator-column alignment: choice rows put their
        // checkboxes at `Sumi.Spacing.l` (16pt) from leading,
        // centred in a 22pt slot. We mirror that so the plus
        // icon sits exactly where checkboxes do — visually the
        // accessory reads as "another row in the same list",
        // not a foreign element.
        let inset = Sumi.Spacing.l
        var c: [NSLayoutConstraint] = [
            heightAnchor.constraint(equalToConstant: 52)
        ]
        if hasIcon {
            c += [
                iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconView.widthAnchor.constraint(equalToConstant: 22),
                iconView.heightAnchor.constraint(equalToConstant: 22),

                label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Sumi.Spacing.m),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ]
        } else {
            c += [
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
                label.centerYAnchor.constraint(equalTo: centerYAnchor)
            ]
        }
        NSLayoutConstraint.activate(c)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)

        accessibilityLabel = accessory.title
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    @objc private func tapped() {
        onTap?()
    }

    // Match ChoiceRowView's press feedback exactly — gentle
    // gray fill, 0.06s in / 0.18s out. Using the same tint as
    // regular rows keeps the visual language consistent:
    // every tappable row in the dialog highlights the same way.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        UIView.animate(withDuration: 0.06) {
            self.backgroundColor = UIColor(white: 0.5, alpha: 0.10)
        }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        UIView.animate(withDuration: 0.18) {
            self.backgroundColor = .clear
        }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        UIView.animate(withDuration: 0.12) {
            self.backgroundColor = .clear
        }
    }
}
