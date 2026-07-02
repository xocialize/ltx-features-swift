// SheetComposer.swift — build an Ingredients reference sheet from subject images + an optional
// location shot (IC-LORA-PLAN P2b). INTENT-reimplementation of the layout popularized by
// gregowahoo/comfyui-ingredients-sheet-builder (no formal license — no code lifted): up to 6
// subject/prop panels at native aspect in a uniform top row, a full-width location band below,
// black gutters everywhere, no text on the final sheet. Composed OVERSIZED (default 1456×825)
// so identity detail survives the downscale to output resolution at ingest.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum SheetComposer {

    public struct Spec: Sendable, Equatable {
        public var width: Int
        public var height: Int
        /// Black separation between panels and around the sheet edge.
        public var gutter: Int
        /// Fraction of sheet height given to the location band (when a location is provided).
        public var locationHeightFraction: CGFloat
        public var maxSubjects: Int

        public init(width: Int = 1456, height: Int = 825, gutter: Int = 12,
                    locationHeightFraction: CGFloat = 0.4, maxSubjects: Int = 6) {
            self.width = width
            self.height = height
            self.gutter = gutter
            self.locationHeightFraction = locationHeightFraction
            self.maxSubjects = maxSubjects
        }
    }

    public enum ComposeError: Error, LocalizedError {
        case noInputs
        case tooManySubjects(Int, max: Int)
        case imageDecode(index: Int)

        public var errorDescription: String? {
            switch self {
            case .noInputs: return "Sheet needs at least one subject image or a location image."
            case .tooManySubjects(let n, let max): return "\(n) subject images exceeds the sheet's \(max)-panel limit."
            case .imageDecode(let i): return "Could not decode subject image at index \(i)."
            }
        }
    }

    /// Compose a sheet from decoded images. Subjects fill a uniform top row (aspect-fit inside
    /// each panel, centered, black elsewhere); the location fills a full-width bottom band
    /// (aspect-fit). No subjects → the location gets the whole sheet; no location → subjects do.
    public static func compose(subjects: [CGImage], location: CGImage?, spec: Spec = Spec()) throws -> CGImage {
        guard !subjects.isEmpty || location != nil else { throw ComposeError.noInputs }
        guard subjects.count <= spec.maxSubjects else {
            throw ComposeError.tooManySubjects(subjects.count, max: spec.maxSubjects)
        }
        let W = spec.width, H = spec.height, g = CGFloat(spec.gutter)
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.interpolationQuality = .high

        let bandH: CGFloat = location == nil ? 0
            : (subjects.isEmpty ? CGFloat(H) - 2 * g : (CGFloat(H) * spec.locationHeightFraction))

        if let location {
            let band = CGRect(x: g, y: g, width: CGFloat(W) - 2 * g, height: bandH - (subjects.isEmpty ? 0 : g))
            draw(location, fitIn: band, in: ctx)
        }
        if !subjects.isEmpty {
            let rowY = location == nil ? g : bandH + g
            let rowH = CGFloat(H) - rowY - g
            let n = CGFloat(subjects.count)
            let panelW = (CGFloat(W) - (n + 1) * g) / n
            for (i, img) in subjects.enumerated() {
                let panel = CGRect(x: g + CGFloat(i) * (panelW + g), y: rowY, width: panelW, height: rowH)
                draw(img, fitIn: panel, in: ctx)
            }
        }
        return ctx.makeImage()!
    }

    /// Convenience over encoded image data (PNG/JPEG/HEIC in, PNG out) — the shape
    /// `ConditioningAttachment.imageSet` carries.
    public static func compose(subjectData: [Data], locationData: Data?, spec: Spec = Spec()) throws -> Data {
        let subjects: [CGImage] = try subjectData.enumerated().map { i, d in
            guard let img = decode(d) else { throw ComposeError.imageDecode(index: i) }
            return img
        }
        let location = locationData.flatMap(decode)
        if locationData != nil && location == nil { throw ComposeError.imageDecode(index: -1) }
        let sheet = try compose(subjects: subjects, location: location, spec: spec)
        return try encodePNG(sheet)
    }

    // MARK: - helpers

    static func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func encodePNG(_ image: CGImage) throws -> Data {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else {
            throw ComposeError.imageDecode(index: -1)
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    /// Aspect-fit `image` centered inside `rect` (black shows through around it).
    private static func draw(_ image: CGImage, fitIn rect: CGRect, in ctx: CGContext) {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0, rect.width > 0, rect.height > 0 else { return }
        let scale = min(rect.width / iw, rect.height / ih)
        let w = iw * scale, h = ih * scale
        let target = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        ctx.draw(image, in: target)
    }
}
