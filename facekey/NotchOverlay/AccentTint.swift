//
//  AccentTint.swift
//  facekey
//
//  The bundled scan animations are drawn in one blue on black, so they cannot
//  follow the accent colour as shipped. Their brightness is the blue channel,
//  which makes recolouring a matter of multiplying the accent by it: black
//  stays black, full blue becomes the accent, and the anti-aliased edges keep
//  their falloff.
//

import AVFoundation
import AppKit
import CoreImage

enum AccentTint {
    /// The accent as linear light, because Core Image works in a linear space:
    /// `blue * linear(accent)` converted back for display equals `blue * accent`
    /// in sRGB, so the edges blend the way the artwork was drawn.
    private struct Components: Sendable {
        let r: CGFloat
        let g: CGFloat
        let b: CGFloat
    }

    private static func current() -> Components {
        let rgb = AccentPalette.accent(FacekeySettings.shared.accentChoice)
        return Components(r: linear(rgb.r), g: linear(rgb.g), b: linear(rgb.b))
    }

    private static func linear(_ value: Double) -> CGFloat {
        let v = value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        return CGFloat(v)
    }

    private nonisolated static func recolour(_ image: CIImage, with c: Components) -> CIImage {
        guard let filter = CIFilter(name: "CIColorMatrix") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 0, y: 0, z: c.r, w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: 0, y: 0, z: c.g, w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: 0, y: 0, z: c.b, w: 0), forKey: "inputBVector")
        filter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        return filter.outputImage ?? image
    }

    /// A composition that recolours every frame of `asset` with the accent
    /// chosen right now. Build a new one each time a video starts, so a change
    /// of accent shows on the next play.
    static func composition(for asset: AVAsset) -> AVVideoComposition {
        let components = current()
        return AVMutableVideoComposition(asset: asset) { @Sendable request in
            let source = request.sourceImage
            let tinted = recolour(source, with: components).cropped(to: source.extent)
            request.finish(with: tinted, context: nil)
        }
    }

    /// `image` recoloured with the accent chosen right now; the image itself
    /// if it cannot be processed.
    static func tinted(_ image: NSImage) -> NSImage {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return image }
        let source = CIImage(cgImage: cgImage)
        let output = recolour(source, with: current()).cropped(to: source.extent)
        guard let result = CIContext().createCGImage(
            output,
            from: output.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else { return image }
        return NSImage(cgImage: result, size: image.size)
    }
}
