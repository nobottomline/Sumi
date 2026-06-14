import UIKit

// LinkAwareLabel — UILabel subclass that detects taps on
// `.link`-attributed ranges in its `attributedText` and fires
// `onLinkTap(URL)`.
//
// Why a UILabel subclass and not UITextView:
//
//   • UITextView has built-in link tappability but drags along
//     scrolling, selection, and a bunch of inherent padding
//     (textContainerInset, lineFragmentPadding) we'd have to
//     zero out everywhere.
//   • UITextView refuses to participate in UILabel's natural
//     layout (sizeToFit, intrinsicContentSize) — alerts and
//     dialogs that measure message height by sizing the label
//     would need a parallel measurement path.
//   • Hit-testing attributed ranges via TextKit is ~30 lines
//     of code, and gives us precise per-character control
//     (highlight on tap, ignore non-link taps).
//
// Behavior:
//
//   • Falls through to base UILabel behaviour when no `.link`
//     attribute exists at the tap point.
//   • Provides a brief visual press feedback on the tapped
//     link range (background highlight) before firing the
//     handler.

@MainActor
public final class LinkAwareLabel: UILabel {

    public var onLinkTap: ((URL) -> Void)?

    public override var attributedText: NSAttributedString? {
        didSet {
            // Track whether there are any link ranges so we
            // can skip hit-testing entirely on plain-text
            // labels (which is the common case).
            hasAnyLinks = (attributedText?.containsLink ?? false)
            isUserInteractionEnabled = hasAnyLinks
        }
    }

    private var hasAnyLinks: Bool = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func commonInit() {
        // The tap recogniser is always attached — we just
        // toggle `isUserInteractionEnabled` based on whether
        // the current text actually contains links.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    @objc private func handleTap(_ recogniser: UITapGestureRecognizer) {
        guard hasAnyLinks else { return }
        let location = recogniser.location(in: self)
        guard let url = url(at: location) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onLinkTap?(url)
    }

    /// Hit-test the tap location against the laid-out attributed
    /// text. Uses a one-shot TextKit pipeline (NSLayoutManager +
    /// NSTextStorage + NSTextContainer) configured to match the
    /// label's current bounds + line break mode + wrapping.
    ///
    /// Important: TextKit's coordinate system is its own —
    /// the bounding rect produced by `boundingRect(forGlyphRange:)`
    /// is relative to the text container's origin, which for a
    /// UILabel with content alignment is offset from the
    /// label's bounds. We compute that offset and translate the
    /// tap location into text-space before glyph hit-testing.
    private func url(at point: CGPoint) -> URL? {
        guard let attributedText, attributedText.length > 0 else { return nil }

        let textStorage = NSTextStorage(attributedString: attributedText)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: bounds.size)
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = numberOfLines
        textContainer.lineBreakMode = lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        // Vertical offset: when text is shorter than the label
        // (typical for short message lines), UILabel centres
        // content vertically — TextKit always lays out from
        // the top. Compute that delta and translate the tap.
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let textBoundingRect = layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        )
        let yOffset = (bounds.height - textBoundingRect.height) * 0.5
        let textSpacePoint = CGPoint(x: point.x, y: point.y - max(0, yOffset))

        let glyphIndex = layoutManager.glyphIndex(
            for: textSpacePoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < attributedText.length else { return nil }

        // Re-check that the glyph at this index is actually
        // hit (not just the nearest glyph beyond text end).
        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.contains(textSpacePoint) else { return nil }

        let attrs = attributedText.attributes(at: charIndex, effectiveRange: nil)
        // Read our custom Sumi link key — never `.link`. See
        // `RichText.swift` for the rationale (UIKit re-tints
        // anything attributed with the system `.link` key).
        return attrs[NSAttributedString.Key.sumiLink] as? URL
    }
}

private extension NSAttributedString {
    var containsLink: Bool {
        var found = false
        enumerateAttribute(
            NSAttributedString.Key.sumiLink,
            in: NSRange(location: 0, length: length)
        ) { value, _, stop in
            if value != nil {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
