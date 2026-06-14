import UIKit
import Sumi

// MenuListView — Sumi's popover list.
//
// Visual model: ONE rounded blur card with hairline separators
// between rows and between sections. (Earlier versions rendered
// each MenuSection as its own floating mini-card with a 6pt
// gap between — the result felt enormous and fragmented, like
// multiple popovers stacked on top of each other. The single-
// card layout matches modern native context menus and
// every contemporary reference for tap-anchored action lists.)
//
// Capabilities:
//
//   1. Sections with optional uppercase title headers. Within
//      a section, rows are separated by hairlines; between
//      sections a slightly thicker divider draws the eye to
//      the group boundary.
//
//   2. Submenu navigation as a real navigation push: the
//      current page slides out to the LEFT, the submenu slides
//      in from the RIGHT, in the same direction as a UINav
//      push. Pop reverses. (The previous crossfade was the
//      single biggest UX gripe — felt like the menu was
//      "flickering" rather than navigating somewhere.)
//
//   3. Internal scroll only when content > available height.
//      The scroll view is always present in the hierarchy
//      (toggling its `isScrollEnabled` based on overflow keeps
//      the layout stable across page transitions) but bouncing
//      and scroll indicators stay off when there's nothing to
//      scroll.
//
//   4. Drag-to-select: a single long-press recogniser at
//      MenuListView level tracks the user's finger across rows
//      and highlights live with haptics.
//
//   5. Rich rows — subtitle, detail, badge, isSelected,
//      animateIconOnHighlight, submenu, toggle, slider — see
//      MenuAction.swift.

@MainActor
public final class MenuListView: UIView {

    // MARK: - Public API

    public var onActionPicked: (() -> Void)?

    /// Fired AFTER the current-page content has been rebuilt
    /// and laid out, with the new natural content height. The
    /// presenting controller (Menu / ContextMenu) listens to
    /// this and animates the outer menu frame so the popover
    /// grows / shrinks to match the new page. Important for
    /// submenu pushes where the submenu may be taller or
    /// shorter than the parent.
    public var onContentSizeShouldChange: ((CGFloat) -> Void)?

    public convenience init(actions: [MenuAction], isSearchable: Bool = false) {
        self.init(sections: [MenuSection(actions: actions)], isSearchable: isSearchable)
    }

    public init(sections: [MenuSection], isSearchable: Bool = false) {
        self.isSearchable = isSearchable
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        layer.cornerRadius = Sumi.Radius.card
        layer.cornerCurve = .continuous
        clipsToBounds = true

        setUpHierarchy()
        setUpGestures()

        pushPage(Page(sections: sections, parentTitle: nil), animation: .none)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Returns the natural (un-clamped) height of the CURRENT
    /// page's content for the given width.
    ///
    /// `Menu` / `ContextMenu` use this before adding the view
    /// to the window to compute the popover frame. Re-called
    /// after every page transition (and after search-filter
    /// changes) so the outer frame can be animated to match.
    public func naturalContentSize(forWidth width: CGFloat) -> CGSize {
        guard let currentPage = pageViewStack.last else {
            return CGSize(width: width, height: 0)
        }
        let pageHeight = currentPage.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let searchHeight: CGFloat = isSearchable
            ? Self.searchFieldHeight + Self.searchFieldBottomGap
            : 0
        return CGSize(width: width, height: pageHeight + searchHeight)
    }

    // MARK: - Constants

    private static let searchFieldHeight: CGFloat = 44
    private static let searchFieldBottomGap: CGFloat = 4  // hairline-thin gap between search and content

    /// Shared transition spec — used for both the inner side-slide
    /// AND the outer wrapper resize. Tuning notes:
    ///
    ///   • `duration: 0.42` — long enough that a tall submenu's
    ///     growth reads as a smooth motion, not a snap. Shorter
    ///     values (we tried 0.32) feel "stiff": the eye registers
    ///     the destination instantly, missing the in-between
    ///     frames that sell the height change.
    ///
    ///   • `damping: 0.86` — slight under-damping. Critical
    ///     damping (1.0) looks technically correct but reads as
    ///     "engineering, not motion design"; consumer-grade
    ///     popovers settle with a tiny soft overshoot, which is
    ///     what 0.86 produces. NOT enough to wobble — just
    ///     enough to feel alive.
    ///
    ///   • `initialSpringVelocity: 0` — no kick at start, lets
    ///     the spring's natural acceleration carry the motion
    ///     from rest. Earlier versions used 0.2 which caused the
    ///     "abrupt rise" complaint: the menu shot upward at the
    ///     very first frame before the spring's ease-in kicked in.
    static let transitionDuration: TimeInterval = 0.42
    private static let transitionDamping: CGFloat = 0.86
    private static let transitionInitialVelocity: CGFloat = 0

    // MARK: - Hierarchy
    //
    //   self  (rounded clip + outer blur)
    //     ├─ blurBackground   (UIVisualEffectView, fills self)
    //     ├─ searchField      (optional, top)
    //     └─ scrollView       (fills below search field)
    //          └─ pageStage   (UIView — host for currentPage,
    //                          and during transition for old
    //                          page sliding out)
    //               └─ currentPage : PageContentView

    private let isSearchable: Bool
    private let blurBackground = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let searchField = MenuSearchField()
    private let scrollView = UIScrollView()
    private let pageStage = UIView()

    fileprivate struct Page {
        let sections: [MenuSection]
        /// Parent action's title — used to label the back row.
        /// `nil` on the root page (no back row drawn).
        let parentTitle: String?
    }

    private var pageStack: [Page] = []
    private var pageViewStack: [PageContentView] = []  // parallel to pageStack
    private var transitionInProgress = false
    /// Drives `pageStage`'s height. Pages don't pin their bottom
    /// edges to `pageStage` (which would force every page to the
    /// same height — squishing the new page to the old page's
    /// size during a transition). Instead we own height
    /// explicitly here and animate this constraint's `constant`
    /// inside the same `UIView.animate` block that drives the
    /// side-slide, so stage height + page slide + outer wrapper
    /// resize all play on one shared spring curve.
    private var stageHeightConstraint: NSLayoutConstraint?

    // Gesture / press-tracking state
    private weak var currentlyHighlightedView: UIView?
    private let selectionHaptic = UISelectionFeedbackGenerator()
    private var pressStartScrollOffset: CGFloat = 0
    private var didScrollDuringPress = false

    private func setUpHierarchy() {
        blurBackground.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurBackground)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.contentInsetAdjustmentBehavior = .never
        // No 150 ms wait before touches reach subviews — UISlider
        // thumb-drag and text-field tap would otherwise feel
        // unresponsive on quick gestures.
        scrollView.delaysContentTouches = false
        addSubview(scrollView)

        pageStage.translatesAutoresizingMaskIntoConstraints = false
        pageStage.clipsToBounds = true  // submenu slides outside its bounds during transition; clip prevents leak
        scrollView.addSubview(pageStage)

        let stageHeight = pageStage.heightAnchor.constraint(equalToConstant: 100)
        self.stageHeightConstraint = stageHeight

        var c: [NSLayoutConstraint] = [
            blurBackground.topAnchor.constraint(equalTo: topAnchor),
            blurBackground.bottomAnchor.constraint(equalTo: bottomAnchor),
            blurBackground.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurBackground.trailingAnchor.constraint(equalTo: trailingAnchor),

            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            // pageStage's bottom is NOT pinned to contentLayoutGuide.
            // Its height is driven by `stageHeightConstraint`; the
            // scroll view derives its contentSize from pageStage's
            // resulting frame. This decouples pageStage's size
            // from any individual page — pages can be at their own
            // natural intrinsic heights without fighting each other
            // for the parent's bottom edge.
            pageStage.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            pageStage.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            pageStage.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            pageStage.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            pageStage.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            stageHeight
        ]
        if isSearchable {
            searchField.translatesAutoresizingMaskIntoConstraints = false
            searchField.onTextChange = { [weak self] text in self?.applyFilter(text) }
            addSubview(searchField)
            c += [
                searchField.topAnchor.constraint(equalTo: topAnchor),
                searchField.leadingAnchor.constraint(equalTo: leadingAnchor),
                searchField.trailingAnchor.constraint(equalTo: trailingAnchor),
                searchField.heightAnchor.constraint(equalToConstant: Self.searchFieldHeight),
                scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: Self.searchFieldBottomGap)
            ]
        } else {
            c.append(scrollView.topAnchor.constraint(equalTo: topAnchor))
        }
        NSLayoutConstraint.activate(c)
    }

    // MARK: - Gestures
    //
    // Single UILongPressGestureRecognizer with minimumPressDuration = 0
    // tracks finger across rows and lights up whichever row is
    // under the touch. Same one-gesture-handles-everything pattern
    // as the previous implementation — keeps slider drag, search
    // field tap, and scroll pan all working alongside row tracking.

    private func setUpGestures() {
        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.allowableMovement = .infinity
        press.delaysTouchesBegan = false
        // Don't swallow touches — slider / search field / scroll
        // all need their own gesture pipelines.
        press.cancelsTouchesInView = false
        press.delegate = self
        addGestureRecognizer(press)
        selectionHaptic.prepare()
    }

    // MARK: - Page navigation

    private enum TransitionDirection {
        case none      // initial render — no animation
        case forward   // pushing into a submenu (slide right→left)
        case backward  // popping back to parent (slide left→right)
    }

    private func pushPage(_ page: Page, animation direction: TransitionDirection) {
        let pageView = PageContentView(
            page: page,
            parentTitle: page.parentTitle,
            onActionPick: { [weak self] in self?.handleActionPick($0) }
        )
        pageStack.append(page)
        pageViewStack.append(pageView)
        installCurrentPage(direction: direction)
    }

    private func popPage() {
        guard pageStack.count > 1, !transitionInProgress else { return }
        pageStack.removeLast()
        pageViewStack.removeLast()
        installCurrentPage(direction: .backward)
    }

    /// Install the top-of-stack PageContentView into `pageStage`,
    /// optionally side-sliding the previous page off and the
    /// new page on.
    ///
    /// Layout principle: pages NEVER pin their bottom edge to
    /// `pageStage`. Each page sits at its own intrinsic height
    /// (driven by the row stack inside). `pageStage`'s height
    /// is controlled separately by `stageHeightConstraint`.
    /// This decoupling fixes the "submenu rows squished then
    /// stretch" bug — previously both pages were pinned to the
    /// stage's bottom, forcing the new page into the old page's
    /// height during the transition.
    private func installCurrentPage(direction: TransitionDirection) {
        guard let newPage = pageViewStack.last else { return }
        let outgoingPage = pageStage.subviews.compactMap { $0 as? PageContentView }.last

        clearHighlight(animated: false)

        pageStage.addSubview(newPage)
        newPage.translatesAutoresizingMaskIntoConstraints = false
        // No bottom pin — newPage's height comes from its own
        // intrinsic content (the row stack inside PageContentView).
        NSLayoutConstraint.activate([
            newPage.topAnchor.constraint(equalTo: pageStage.topAnchor),
            newPage.leadingAnchor.constraint(equalTo: pageStage.leadingAnchor),
            newPage.widthAnchor.constraint(equalTo: pageStage.widthAnchor)
        ])

        // Measure new page's natural height at the menu's
        // standard width. Use `bounds.width` if we've been laid
        // out, otherwise fall back to 280 (Sumi's menu/popover
        // standard) — without this fallback the first
        // `installCurrentPage` call at init time would measure
        // against `width=0` and return `height=0`, leaving the
        // stage collapsed until the next layout pass. `ContextMenu`
        // hit that on every present because its wrapper is
        // AutoLayout-positioned (no explicit `frame` is set
        // synchronously like the `Menu` controller does) — the
        // menu rendered with zero height and looked invisible.
        if bounds.width > 0 {
            pageStage.layoutIfNeeded()
        }
        let measurementWidth = bounds.width > 0 ? bounds.width : 250
        let newPageHeight = newPage.systemLayoutSizeFitting(
            CGSize(width: measurementWidth, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        let totalHeight = newPageHeight + (isSearchable ? Self.searchFieldHeight + Self.searchFieldBottomGap : 0)
        scrollView.setContentOffset(.zero, animated: false)

        // Initial render — no slide, no spring. Sync everything
        // immediately.
        if direction == .none || outgoingPage == nil {
            stageHeightConstraint?.constant = newPageHeight
            onContentSizeShouldChange?(totalHeight)
            setNeedsLayout()
            layoutIfNeeded()
            updateScrollEnabled()
            return
        }

        let stageWidth = bounds.width

        switch direction {
        case .forward:
            newPage.transform = CGAffineTransform(translationX: stageWidth, y: 0)
        case .backward:
            newPage.transform = CGAffineTransform(translationX: -stageWidth, y: 0)
        case .none:
            break
        }

        // One animation block — three coordinated changes:
        //   1. inner page slide (transforms on old + new page)
        //   2. stage height grow / shrink (constraint constant)
        //   3. outer wrapper resize (the controller's callback —
        //      it animates `wrapper.frame.height` using the same
        //      spring spec from `Self.transitionDuration` /
        //      `transitionDamping` / `transitionInitialVelocity`)
        //
        // All three are kicked off inside the SAME `UIView.animate`
        // call on the SAME run-loop tick. They share a spring,
        // start at the same frame, and finish at the same frame.
        // Earlier code triggered the wrapper resize a microsecond
        // before this block, so even with identical params the
        // two animations were one frame offset and read as
        // "wrapper grows, then content slides" — exactly the
        // "abrupt rise" the user reported.
        transitionInProgress = true
        UIView.animate(
            withDuration: Self.transitionDuration,
            delay: 0,
            usingSpringWithDamping: Self.transitionDamping,
            initialSpringVelocity: Self.transitionInitialVelocity,
            options: [.allowUserInteraction, .curveEaseOut]
        ) {
            newPage.transform = .identity
            switch direction {
            case .forward:
                outgoingPage?.transform = CGAffineTransform(translationX: -stageWidth, y: 0)
            case .backward:
                outgoingPage?.transform = CGAffineTransform(translationX: stageWidth, y: 0)
            case .none:
                break
            }
            self.stageHeightConstraint?.constant = newPageHeight
            // Tell the presenting controller to animate the
            // wrapper frame NOW — inside this block — so its
            // animation joins ours.
            self.onContentSizeShouldChange?(totalHeight)
            self.layoutIfNeeded()
        } completion: { [weak self, weak outgoingPage] _ in
            outgoingPage?.removeFromSuperview()
            self?.transitionInProgress = false
            self?.updateScrollEnabled()
        }
    }

    /// Disable bounce + indicator when content fits — the user's
    /// complaint about "scroll where there shouldn't be one"
    /// usually traces to a 1-pixel rounding mismatch making
    /// scroll think it has overflow. Explicitly clamping here.
    private func updateScrollEnabled() {
        let needsScroll = scrollView.contentSize.height > scrollView.bounds.height + 0.5
        scrollView.isScrollEnabled = needsScroll
        scrollView.showsVerticalScrollIndicator = needsScroll
    }

    /// Width at which we last measured the current page's
    /// intrinsic height. Re-measuring only when this changes
    /// (vs. on every layout pass) prevents a feedback loop:
    /// `layoutSubviews` updates the height constraint →
    /// triggers another layout → measures again → adjusts by
    /// fractional pixels → wobble. The user reported this as
    /// "menu jumps when I drag my finger over rows."
    private var lastMeasuredWidth: CGFloat = 0

    public override func layoutSubviews() {
        super.layoutSubviews()
        if let page = pageViewStack.last,
           bounds.width > 0,
           abs(bounds.width - lastMeasuredWidth) > 0.5 {
            let measured = page.systemLayoutSizeFitting(
                CGSize(width: bounds.width, height: UIView.layoutFittingExpandedSize.height),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel
            ).height
            stageHeightConstraint?.constant = measured
            lastMeasuredWidth = bounds.width
        }
        updateScrollEnabled()
    }

    // MARK: - Action handling

    private func handleActionPick(_ action: MenuAction) {
        guard action.style != .disabled else { return }
        if let submenu = action.submenu {
            pushPage(Page(sections: submenu, parentTitle: action.title), animation: .forward)
        } else {
            action.handler()
            onActionPicked?()
        }
    }

    // MARK: - Press gesture (drag-to-select)

    @objc private func handlePress(_ gesture: UILongPressGestureRecognizer) {
        guard !transitionInProgress else { return }
        let point = gesture.location(in: self)
        let touched: UIView? = visibleRowAt(point) ?? visibleBackRowAt(point)

        switch gesture.state {
        case .began:
            pressStartScrollOffset = scrollView.contentOffset.y
            didScrollDuringPress = false
            setHighlight(to: touched, fireHaptic: true)

        case .changed:
            // Treat as scroll, not tap, once user has dragged
            // the scroll content more than 4 pt — abandon any
            // highlight to avoid the "row stays lit while
            // content moves under finger" jank.
            if abs(scrollView.contentOffset.y - pressStartScrollOffset) > 4 {
                didScrollDuringPress = true
                clearHighlight(animated: false)
                return
            }
            setHighlight(to: touched, fireHaptic: true)

        case .ended:
            if didScrollDuringPress {
                didScrollDuringPress = false
                currentlyHighlightedView = nil
                return
            }
            let finger = currentlyHighlightedView
            currentlyHighlightedView = nil
            setHighlightAppearance(finger, highlighted: false, animated: true)

            if let row = finger as? MenuRowView, row.action.style != .disabled {
                if let toggle = row.action.toggle, row.action.submenu == nil {
                    _ = toggle  // silence unused
                    row.flipToggle()
                } else {
                    handleActionPick(row.action)
                }
            } else if finger is MenuBackRowView {
                popPage()
            }

        case .cancelled, .failed:
            clearHighlight(animated: true)

        default:
            break
        }
    }

    private func setHighlight(to view: UIView?, fireHaptic: Bool) {
        guard view !== currentlyHighlightedView else { return }
        setHighlightAppearance(currentlyHighlightedView, highlighted: false, animated: false)
        setHighlightAppearance(view, highlighted: true, animated: false)
        currentlyHighlightedView = view
        if fireHaptic, view != nil {
            selectionHaptic.selectionChanged()
            selectionHaptic.prepare()
        }
    }

    private func clearHighlight(animated: Bool) {
        setHighlightAppearance(currentlyHighlightedView, highlighted: false, animated: animated)
        currentlyHighlightedView = nil
    }

    private func setHighlightAppearance(_ view: UIView?, highlighted: Bool, animated: Bool) {
        (view as? MenuRowView)?.setHighlighted(highlighted, animated: animated)
        (view as? MenuBackRowView)?.setHighlighted(highlighted, animated: animated)
    }

    private func visibleRowAt(_ point: CGPoint) -> MenuRowView? {
        guard let page = pageViewStack.last else { return nil }
        for row in page.rows where row.participatesInRowGesture && !row.isHidden {
            let converted = convert(point, to: row)
            if row.bounds.insetBy(dx: 0, dy: -1).contains(converted) {
                return row
            }
        }
        return nil
    }

    private func visibleBackRowAt(_ point: CGPoint) -> MenuBackRowView? {
        guard let page = pageViewStack.last, let back = page.backRow else { return nil }
        let converted = convert(point, to: back)
        if back.bounds.insetBy(dx: 0, dy: -1).contains(converted) {
            return back
        }
        return nil
    }

    // MARK: - Search

    private func applyFilter(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
        pageViewStack.last?.applyFilter(query)
        // Filter changed visible rows — re-measure current page,
        // animate stage height + outer wrapper height to match.
        guard let page = pageViewStack.last else { return }
        setNeedsLayout()
        layoutIfNeeded()
        let newPageHeight = page.systemLayoutSizeFitting(
            CGSize(width: bounds.width, height: UIView.layoutFittingExpandedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        let totalHeight = newPageHeight + (isSearchable ? Self.searchFieldHeight + Self.searchFieldBottomGap : 0)
        // Same spring as page transitions — keeps the filter-
        // shrink/grow consistent with submenu navigation feel.
        UIView.animate(
            withDuration: Self.transitionDuration,
            delay: 0,
            usingSpringWithDamping: Self.transitionDamping,
            initialSpringVelocity: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            self.stageHeightConstraint?.constant = newPageHeight
            self.onContentSizeShouldChange?(totalHeight)
            self.layoutIfNeeded()
        }
        updateScrollEnabled()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MenuListView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return true
    }
}

// MARK: - PageContentView
//
// One "page" of the menu. Renders the back row (if submenu),
// section titles, rows, and the hairlines / dividers between
// them, all in a single vertical stack. Unlike the previous
// MenuSectionCard the rows are NOT wrapped in a per-section
// blur/round-clip; the parent MenuListView owns the unified
// card shell, and we just lay out content inline.

@MainActor
final class PageContentView: UIView {

    let sections: [MenuSection]
    let parentTitle: String?
    let rows: [MenuRowView]
    let backRow: MenuBackRowView?
    let onActionPick: (MenuAction) -> Void

    private let stack = UIStackView()
    private var rowToSection: [MenuRowView: Int] = [:]
    private var sectionHeaders: [Int: UIView] = [:]
    private var sectionDividers: [Int: UIView] = [:]
    private var rowInteriorSeparators: [Int: [UIView]] = [:]  // section idx → separators inside the section

    fileprivate init(
        page: MenuListView.Page,
        parentTitle: String?,
        onActionPick: @escaping (MenuAction) -> Void
    ) {
        self.sections = page.sections
        self.parentTitle = parentTitle
        self.rows = page.sections.flatMap { $0.actions.map(MenuRowView.init) }
        self.backRow = parentTitle.map(MenuBackRowView.init)
        self.onActionPick = onActionPick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 0
        stack.alignment = .fill
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        buildLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func buildLayout() {
        // Back row first — pseudo-row that pops to parent on
        // tap. The MenuListView's gesture handler treats it the
        // same as a real row for highlight + finger-drag, but
        // dispatches to popPage() instead of handler().
        if let backRow = backRow {
            stack.addArrangedSubview(backRow)
            // Hairline below the back row, drawn at row-edge
            // (no inset) to read as the boundary between
            // navigation chrome and content. Inter-section
            // dividers below are inset-rendered so this one
            // is visually distinguishable.
            stack.addArrangedSubview(Self.makeFullWidthHairline())
        }

        // Walk sections — each contributes a title (optional),
        // its rows separated by hairlines, and a thicker
        // inter-section divider before the NEXT section.
        var allRows: [MenuRowView] = []
        for (sectionIdx, section) in sections.enumerated() {
            if sectionIdx > 0 {
                // Section divider — slightly thicker, drawn full
                // width. The visual rhythm: thin hairline between
                // rows of the same section, medium divider
                // between sections. Cheaper and tidier than a
                // gap-with-different-background; one continuous
                // surface keeps the menu reading as a single
                // panel.
                let divider = Self.makeSectionDivider()
                stack.addArrangedSubview(divider)
                sectionDividers[sectionIdx] = divider
            }

            if let title = section.title {
                let header = Self.makeSectionHeader(text: title)
                stack.addArrangedSubview(header)
                sectionHeaders[sectionIdx] = header
            }

            var separators: [UIView] = []
            for (rowIdx, _) in section.actions.enumerated() {
                let rowView = self.rows[allRows.count]
                allRows.append(rowView)
                rowToSection[rowView] = sectionIdx

                if rowIdx > 0 {
                    // Hairline between rows of the same section
                    // — inset by the row's leading padding so the
                    // separator visually starts where the row's
                    // content does, NOT edge-to-edge. Same
                    // pattern as `UITableView`'s default cell
                    // separator inset.
                    let hairline = Self.makeIntraSectionHairline()
                    stack.addArrangedSubview(hairline)
                    separators.append(hairline)
                }
                stack.addArrangedSubview(rowView)
            }
            rowInteriorSeparators[sectionIdx] = separators
        }
    }

    func applyFilter(_ query: String) {
        guard !query.isEmpty else {
            // Empty query — restore everything.
            for row in rows { row.isHidden = false }
            for (_, header) in sectionHeaders { header.isHidden = false }
            for (_, divider) in sectionDividers { divider.isHidden = false }
            for (_, seps) in rowInteriorSeparators { seps.forEach { $0.isHidden = false } }
            return
        }
        // Per-row filter. Then hide section headers / dividers
        // for empty sections, and recompute which intra-section
        // hairlines should show (only between two visible
        // adjacent rows in the same section).
        var sectionVisibleCount: [Int: Int] = [:]
        for row in rows {
            let matches = row.action.title.lowercased().contains(query)
            row.isHidden = !matches
            if matches, let s = rowToSection[row] {
                sectionVisibleCount[s, default: 0] += 1
            }
        }
        for (sectionIdx, header) in sectionHeaders {
            header.isHidden = (sectionVisibleCount[sectionIdx, default: 0] == 0)
        }
        // First-non-empty section gets no divider above it; once
        // a section has matches and we've seen a previous match,
        // its divider shows.
        var sawAnyVisible = false
        for sectionIdx in 0..<sections.count {
            let hasVisible = sectionVisibleCount[sectionIdx, default: 0] > 0
            if let divider = sectionDividers[sectionIdx] {
                divider.isHidden = !(hasVisible && sawAnyVisible)
            }
            if hasVisible { sawAnyVisible = true }
        }
        // Intra-section hairlines: show only between two
        // consecutive visible rows in the same section.
        for (sectionIdx, separators) in rowInteriorSeparators {
            let sectionRows = sections[sectionIdx].actions.indices.map { actionIdx -> MenuRowView in
                // Locate the rowView for (sectionIdx, actionIdx)
                let absoluteIdx = sections.prefix(sectionIdx).reduce(0) { $0 + $1.actions.count } + actionIdx
                return rows[absoluteIdx]
            }
            for (sepIdx, sep) in separators.enumerated() {
                // Separator between rowIdx sepIdx and sepIdx+1.
                let above = sectionRows[sepIdx]
                let below = sectionRows[sepIdx + 1]
                sep.isHidden = above.isHidden || below.isHidden
            }
        }
    }

    // MARK: Visual primitives

    private static func makeIntraSectionHairline() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = Sumi.Color.separator
        // Inset matches MenuRowView's leading padding so the
        // hairline starts where the row's text starts.
        let inset = Sumi.Spacing.l
        let inner = UIView()
        inner.translatesAutoresizingMaskIntoConstraints = false
        inner.backgroundColor = Sumi.Color.separator
        v.backgroundColor = .clear
        v.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: inset),
            inner.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            inner.topAnchor.constraint(equalTo: v.topAnchor),
            inner.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            v.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
        return v
    }

    private static func makeFullWidthHairline() -> UIView {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = Sumi.Color.separator
        v.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale).isActive = true
        return v
    }

    private static func makeSectionDivider() -> UIView {
        // 4pt — slightly thicker than the row hairlines (1px),
        // distinct enough to read as "new group" but not so
        // big that 3-section menus balloon. Earlier value was
        // 6pt which made multi-section menus feel chunky next
        // to the source they anchor against.
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = Sumi.Color.separator
        v.heightAnchor.constraint(equalToConstant: 4).isActive = true
        return v
    }

    /// UILabel can't carry its own padding (`layoutMargins` is
    /// metadata for AutoLayout-driven containers; UILabel
    /// doesn't read it for self-drawing). Wrap in a UIView with
    /// constraint-based insets so the header text sits within
    /// the menu's bounds with the same horizontal inset as the
    /// rows. Earlier code stored the bare UILabel and tried to
    /// set `layoutMargins` on it from `layoutSubviews` — no
    /// effect, the text rendered at the label's leading edge
    /// (which under `.fill` stack alignment ends up exactly at
    /// the menu's leading edge, then visually appears to "hang
    /// off the left" of the rounded card because of the
    /// 16pt corner curve).
    private static func makeSectionHeader(text: String) -> UIView {
        let wrapper = UIView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.backgroundColor = .clear

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text.uppercased()
        label.font = UIFont.systemFont(ofSize: 11, weight: .semibold).sumiSized(11)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Sumi.Color.textSecondary
        label.numberOfLines = 1
        wrapper.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: Sumi.Spacing.l),
            label.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor, constant: -Sumi.Spacing.l),
            label.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            label.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -6)
        ])
        return wrapper
    }
}

// MARK: - Back row
//
// Single tappable header at the top of a submenu page. Looks
// like a regular row (chevron-left + parent title), shares the
// same hover-highlight machinery as `MenuRowView`. Touch
// handling lives in MenuListView's long-press recogniser.

@MainActor
final class MenuBackRowView: UIView {

    let parentTitle: String
    private let label = UILabel()
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.left"))
    private var isCurrentlyHighlighted = false

    init(parentTitle: String) {
        self.parentTitle = parentTitle
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isUserInteractionEnabled = false  // parent gesture owns touches

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = Sumi.Color.accent
        chevron.contentMode = .scaleAspectFit
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body, scale: .medium)
        addSubview(chevron)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = parentTitle
        label.font = Sumi.Font.bodyEmphasised()
        label.textColor = Sumi.Color.textPrimary
        label.numberOfLines = 1
        addSubview(label)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            chevron.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.l),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: chevron.trailingAnchor, constant: Sumi.Spacing.s),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Sumi.Spacing.l)
        ])

        accessibilityLabel = "Back to \(parentTitle)"
        accessibilityTraits = .button
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func setHighlighted(_ highlighted: Bool, animated: Bool) {
        guard highlighted != isCurrentlyHighlighted else { return }
        isCurrentlyHighlighted = highlighted
        let target: UIColor = highlighted ? UIColor(white: 0.5, alpha: 0.16) : .clear
        let updates = { self.backgroundColor = target }
        if animated {
            UIView.animate(withDuration: 0.18, animations: updates)
        } else {
            updates()
        }
    }
}

// MARK: - Search field
//
// Used when `isSearchable: true` is passed to MenuListView.
// Distinct top-of-card UI; lives outside the scrolling page
// stage so it stays fixed during page transitions.

@MainActor
final class MenuSearchField: UIView {

    var onTextChange: ((String) -> Void)?

    private let textField = UITextField()
    private let iconView = UIImageView(image: UIImage(systemName: "magnifyingglass"))

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = Sumi.Color.textSecondary
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        addSubview(iconView)

        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = Sumi.Font.body()
        textField.textColor = Sumi.Color.textPrimary
        textField.clearButtonMode = .whileEditing
        textField.placeholder = "Search"
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.returnKeyType = .done
        textField.addTarget(self, action: #selector(editingChanged), for: .editingChanged)
        addSubview(textField)

        let underline = UIView()
        underline.translatesAutoresizingMaskIntoConstraints = false
        underline.backgroundColor = Sumi.Color.separator
        addSubview(underline)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Sumi.Spacing.l),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            textField.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Sumi.Spacing.m),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Sumi.Spacing.l),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),

            // Hairline along the bottom — reads as the boundary
            // between the search bar and the content below.
            underline.leadingAnchor.constraint(equalTo: leadingAnchor),
            underline.trailingAnchor.constraint(equalTo: trailingAnchor),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor),
            underline.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    var text: String { textField.text ?? "" }

    @objc private func editingChanged() {
        onTextChange?(text)
    }
}

// MARK: - Row
//
// Single tappable row. Owns its own visual layout (icon /
// title / subtitle / right slot — chevron, toggle, slider,
// checkmark, detail, badge). Highlight is driven externally
// by MenuListView's gesture handler.

@MainActor
public final class MenuRowView: UIView {

    public let action: MenuAction

    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailLabel = UILabel()
    private let iconView = UIImageView()
    private let badgeView = BadgeView()
    private let switchView = UISwitch()
    private let slider = UISlider()
    private let sliderValueLabel = UILabel()

    private var isCurrentlyHighlighted = false
    fileprivate private(set) var liveToggleIsOn: Bool

    private let rightSlotKind: RightSlotKind
    private enum RightSlotKind { case chevron, toggle, slider, check, icon, none }

    var participatesInRowGesture: Bool {
        switch rightSlotKind {
        case .slider: return false
        default:      return true
        }
    }

    init(action: MenuAction) {
        self.action = action
        self.liveToggleIsOn = action.toggle?.isOn ?? false

        if action.submenu != nil {
            self.rightSlotKind = .chevron
        } else if action.slider != nil {
            self.rightSlotKind = .slider
        } else if action.toggle != nil {
            self.rightSlotKind = .toggle
        } else if action.isSelected {
            self.rightSlotKind = .check
        } else if action.systemImage != nil && action.detail == nil && action.badge == nil {
            self.rightSlotKind = .icon
        } else {
            self.rightSlotKind = .none
        }

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isUserInteractionEnabled = (rightSlotKind == .slider)

        let height: CGFloat
        if rightSlotKind == .slider {
            // Stacked layout: title row on top, slider below. Must be
            // tall enough that the title's full line box (descenders —
            // g, p, y, j) clears the slider. At 64 the content needed
            // ~68 (8 top + title + 4 gap + 28 slider + 6 bottom), so
            // Auto Layout compressed the title label and clipped the
            // "g" tail. 72 leaves the title at its natural height.
            height = 72
        } else if action.subtitle != nil {
            height = 56
        } else {
            height = 44
        }
        heightAnchor.constraint(equalToConstant: height).isActive = true

        let tint: UIColor
        switch action.style {
        case .default:     tint = Sumi.Color.textPrimary
        case .destructive: tint = Sumi.Color.danger
        case .disabled:    tint = Sumi.Color.textSecondary
        }

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = action.title
        titleLabel.font = Sumi.Font.body()
        titleLabel.textColor = tint
        titleLabel.numberOfLines = 1
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.text = action.subtitle
        subtitleLabel.font = Sumi.Font.caption()
        subtitleLabel.textColor = Sumi.Color.textSecondary
        subtitleLabel.numberOfLines = 1
        subtitleLabel.isHidden = (action.subtitle == nil)
        addSubview(subtitleLabel)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = Sumi.Font.body()
        detailLabel.textColor = Sumi.Color.textSecondary
        detailLabel.textAlignment = .right
        detailLabel.numberOfLines = 1
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        detailLabel.setContentHuggingPriority(.required, for: .horizontal)
        detailLabel.text = action.detail
        detailLabel.isHidden = (action.detail == nil)
        addSubview(detailLabel)

        badgeView.translatesAutoresizingMaskIntoConstraints = false
        if let badgeText = action.badge {
            badgeView.configure(text: badgeText, accent: action.style == .destructive ? Sumi.Color.danger : Sumi.Color.accent)
            badgeView.isHidden = false
        } else {
            badgeView.isHidden = true
        }
        badgeView.setContentCompressionResistancePriority(.required, for: .horizontal)
        badgeView.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(badgeView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.tintColor = tint
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        switch rightSlotKind {
        case .chevron:
            iconView.image = UIImage(systemName: "chevron.right")
            iconView.tintColor = Sumi.Color.textTertiary
        case .check:
            iconView.image = UIImage(systemName: "checkmark")
            iconView.tintColor = Sumi.Color.accent
        case .icon:
            iconView.image = UIImage(systemName: action.systemImage ?? "")
        case .toggle, .slider, .none:
            iconView.image = nil
        }
        addSubview(iconView)

        switchView.translatesAutoresizingMaskIntoConstraints = false
        switchView.onTintColor = Sumi.Color.accent
        switchView.setContentHuggingPriority(.required, for: .horizontal)
        switchView.isUserInteractionEnabled = false  // parent gesture owns the tap → flip
        if let toggle = action.toggle {
            switchView.isOn = toggle.isOn
            switchView.isHidden = false
        } else {
            switchView.isHidden = true
        }
        addSubview(switchView)

        slider.translatesAutoresizingMaskIntoConstraints = false
        sliderValueLabel.translatesAutoresizingMaskIntoConstraints = false
        sliderValueLabel.font = Sumi.Font.caption()
        sliderValueLabel.textColor = Sumi.Color.textSecondary
        sliderValueLabel.textAlignment = .right
        sliderValueLabel.setContentHuggingPriority(.required, for: .horizontal)
        if let sliderModel = action.slider {
            slider.minimumValue = Float(sliderModel.range.lowerBound)
            slider.maximumValue = Float(sliderModel.range.upperBound)
            slider.value = Float(sliderModel.value)
            slider.minimumTrackTintColor = Sumi.Color.accent
            sliderValueLabel.text = sliderModel.formatter(sliderModel.value)
            slider.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
            slider.isHidden = false
            sliderValueLabel.isHidden = false
        } else {
            slider.isHidden = true
            sliderValueLabel.isHidden = true
        }
        addSubview(slider)
        addSubview(sliderValueLabel)

        configureConstraints()

        isAccessibilityElement = true
        var accessibilityLabelText = action.title
        if let subtitle = action.subtitle { accessibilityLabelText += ", \(subtitle)" }
        if let detail = action.detail   { accessibilityLabelText += ", \(detail)" }
        if let badge = action.badge    { accessibilityLabelText += ", badge \(badge)" }
        if action.submenu != nil        { accessibilityLabelText += ", more options" }
        accessibilityLabel = accessibilityLabelText
        accessibilityTraits = action.style == .disabled ? [.button, .notEnabled] : .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func configureConstraints() {
        let inset = Sumi.Spacing.l

        if rightSlotKind == .slider {
            configureSliderRowConstraints(inset: inset)
            return
        }

        let titleTrailing: NSLayoutXAxisAnchor
        let titleTrailingInset: CGFloat
        if rightSlotKind == .toggle {
            titleTrailing = switchView.leadingAnchor
            titleTrailingInset = Sumi.Spacing.s
        } else if iconView.image != nil {
            titleTrailing = iconView.leadingAnchor
            titleTrailingInset = Sumi.Spacing.s
        } else if !badgeView.isHidden {
            titleTrailing = badgeView.leadingAnchor
            titleTrailingInset = Sumi.Spacing.s
        } else if !detailLabel.isHidden {
            titleTrailing = detailLabel.leadingAnchor
            titleTrailingInset = Sumi.Spacing.s
        } else {
            titleTrailing = trailingAnchor
            titleTrailingInset = inset
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.topAnchor.constraint(
                equalTo: topAnchor,
                constant: (action.subtitle == nil) ? 0 : 8
            ).withPriority(.defaultHigh),
            titleLabel.bottomAnchor.constraint(
                equalTo: subtitleLabel.isHidden ? bottomAnchor : subtitleLabel.topAnchor,
                constant: subtitleLabel.isHidden ? 0 : -1
            ).withPriority(.defaultHigh),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor).withPriority(.defaultLow),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleTrailing, constant: -titleTrailingInset),

            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            subtitleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleTrailing, constant: -titleTrailingInset),

            iconView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(lessThanOrEqualToConstant: 22),

            badgeView.trailingAnchor.constraint(
                equalTo: iconView.image == nil ? trailingAnchor : iconView.leadingAnchor,
                constant: iconView.image == nil ? -inset : -Sumi.Spacing.s
            ),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),

            detailLabel.trailingAnchor.constraint(
                equalTo: badgeView.isHidden
                    ? (iconView.image == nil ? trailingAnchor : iconView.leadingAnchor)
                    : badgeView.leadingAnchor,
                constant: (badgeView.isHidden && iconView.image == nil) ? -inset : -Sumi.Spacing.s
            ),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            switchView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            switchView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    private func configureSliderRowConstraints(inset: CGFloat) {
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: sliderValueLabel.leadingAnchor, constant: -Sumi.Spacing.s),

            sliderValueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            sliderValueLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),

            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            slider.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            slider.heightAnchor.constraint(equalToConstant: 28),
            slider.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])
    }

    @objc private func sliderChanged() {
        guard let model = action.slider else { return }
        let value = Double(slider.value)
        sliderValueLabel.text = model.formatter(value)
        model.onChange(value)
    }

    fileprivate func flipToggle() {
        guard let toggle = action.toggle else { return }
        liveToggleIsOn.toggle()
        switchView.setOn(liveToggleIsOn, animated: true)
        toggle.onChange(liveToggleIsOn)
    }

    func setHighlighted(_ highlighted: Bool, animated: Bool) {
        guard highlighted != isCurrentlyHighlighted else { return }
        isCurrentlyHighlighted = highlighted

        let target: UIColor = highlighted ? UIColor(white: 0.5, alpha: 0.16) : .clear
        let updates = { self.backgroundColor = target }
        if animated {
            UIView.animate(withDuration: 0.18, animations: updates)
        } else {
            updates()
        }

        guard highlighted,
              action.animateIconOnHighlight,
              !UIAccessibility.isReduceMotionEnabled,
              action.style != .disabled,
              iconView.image != nil,
              rightSlotKind != .chevron
        else { return }
        if #available(iOS 17.0, *) {
            iconView.addSymbolEffect(.bounce.up, options: .nonRepeating)
        } else {
            bounceIconLegacy()
        }
    }

    /// iOS 13–16 fallback for the `.bounce.up` symbol effect (which is
    /// iOS 17+). A short pop-and-settle on the icon: it lifts a few
    /// points while scaling up, overshoots, then springs back to rest.
    ///
    /// Driven on the layer's `transform` so it never disturbs the row's
    /// Auto Layout, and every keyframe resolves back to identity so no
    /// permanent offset survives the animation. Reduce-motion is already
    /// honoured by the caller's guard before we get here.
    private func bounceIconLegacy() {
        func frame(_ translateY: CGFloat, _ scale: CGFloat) -> NSValue {
            var m = CATransform3DMakeTranslation(0, translateY, 0)
            m = CATransform3DScale(m, scale, scale, 1)
            return NSValue(caTransform3D: m)
        }
        let bounce = CAKeyframeAnimation(keyPath: "transform")
        bounce.values = [frame(0, 1), frame(-7, 1.14), frame(0, 1), frame(-2, 1.04), frame(0, 1)]
        bounce.keyTimes = [0, 0.28, 0.56, 0.78, 1]
        bounce.duration = 0.52
        bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconView.layer.add(bounce, forKey: "sumiIconBounce")
    }
}

// MARK: - Badge

@MainActor
final class BadgeView: UIView {
    private let label = UILabel()

    init() {
        super.init(frame: .zero)
        layer.cornerRadius = 8
        layer.cornerCurve = .continuous

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 18)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func configure(text: String, accent: UIColor) {
        label.text = text
        backgroundColor = accent
    }
}

// MARK: - Shadow wrapper (API compat for Menu / ContextMenu)

public final class MenuShadowWrapper: UIView {
    public let menu: MenuListView

    public init(menu: MenuListView) {
        self.menu = menu
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        // One unified soft shadow at the outer perimeter,
        // following the rounded corners of the menu card.
        layer.applySumiShadow(.elevated)
        addSubview(menu)
        NSLayoutConstraint.activate([
            menu.topAnchor.constraint(equalTo: topAnchor),
            menu.bottomAnchor.constraint(equalTo: bottomAnchor),
            menu.leadingAnchor.constraint(equalTo: leadingAnchor),
            menu.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let newPath = UIBezierPath(
            roundedRect: bounds,
            cornerRadius: Sumi.Radius.card
        ).cgPath

        // shadowPath isn't an automatically-animatable property
        // inside `UIView.animate` blocks. To make the shadow
        // track the bounds animation, we inspect whichever
        // bounds/position animation is currently in flight and
        // mirror its parameters onto a dedicated shadowPath
        // animation.
        //
        // When the bounds animation is a CASpringAnimation
        // (which is what `UIView.animate(usingSpringWithDamping:...)`
        // produces under the hood), we copy its damping / mass
        // / stiffness / initialVelocity so the shadow rides the
        // same spring. Earlier code only copied `duration` +
        // `timingFunction` onto a plain CABasicAnimation —
        // because spring duration is the SETTLING duration
        // (longer than the visible perceived duration), the
        // shadow stretched out behind the bounds, looking like
        // it was "lagging".
        let resizeAnim = layer.animation(forKey: "bounds.size")
            ?? layer.animation(forKey: "bounds")
            ?? layer.animation(forKey: "position")
        if let spring = resizeAnim as? CASpringAnimation {
            let pathAnim = CASpringAnimation(keyPath: "shadowPath")
            pathAnim.fromValue = layer.shadowPath ?? newPath
            pathAnim.toValue = newPath
            pathAnim.damping = spring.damping
            pathAnim.mass = spring.mass
            pathAnim.stiffness = spring.stiffness
            pathAnim.initialVelocity = spring.initialVelocity
            pathAnim.duration = spring.settlingDuration
            pathAnim.fillMode = .both
            layer.add(pathAnim, forKey: "shadowPath")
        } else if let anim = resizeAnim {
            let pathAnim = CABasicAnimation(keyPath: "shadowPath")
            pathAnim.fromValue = layer.shadowPath ?? newPath
            pathAnim.toValue = newPath
            pathAnim.duration = anim.duration
            pathAnim.timingFunction = anim.timingFunction
            pathAnim.fillMode = .both
            layer.add(pathAnim, forKey: "shadowPath")
        }
        layer.shadowPath = newPath
    }
}

// MARK: - Helpers

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
