//
//  NotchStatusGlyphView.swift
//  facekey
//
//  The mark beside the notch status text. Drawn as thin round-capped strokes
//  like the scan animation next to it, and animated per state: a turning arc
//  while working, a ring that closes into a check or a cross, a breathing
//  alert. With Reduce Motion on, each one is drawn at rest.
//

import SwiftUI

struct NotchStatusGlyphView: View {
    let glyph: NotchStatusGlyph
    let color: Color

    static let size: CGFloat = 14
    private static let lineWidth: CGFloat = 1.8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 → 1 drives the strokes that draw themselves in.
    @State private var progress: CGFloat = 0
    @State private var rotation: Double = 0
    @State private var breathing = false

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round)
    }

    var body: some View {
        ZStack {
            switch glyph {
            case .spinner:
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(color, style: stroke)
                    .rotationEffect(.degrees(rotation))
            case .check:
                ring
                CheckShape()
                    .trim(from: 0, to: markProgress)
                    .stroke(color, style: stroke)
            case .cross:
                ring
                CrossShape()
                    .trim(from: 0, to: markProgress)
                    .stroke(color, style: stroke)
            case .alert:
                Circle()
                    .stroke(color, style: stroke)
                AlertShape()
                    .stroke(color, style: stroke)
            }
        }
        .frame(width: Self.size, height: Self.size)
        .opacity(glyph == .alert && !reduceMotion ? (breathing ? 1 : 0.45) : 1)
        .fixedSize()
        .onAppear(perform: start)
    }

    /// The ring closes first, then the mark follows.
    private var ring: some View {
        Circle()
            .trim(from: 0, to: min(progress / 0.55, 1))
            .stroke(color, style: stroke)
            .rotationEffect(.degrees(-90))
    }

    private var markProgress: CGFloat {
        max(0, (progress - 0.5) / 0.5)
    }

    private func start() {
        if reduceMotion {
            progress = 1
            return
        }
        switch glyph {
        case .spinner:
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        case .check, .cross:
            withAnimation(.easeOut(duration: 0.55)) {
                progress = 1
            }
        case .alert:
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }
}

// MARK: - Marks

/// Shapes live in the 14 pt box the glyph is drawn in.
private struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.73, y: rect.minY + rect.height * 0.34))
        return path
    }
}

private struct CrossShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.minY + rect.height * 0.33))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.67, y: rect.minY + rect.height * 0.67))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.67, y: rect.minY + rect.height * 0.33))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.33, y: rect.minY + rect.height * 0.67))
        return path
    }
}

private struct AlertShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.midX
        path.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.27))
        path.addLine(to: CGPoint(x: x, y: rect.minY + rect.height * 0.55))
        path.move(to: CGPoint(x: x, y: rect.minY + rect.height * 0.73))
        path.addLine(to: CGPoint(x: x, y: rect.minY + rect.height * 0.74))
        return path
    }
}

#Preview {
    HStack(spacing: 20) {
        NotchStatusGlyphView(glyph: .spinner, color: FacekeyTheme.accent)
        NotchStatusGlyphView(glyph: .check, color: FacekeyTheme.accent)
        NotchStatusGlyphView(glyph: .cross, color: Color(red: 1.0, green: 0.35, blue: 0.37))
        NotchStatusGlyphView(glyph: .alert, color: Color(red: 245 / 255, green: 183 / 255, blue: 59 / 255))
    }
    .padding()
    .background(Color.black)
}
