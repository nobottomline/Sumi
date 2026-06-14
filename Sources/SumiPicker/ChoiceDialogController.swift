import UIKit
import Sumi

// ChoiceDialogController — owns the dim layer + the card,
// drives the spring animation, holds the live selection,
// fires the completion when the user picks or cancels.
//
// Lives in a static `live` array (same retain-bug pattern
// used by AlertPresentation / MenuPresentationController):
// without it, the local controller inside `ChoiceDialog
// .presentSingle` deallocates before the user taps anything.

@MainActor
final class ChoiceDialogController {

    private static var live: [ChoiceDialogController] = []

    private let dialogTitle: String
    private let message: String?
    private let mode: DialogMode
    private let choices: [AnyChoice]
    private let completion: (DialogResult) -> Void

    private let dimmer = UIView()
    private let card: ChoiceDialogCard
    private var didComplete = false

    // Live selection state, depending on mode.
    private var singleSelection: AnyHashable?
    private var multiSelection: Set<AnyHashable> = []
    private var triStates: [AnyHashable: TriState] = [:]

    init<T: Hashable & Sendable>(
        title: String,
        message: String?,
        mode: DialogMode,
        choices: [Choice<T>],
        accessory: ChoiceDialog.PickerAccessory? = nil,
        completion: @escaping (DialogResult) -> Void
    ) {
        self.dialogTitle = title
        self.message = message
        self.mode = mode
        self.choices = choices.map { $0.erased() }
        self.completion = completion

        switch mode {
        case .single(let initial):
            self.singleSelection = initial
        case .multi(let initial):
            self.multiSelection = initial
        case .triState(let initial):
            self.triStates = initial
        }

        self.card = ChoiceDialogCard(
            title: title,
            message: message,
            mode: mode,
            choices: self.choices,
            accessory: accessory
        )
        card.initialSingleSelection = singleSelection
        card.initialMultiSelection = multiSelection
        card.initialTriStates = triStates

        card.onSinglePicked = { [weak self] value in
            // Auto-confirm + dismiss for single-select.
            self?.completeSingle(value)
        }
        card.onMultiChanged = { [weak self] newSet in
            self?.multiSelection = newSet
        }
        card.onTriChanged = { [weak self] newMap in
            self?.triStates = newMap
        }
        card.onDoneTapped = { [weak self] in
            self?.completeFromMode()
        }
        card.onAccessoryTapped = { [weak self] in
            self?.complete(with: .accessory)
        }
    }

    // MARK: - Present

    func present(in window: UIWindow) {
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(dimmerTapped))
        dimmer.addGestureRecognizer(tap)

        card.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: window.centerYAnchor, constant: -16),
            card.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            card.widthAnchor.constraint(equalToConstant: 300)
        ])

        card.sumi_enableDynamicType()

        // Spring scale-in.
        card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        card.alpha = 0
        window.layoutIfNeeded()
        UIView.animate(
            withDuration: Sumi.Motion.standard,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.40)
            self.card.transform = .identity
            self.card.alpha = 1
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Completion

    @objc private func dimmerTapped() {
        complete(with: .cancelled)
    }

    private func completeSingle(_ value: AnyHashable) {
        complete(with: .single(value))
    }

    private func completeFromMode() {
        switch mode {
        case .single:
            complete(with: .single(singleSelection))
        case .multi:
            complete(with: .multi(multiSelection))
        case .triState:
            complete(with: .triState(triStates))
        }
    }

    private func complete(with result: DialogResult) {
        guard !didComplete else { return }
        didComplete = true
        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            self.card.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            self.card.alpha = 0
        } completion: { _ in
            self.card.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(result)
            Self.live.removeAll { $0 === self }
        }
    }
}
