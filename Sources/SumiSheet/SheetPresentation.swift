import UIKit
import Sumi

// SheetPresentation — owns the dimmer, the main card, the
// cancel card, the slide-up animation, the pan-to-dismiss
// gesture, and the result delivery.
//
// Static `live` registry (same pattern as `AlertPresentation` /
// `ChoiceDialogController`) keeps the instance alive between
// `attach()` and a user interaction; the local `presentation`
// var inside `SumiSheet.present(...)` would otherwise be the
// sole owner and the controller would deallocate before any
// row could tap.

@MainActor
final class SheetPresentation {

    private static var live: [SheetPresentation] = []

    private let mainCard: SheetContentCard
    private let cancelCard: SheetCancelCard?
    private let dimmer = UIView()
    private let completion: (Int?) -> Void

    private var didComplete = false
    private var bottomConstraint: NSLayoutConstraint?
    private var hostWindow: UIWindow?
    private var panInitialOffset: CGFloat = 0

    /// Generic over the content card (vertical / horizontal /
    /// future variants). `mainCard` provides the action list;
    /// the optional `cancelCard` is a separate floating card
    /// below, separated by a transparent 8pt gap that shows the
    /// dimmer through — gives the Apple-style two-card visual
    /// without the previous "channel strip" inside-the-card
    /// trick that the user rightly flagged as ugly.
    init(
        mainCard: SheetContentCard,
        cancelCard: SheetCancelCard?,
        actions: [SheetAction],
        completion: @escaping (Int?) -> Void
    ) {
        self.mainCard = mainCard
        self.cancelCard = cancelCard
        self.completion = completion

        let storedActions = actions

        mainCard.onActionPicked = { [weak self] index in
            guard let self else { return }
            storedActions[index].handler?()
            self.complete(with: index)
        }
        cancelCard?.onTap = { [weak self] in self?.complete(with: nil) }
    }

    // MARK: - Present

    func attach(to window: UIWindow) {
        Self.live.append(self)
        self.hostWindow = window

        // ---- Dimmer ----
        dimmer.translatesAutoresizingMaskIntoConstraints = false
        dimmer.backgroundColor = UIColor.black.withAlphaComponent(0)
        window.addSubview(dimmer)
        NSLayoutConstraint.activate([
            dimmer.topAnchor.constraint(equalTo: window.topAnchor),
            dimmer.bottomAnchor.constraint(equalTo: window.bottomAnchor),
            dimmer.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            dimmer.trailingAnchor.constraint(equalTo: window.trailingAnchor)
        ])
        let dimmerTap = UITapGestureRecognizer(target: self, action: #selector(dimmerTapped))
        dimmer.addGestureRecognizer(dimmerTap)

        // ---- Cards ----
        // Both cards sit inside a single container so they share
        // the slide-up animation and pan gesture as one unit.
        let cardContainer = UIView()
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.backgroundColor = .clear
        window.addSubview(cardContainer)

        cardContainer.addSubview(mainCard)
        NSLayoutConstraint.activate([
            mainCard.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            mainCard.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            mainCard.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor)
        ])

        if let cancelCard {
            cardContainer.addSubview(cancelCard)
            // 8pt transparent gap shows the dimmer through.
            // Two distinct cards, each with its own shadow + clip.
            NSLayoutConstraint.activate([
                cancelCard.topAnchor.constraint(equalTo: mainCard.bottomAnchor, constant: 8),
                cancelCard.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
                cancelCard.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
                cancelCard.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor)
            ])
        } else {
            mainCard.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor).isActive = true
        }

        // Container width: full-width minus 16pt side margins,
        // capped at 500pt (iPad). Bottom: 8pt above safe area.
        let bottomC = cardContainer.bottomAnchor.constraint(
            equalTo: window.safeAreaLayoutGuide.bottomAnchor,
            constant: -8
        )
        self.bottomConstraint = bottomC

        NSLayoutConstraint.activate([
            cardContainer.leadingAnchor.constraint(greaterThanOrEqualTo: window.leadingAnchor, constant: Sumi.Spacing.l),
            cardContainer.trailingAnchor.constraint(lessThanOrEqualTo: window.trailingAnchor, constant: -Sumi.Spacing.l),
            cardContainer.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            cardContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            // On phones we want full width minus margins; the
            // greaterThanOrEqual constraint above ensures that
            // when there's room (iPad), we hit the 500pt cap
            // instead. Equal width with priority < required
            // makes this resolve cleanly.
            cardContainer.widthAnchor.constraint(equalTo: window.widthAnchor, constant: -Sumi.Spacing.l * 2).withPriority(.defaultHigh),
            bottomC
        ])

        cardContainer.sumi_enableDynamicType()

        // Start off-screen below the safe area, animate up.
        window.layoutIfNeeded()
        let initialOffset = cardContainer.bounds.height + 32
        cardContainer.transform = CGAffineTransform(translationX: 0, y: initialOffset)

        UIView.animate(
            withDuration: Sumi.Motion.standard,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0.4,
            options: [.allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
            cardContainer.transform = .identity
        }

        // Pan-to-dismiss gesture on the container. Following
        // the iOS modal sheet UX: only DOWN drags translate the
        // sheet; up drags rubber-band with rapidly increasing
        // resistance so the sheet doesn't fly off the top.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panHandled(_:)))
        cardContainer.addGestureRecognizer(pan)

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Gestures

    @objc private func dimmerTapped() { complete(with: nil) }

    @objc private func panHandled(_ gesture: UIPanGestureRecognizer) {
        guard let container = gesture.view else { return }
        let translation = gesture.translation(in: container)

        switch gesture.state {
        case .began:
            panInitialOffset = container.transform.ty
        case .changed:
            // Only allow downward movement past the start; up
            // drags rubber-band: y = -sqrt(|dy|) so first 50pt
            // up move ~7pt of card.
            let raw = panInitialOffset + translation.y
            let resisted: CGFloat = raw < 0 ? -sqrt(-raw) : raw
            container.transform = CGAffineTransform(translationX: 0, y: resisted)
            // Dim fades as user pulls the sheet down.
            let progress = max(0, min(1, resisted / container.bounds.height))
            dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36 * (1 - progress))
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: container).y
            let translated = container.transform.ty
            // Dismiss threshold: pulled down past 40% of sheet
            // height OR strong downward fling (>800pt/s).
            let shouldDismiss = translated > container.bounds.height * 0.4 || velocity > 800
            if shouldDismiss {
                complete(with: nil)
            } else {
                UIView.animate(
                    withDuration: 0.32,
                    delay: 0,
                    usingSpringWithDamping: 0.82,
                    initialSpringVelocity: 0.4,
                    options: [.allowUserInteraction]
                ) {
                    container.transform = .identity
                    self.dimmer.backgroundColor = UIColor.black.withAlphaComponent(0.36)
                }
            }
        default:
            break
        }
    }

    // MARK: - Completion

    private func complete(with pickedIndex: Int?) {
        guard !didComplete else { return }
        didComplete = true

        // The card container is whichever superview the cards
        // share — find it via the mainCard's parent.
        let container = mainCard.superview
        let exitDistance: CGFloat = (container?.bounds.height ?? 300) + 64

        UIView.animate(
            withDuration: Sumi.Motion.fast,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction]
        ) {
            self.dimmer.backgroundColor = .clear
            container?.transform = CGAffineTransform(translationX: 0, y: exitDistance)
        } completion: { _ in
            container?.removeFromSuperview()
            self.dimmer.removeFromSuperview()
            self.completion(pickedIndex)
            Self.live.removeAll { $0 === self }
        }
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
