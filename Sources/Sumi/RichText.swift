import UIKit

// Sumi.RichText — lightweight rich-text container used wherever
// alerts, dialogs, toasts, or any other text surface needs to
// accept either a plain string OR markdown-formatted text.
//
// Why not just always require `NSAttributedString`:
//
//   • 90% of call sites pass a string literal. Forcing them to
//     construct an attributed string each time pollutes call
//     sites and removes the chance for the design system to
//     own its typographic decisions (font weight, link colour,
//     code background).
//   • Markdown is portable across surfaces — the same
//     `.markdown("...")` value can render in an Alert or a
//     Dialog and pick up that surface's typographic context
//     (title vs body font size, primary vs subdued tint).
//
// Why not just `String` with a separate `isMarkdown: Bool`:
//
//   • Two parameters that must agree is a footgun. The enum
//     bakes the intent into the value itself, so a caller can
//     never accidentally pass `isMarkdown: true` with text
//     that has no markup, or vice versa.
//
// Supported markdown subset (deliberately minimal — full
// CommonMark is overkill for an alert message):
//
//   **bold**           — semibold weight
//   *italic*           — italic
//   `inline code`      — monospaced + tinted background
//   [text](url)        — accent colour + underline + tap target
//
// Nested combinations work for the common cases (bold+italic
// is the only one — write `***both***`, or use `**italic*` if
// you only need one level). Edge cases (nested code in bold,
// etc.) are not supported; if a caller needs that, they own an
// `NSAttributedString` directly.

public extension Sumi {

    /// String OR markdown. Use `.plain` for already-rendered
    /// text, `.markdown` to let the design system parse and
    /// style inline formatting.
    ///
    /// Conforms to `ExpressibleByStringLiteral` so existing
    /// call sites that pass a string literal compile without
    /// change — the literal is treated as `.plain`.
    enum RichText: Sendable, ExpressibleByStringLiteral {
        case plain(String)
        case markdown(String)

        public init(stringLiteral value: String) {
            self = .plain(value)
        }

        /// Underlying string with markdown markers intact (for
        /// VoiceOver, copying to clipboard, character counts,
        /// or any place where the rendered visual isn't what
        /// matters).
        public var raw: String {
            switch self {
            case .plain(let s), .markdown(let s): return s
            }
        }

        public var isEmpty: Bool { raw.isEmpty }
    }

    /// Visual context for rendering a `RichText` into an
    /// `NSAttributedString`. The base font + text colour come
    /// from the host surface (alert message style, dialog body
    /// style, toast body, etc.); the parser then applies its
    /// own font + colour deltas on top for **bold**, *italic*,
    /// `code`, and links.
    struct RichTextContext: Sendable {
        public let baseFont: UIFont
        public let textColor: UIColor
        public let accent: UIColor
        public let codeBackgroundColor: UIColor
        public let alignment: NSTextAlignment

        public init(
            baseFont: UIFont,
            textColor: UIColor,
            accent: UIColor,
            codeBackgroundColor: UIColor,
            alignment: NSTextAlignment = .center
        ) {
            self.baseFont = baseFont
            self.textColor = textColor
            self.accent = accent
            self.codeBackgroundColor = codeBackgroundColor
            self.alignment = alignment
        }

        /// Convenience using Sumi's standard tokens — call from
        /// any surface that doesn't care to customise.
        public static func bodyMessage(alignment: NSTextAlignment = .center) -> RichTextContext {
            RichTextContext(
                baseFont: Sumi.Font.body(),
                textColor: Sumi.Color.textSecondary,
                accent: Sumi.Color.accent,
                codeBackgroundColor: Sumi.Color.surfaceSubtle,
                alignment: alignment
            )
        }
    }

    /// Render a `RichText` into an `NSAttributedString` using
    /// the given context. Plain text values just get the
    /// context's base font + colour + alignment applied; markdown
    /// values get parsed.
    static func render(
        _ rich: RichText,
        context: RichTextContext
    ) -> NSAttributedString {
        switch rich {
        case .plain(let s):
            return basePlain(s, context: context)
        case .markdown(let s):
            return MarkdownRenderer.render(s, context: context)
        }
    }

    /// Base attributes (paragraph style + font + colour) applied
    /// to every rendered string regardless of markdown content.
    /// Exposed because the markdown renderer needs the same base
    /// to layer attributes on top of.
    internal static func basePlain(
        _ s: String,
        context: RichTextContext
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = context.alignment
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: s,
            attributes: [
                .font: context.baseFont,
                .foregroundColor: context.textColor,
                .paragraphStyle: paragraph
            ]
        )
    }
}

// MARK: - Markdown renderer
//
// Hand-rolled parser, not `NSAttributedString(markdown:)`:
//
//   • iOS 15's `AttributedString(markdown:)` produces a
//     foundation-level type that doesn't directly bridge to
//     `NSAttributedString` without conversion, and applying
//     custom fonts/colours (vs system defaults) requires post-
//     walking the result anyway.
//   • iOS 13/14 don't have it at all — we'd need a parallel
//     path. Since Sumi's floor is iOS 13, a single regex-based
//     renderer covering both is simpler than an availability
//     fork.
//   • Our markdown subset is intentionally narrow (4 styles).
//     Full CommonMark is hundreds of lines; ours is ~120.
//
// Algorithm: tokenise by walking the string with NSRegularExpression
// patterns ordered by precedence (code first — its content is
// literal and must not be parsed for nested bold/italic),
// then bold, italic, and links. Each match produces a token;
// non-matched ranges become plain tokens. A second pass renders
// tokens into an `NSMutableAttributedString` applying attribute
// deltas on top of the base context.

internal enum MarkdownRenderer {

    fileprivate enum Token {
        case plain(String)
        case code(String)         // `text`
        case bold(String)         // **text**
        case italic(String)       // *text*
        case link(text: String, url: URL)  // [text](url)
    }

    static func render(_ source: String, context: Sumi.RichTextContext) -> NSAttributedString {
        let tokens = tokenise(source)
        let result = NSMutableAttributedString()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = context.alignment
        paragraph.lineBreakMode = .byWordWrapping

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: context.baseFont,
            .foregroundColor: context.textColor,
            .paragraphStyle: paragraph
        ]

        for token in tokens {
            switch token {
            case .plain(let s):
                result.append(NSAttributedString(string: s, attributes: baseAttrs))

            case .code(let s):
                // Monospaced font + tinted background. We DON'T
                // surround with thin-space "padding" any more —
                // earlier versions used `\u{2009}` on each side
                // with the same background attribute, but the
                // bleed at line-wrap boundaries (kamiSubtle
                // background continues onto the next line where
                // a space wraps to the start) looked broken. With
                // a soft enough background colour the tight
                // edges read fine without internal padding.
                let mono = UIFont.monospacedSystemFont(
                    ofSize: context.baseFont.pointSize - 1,
                    weight: .regular
                )
                var attrs = baseAttrs
                attrs[.font] = mono
                attrs[.backgroundColor] = context.codeBackgroundColor
                attrs[.foregroundColor] = context.textColor
                result.append(NSAttributedString(string: s, attributes: attrs))

            case .bold(let s):
                var attrs = baseAttrs
                attrs[.font] = context.baseFont.withWeight(.semibold)
                result.append(NSAttributedString(string: s, attributes: attrs))

            case .italic(let s):
                var attrs = baseAttrs
                let italicDescriptor = context.baseFont.fontDescriptor
                    .withSymbolicTraits(.traitItalic) ?? context.baseFont.fontDescriptor
                attrs[.font] = UIFont(descriptor: italicDescriptor, size: context.baseFont.pointSize)
                result.append(NSAttributedString(string: s, attributes: attrs))

            case .link(let text, let url):
                // NB: we use the CUSTOM `.sumiLink` attribute key,
                // NOT `NSAttributedString.Key.link`. UIKit
                // intercepts the system `.link` key on UILabel
                // and re-paints it with `UIColor.link` (system
                // blue) regardless of our `.foregroundColor`. By
                // storing the URL under our own key, the system
                // restyle never fires and our accent vermillion
                // wins. `LinkAwareLabel` reads `.sumiLink` for
                // hit-testing.
                var attrs = baseAttrs
                attrs[.foregroundColor] = context.accent
                attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attrs[.underlineColor] = context.accent
                attrs[NSAttributedString.Key.sumiLink] = url
                result.append(NSAttributedString(string: text, attributes: attrs))
            }
        }
        return result
    }

    /// Tokenise the source string by greedy precedence-ordered
    /// matching: code → link → bold → italic. Once a match is
    /// consumed, the recogniser advances past it; the gaps
    /// become plain tokens.
    ///
    /// Doesn't handle escape sequences (`\*`, `\[`) — if a user
    /// needs a literal `*` they pass `.plain(...)` instead.
    fileprivate static func tokenise(_ source: String) -> [Token] {
        // Pattern order matters: code content is literal and
        // its delimiters wouldn't otherwise be ignored by the
        // bold/italic patterns. Link before bold so `[**text**](url)`
        // doesn't get half-consumed (we don't support nested
        // bold inside link in this v1).
        // Italic uses negative-lookaround so it can't latch onto
        // a `*` that belongs to an adjacent `**bold**`. Without
        // the guards, the italic regex (running independently
        // of bold) would consume the trailing `*` of a bold span
        // and stretch its match across surrounding plain text
        // — that breaks a later REAL italic by overlap.
        //
        //   Input: "version **2.0.4** but copy is *1.9.7*"
        //   Without lookarounds: italic matches "* but copy is *"
        //   (consuming the closing `*` of bold AND the opening
        //   `*` of *1.9.7*), so *1.9.7* never gets emphasised.
        //   With lookarounds: italic refuses any match where its
        //   opening `*` is preceded by `*` or its closing `*`
        //   is followed by `*`.
        //
        // Bold gets the same lookarounds for symmetry — handles
        // `***triple***` where you don't want italic-of-bold
        // glued to a third boundary `*`.
        let patterns: [(NSRegularExpression, (NSTextCheckingResult, String) -> Token?)] = [
            (try! NSRegularExpression(pattern: "`([^`\n]+)`"), { match, src in
                guard let body = substring(src, match.range(at: 1)) else { return nil }
                return .code(body)
            }),
            (try! NSRegularExpression(pattern: "\\[([^\\]\n]+)\\]\\(([^\\)\n]+)\\)"), { match, src in
                guard let text = substring(src, match.range(at: 1)),
                      let urlString = substring(src, match.range(at: 2)),
                      let url = URL(string: urlString) else { return nil }
                return .link(text: text, url: url)
            }),
            (try! NSRegularExpression(pattern: "(?<!\\*)\\*\\*([^*\n]+)\\*\\*(?!\\*)"), { match, src in
                guard let body = substring(src, match.range(at: 1)) else { return nil }
                return .bold(body)
            }),
            (try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*\n]+)\\*(?!\\*)"), { match, src in
                guard let body = substring(src, match.range(at: 1)) else { return nil }
                return .italic(body)
            })
        ]

        // Find ALL matches across all patterns, then sort by
        // start offset. Overlapping matches keep the earliest;
        // we walk the string once and emit tokens.
        struct Hit {
            let range: NSRange
            let token: Token
        }
        var hits: [Hit] = []
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        for (regex, transform) in patterns {
            regex.enumerateMatches(in: source, range: fullRange) { match, _, _ in
                guard let match,
                      let token = transform(match, source) else { return }
                hits.append(Hit(range: match.range, token: token))
            }
        }

        // Sort + resolve overlaps (earlier match wins; if same
        // start, longer wins which gives bold precedence over
        // italic when text is `**foo**`).
        hits.sort { lhs, rhs in
            if lhs.range.location != rhs.range.location {
                return lhs.range.location < rhs.range.location
            }
            return lhs.range.length > rhs.range.length
        }

        var output: [Token] = []
        var cursor = 0
        for hit in hits {
            if hit.range.location < cursor { continue }  // overlap with prior
            if hit.range.location > cursor {
                let gap = NSRange(location: cursor, length: hit.range.location - cursor)
                output.append(.plain(nsSource.substring(with: gap)))
            }
            output.append(hit.token)
            cursor = hit.range.location + hit.range.length
        }
        if cursor < nsSource.length {
            let tail = NSRange(location: cursor, length: nsSource.length - cursor)
            output.append(.plain(nsSource.substring(with: tail)))
        }
        return output
    }

    private static func substring(_ source: String, _ range: NSRange) -> String? {
        guard range.location != NSNotFound else { return nil }
        return (source as NSString).substring(with: range)
    }
}

// `UIFont.withWeight(_:)` lives in Sumi.swift — used by both
// Sumi.Font factories and the markdown renderer below.

// MARK: - Custom attribute key
//
// We attach link URLs under our own `.sumiLink` key rather
// than `NSAttributedString.Key.link`. Reason: UIKit's UILabel
// (iOS 15+) detects `.link` and re-tints the text with
// `UIColor.link` (system blue) regardless of the
// `.foregroundColor` we set. The override is undocumented and
// runs after our attributed string is installed; trying to
// fight it by setting `tintColor` or `tintAdjustmentMode` is
// fragile across iOS versions.
//
// By using a custom key, the system never sees a "link" and
// our accent vermillion + underline remain authoritative.
// `LinkAwareLabel` hit-tests against `.sumiLink` for tap
// routing.

public extension NSAttributedString.Key {
    /// Internal Sumi-only link marker — see RichText.swift for
    /// rationale. Exposed `public` so external consumers (e.g.
    /// a host app) can also detect link attributes in
    /// strings produced by `Sumi.render(_:context:)`.
    static let sumiLink = NSAttributedString.Key("SumiLink")
}
