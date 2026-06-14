import UIKit

// MARK: - FocusTraceBorder
//
// Expert / experimental focus affordance for dialog text fields.
//
// Instead of the accent outline snapping in instantly, the stroke
// is *drawn*: it springs from the TOP-CENTRE of the field and
// sweeps down BOTH sides simultaneously, the two ends meeting and
// sealing at the BOTTOM-CENTRE — like field lines wrapping a magnet.
//
// How the symmetry is guaranteed (and why it's one layer, not two):
//
//   • The border path is a closed rounded rect built starting at
//     the bottom-centre, traversed all the way around back to the
//     bottom-centre. Because the path is mirror-symmetric across the
//     vertical axis, its arc-length MIDPOINT (parametric 0.5) lands
//     EXACTLY on the top-centre — for any width/height/​radius.
//   • So we animate a single CAShapeLayer's `strokeStart` 0.5 → 0
//     and `strokeEnd` 0.5 → 1 together. The visible segment grows
//     out from parametric 0.5 (top-centre) in both directions and
//     the two ends converge on parametric 0/1 (bottom-centre). One
//     continuous path means the ends meet pixel-perfectly.
//
// On blur the stroke fades out quickly (kept snappy so tabbing
// between fields reads as "this one lit, that one dimmed", not a
// slow ceremony).

@MainActor
final class FocusTraceBorder {

    let shape = CAShapeLayer()

    private let cornerRadius: CGFloat
    private let lineWidth: CGFloat

    init(cornerRadius: CGFloat, lineWidth: CGFloat = 2, color: UIColor) {
        self.cornerRadius = cornerRadius
        self.lineWidth = lineWidth
        shape.fillColor = UIColor.clear.cgColor
        shape.strokeColor = color.cgColor
        shape.lineWidth = lineWidth
        shape.lineCap = .round
        shape.lineJoin = .round
        // Start fully hidden + collapsed at the spawn point so the
        // very first `animateIn` has a clean origin.
        shape.opacity = 0
        shape.strokeStart = 0.5
        shape.strokeEnd = 0.5
    }

    /// Add the stroke layer above the host's own background.
    func install(in host: UIView) {
        host.layer.addSublayer(shape)
    }

    func setColor(_ color: UIColor) {
        shape.strokeColor = color.cgColor
    }

    /// Rebuild the path for the host's current bounds. Call from the
    /// host's `layoutSubviews` so the trace tracks resizes. Implicit
    /// layer animations are suppressed — a path change mid-resize
    /// shouldn't crossfade.
    func updatePath(for bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds
        shape.path = Self.tracePath(
            in: bounds,
            cornerRadius: cornerRadius,
            lineWidth: lineWidth
        ).cgPath
        CATransaction.commit()
    }

    /// Play the draw-in. `reduceMotion` snaps straight to the full
    /// outline (respecting the accessibility setting).
    func animateIn(reduceMotion: Bool) {
        shape.removeAllAnimations()
        shape.opacity = 1
        // Model = final state, so the border persists after the
        // animation resolves.
        shape.strokeStart = 0
        shape.strokeEnd = 1

        guard !reduceMotion else { return }

        let start = CABasicAnimation(keyPath: "strokeStart")
        start.fromValue = 0.5
        start.toValue = 0
        let end = CABasicAnimation(keyPath: "strokeEnd")
        end.fromValue = 0.5
        end.toValue = 1

        let group = CAAnimationGroup()
        group.animations = [start, end]
        group.duration = 0.42
        // Decisive ease-out — quick off the mark, gentle landing.
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        shape.add(group, forKey: "trace-in")
    }

    /// Fade the outline away on blur. Resets the collapsed origin so
    /// the next focus draws fresh from the top-centre.
    func animateOut(reduceMotion: Bool) {
        shape.removeAllAnimations()

        guard !reduceMotion else {
            shape.opacity = 0
            shape.strokeStart = 0.5
            shape.strokeEnd = 0.5
            return
        }

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = shape.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.20
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        shape.opacity = 0
        shape.add(fade, forKey: "trace-out")

        // Reset the spawn geometry once the fade can't be seen.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.strokeStart = 0.5
        shape.strokeEnd = 0.5
        CATransaction.commit()
    }

    // MARK: Path

    /// Closed rounded-rect outline that STARTS and ENDS at the
    /// bottom-centre, traversed once around. Mirror-symmetric across
    /// the vertical axis ⇒ parametric 0.5 == top-centre. Corners use
    /// quadratic curves with the true corner as control point; the
    /// symmetry (and therefore the 0.5-is-top-centre guarantee) holds
    /// regardless of the corner approximation.
    private static func tracePath(
        in bounds: CGRect,
        cornerRadius: CGFloat,
        lineWidth: CGFloat
    ) -> UIBezierPath {
        // Inset by half the stroke so the 2pt line sits just inside
        // the fill edge — matches the old inward `layer.borderWidth`.
        let inset = lineWidth / 2
        let r = bounds.insetBy(dx: inset, dy: inset)
        let rad = max(0, min(cornerRadius - inset, min(r.width, r.height) / 2))

        let minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        let midX = r.midX

        let p = UIBezierPath()
        p.move(to: CGPoint(x: midX, y: maxY))                                   // bottom-centre (start)
        p.addLine(to: CGPoint(x: maxX - rad, y: maxY))
        p.addQuadCurve(to: CGPoint(x: maxX, y: maxY - rad),
                       controlPoint: CGPoint(x: maxX, y: maxY))                 // bottom-right
        p.addLine(to: CGPoint(x: maxX, y: minY + rad))
        p.addQuadCurve(to: CGPoint(x: maxX - rad, y: minY),
                       controlPoint: CGPoint(x: maxX, y: minY))                 // top-right
        p.addLine(to: CGPoint(x: minX + rad, y: minY))                         // top edge — crosses top-centre
        p.addQuadCurve(to: CGPoint(x: minX, y: minY + rad),
                       controlPoint: CGPoint(x: minX, y: minY))                 // top-left
        p.addLine(to: CGPoint(x: minX, y: maxY - rad))
        p.addQuadCurve(to: CGPoint(x: minX + rad, y: maxY),
                       controlPoint: CGPoint(x: minX, y: maxY))                 // bottom-left
        p.close()                                                               // → back to bottom-centre
        return p
    }
}
