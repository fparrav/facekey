//
//  FacekeyMark.swift
//  facekey
//
//  The vector brand mark: a head and shoulders inside a rounded corner frame,
//  drawn without image assets and tinted with whatever colour is passed in
//  (the accent by default, per the identity design's decision 4).
//

import SwiftUI

/// Facekey's brand mark, `size` points square. Everything (frame stroke, head)
/// is a vector that scales with the size; heavier weights and a larger head at
/// the small sizes so the mark holds its shape at 20–32 pt.
struct FacekeyMark: View {
    var size: CGFloat
    var color: Color = FacekeyTheme.accent

    var body: some View {
        FacekeyMarkShape(stroke: strokeUnits, headRadius: headRadiusUnits)
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// Corner-frame stroke, in viewBox-200 units.
    private var strokeUnits: CGFloat {
        size <= 32 ? 16 : (size <= 64 ? 12 : 10)
    }
    /// Head radius, in viewBox-200 units.
    private var headRadiusUnits: CGFloat {
        size <= 32 ? 18 : 15
    }
}

/// The mark on an accent tile, as the app icon looks but following the chosen accent:
/// About and the first onboarding step show this instead of an image.
struct FacekeyLogoTile: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 45 / 200, style: .continuous)
                .fill(FacekeyTheme.accent)
            FacekeyMark(size: size * 0.7, color: FacekeyTheme.onAccent)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One path holding the whole mark: the corner frame (stroked, then outlined so
/// the single fill covers it) plus the filled head and shoulders.
///
/// Drawn in a 120 x 120 design space — the viewBox-200 art cropped to its
/// 40,40,120,120 box so the mark fills the frame — and mapped to the rect by
/// `path(in:)`.
private struct FacekeyMarkShape: Shape {
    var stroke: CGFloat
    var headRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let scale = rect.width / 120

        let frame = FacekeyMarkShape.cornerFrame()
            .strokedPath(StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))

        let figure = FacekeyMarkShape.figure(headRadius: headRadius)

        let toRect = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))

        var path = Path()
        path.addPath(frame, transform: toRect)
        path.addPath(figure, transform: toRect)
        return path
    }

    /// The four rounded corners. Each is a line, a 90° arc of radius 6, and a
    /// line, matching the SVG source `M56 78V62a6 6 0 016-6h16 M122 56h16a6
    /// 6 0 016 6v16 M144 122v16a6 6 0 01-6 6h-16 M78 144H62a6 6 0 01-6-6v-16`
    /// with the box origin (40,40) subtracted.
    private static func cornerFrame() -> Path {
        var path = Path()

        // Top left: up, arc, right.
        path.move(to: CGPoint(x: 16, y: 38))
        path.addLine(to: CGPoint(x: 16, y: 22))
        path.addArc(center: CGPoint(x: 22, y: 22), radius: 6,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.addLine(to: CGPoint(x: 38, y: 16))

        // Top right: right, arc, down.
        path.move(to: CGPoint(x: 82, y: 16))
        path.addLine(to: CGPoint(x: 98, y: 16))
        path.addArc(center: CGPoint(x: 98, y: 22), radius: 6,
                     startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        path.addLine(to: CGPoint(x: 104, y: 38))

        // Bottom right: down, arc, left.
        path.move(to: CGPoint(x: 104, y: 82))
        path.addLine(to: CGPoint(x: 104, y: 98))
        path.addArc(center: CGPoint(x: 98, y: 98), radius: 6,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: 82, y: 104))

        // Bottom left: left, arc, up.
        path.move(to: CGPoint(x: 38, y: 104))
        path.addLine(to: CGPoint(x: 22, y: 104))
        path.addArc(center: CGPoint(x: 22, y: 98), radius: 6,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: 16, y: 82))

        return path
    }

    /// Head (circle centred at (60,46) with the variant radius) and shoulders
    /// (the closed polygon from the SVG source), in design space.
    private static func figure(headRadius r: CGFloat) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 60 - r, y: 46 - r, width: 2 * r, height: 2 * r))

        path.move(to: CGPoint(x: 53, y: 62))
        path.addLine(to: CGPoint(x: 67, y: 62))
        path.addLine(to: CGPoint(x: 73, y: 96))
        path.addLine(to: CGPoint(x: 47, y: 96))
        path.closeSubpath()

        return path
    }
}

#Preview {
    HStack(spacing: 24) {
        FacekeyMark(size: 20)
        FacekeyMark(size: 32)
        FacekeyMark(size: 64)
        FacekeyMark(size: 128)
    }
}
