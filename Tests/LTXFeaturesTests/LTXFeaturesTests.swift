import CoreGraphics
import XCTest
@testable import LTXFeatureCore
@testable import LTXIngredients

final class LTXFeaturesTests: XCTestCase {

    // MARK: - Registry v2 decode

    func testBundledRegistryDecodesV2() throws {
        let reg = try AdapterRegistry.bundled()
        XCTAssertEqual(reg.schemaVersion, 2)
        XCTAssertEqual(reg.adapters.count, 7)
        // Plain entry: v2 fields defaulted.
        let plain = try XCTUnwrap(reg.entry(id: "transition"))
        XCTAssertEqual(plain.effectiveKind, .plain)
        XCTAssertFalse(plain.isLicenseGated)
        // IC entry with grouped one-of slots.
        let ing = try XCTUnwrap(reg.entry(id: "ingredients"))
        XCTAssertEqual(ing.effectiveKind, .ic)
        XCTAssertEqual(ing.slots.count, 3)
        XCTAssertEqual(ing.slotGroups.count, 1)
        XCTAssertEqual(ing.slotGroups[0].key, "sheet")
        let imageSet = try XCTUnwrap(ing.slots.first { $0.media == .imageSet })
        XCTAssertEqual(imageSet.maxCount, 6)
        // License gating.
        let cam = try XCTUnwrap(reg.entry(id: "cameraman-v2"))
        XCTAssertTrue(cam.isLicenseGated)
        XCTAssertFalse(reg.surfaced().contains { $0.id == "cameraman-v2" })
        XCTAssertTrue(reg.surfaced(includeGated: true).contains { $0.id == "cameraman-v2" })
    }

    // MARK: - Intent validation

    func testValidationRequiresOneOfGroup() throws {
        let reg = try AdapterRegistry.bundled()
        let ing = try XCTUnwrap(reg.entry(id: "ingredients"))
        // Nothing supplied → the "sheet" group (named in conditioningGroups) is required.
        XCTAssertThrowsError(try IntentValidation.validate(GenerationIntent(prompt: "x"), against: ing))
        // A finished sheet satisfies the group.
        let withSheet = GenerationIntent(prompt: "x", attachments: [
            ConditioningAttachment(role: "reference_sheet", payload: .image(Data([1]))),
        ])
        XCTAssertNoThrow(try IntentValidation.validate(withSheet, against: ing))
        // Subject images satisfy it too (the builder path).
        let withSubjects = GenerationIntent(prompt: "x", attachments: [
            ConditioningAttachment(role: "subject_images",
                                   payload: .imageSet([Data([1])], descriptions: [nil])),
        ])
        XCTAssertNoThrow(try IntentValidation.validate(withSubjects, against: ing))
    }

    func testValidationRequiresLipdubReferenceVideo() throws {
        let reg = try AdapterRegistry.bundled()
        let lipdub = try XCTUnwrap(reg.entry(id: "lipdub"))
        XCTAssertThrowsError(try IntentValidation.validate(GenerationIntent(prompt: "x"), against: lipdub))
        let ok = GenerationIntent(prompt: "x", attachments: [
            ConditioningAttachment(role: "reference_video", payload: .video(URL(fileURLWithPath: "/tmp/v.mp4"))),
        ])
        XCTAssertNoThrow(try IntentValidation.validate(ok, against: lipdub))
    }

    // MARK: - Sheet composer (P2b)

    private func solidImage(w: Int, h: Int, r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Draw so that (x, y) lands at the single pixel (CG origin bottom-left).
        ctx.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(image.height - 1 - y),
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: 4)
        return (p[0], p[1], p[2])
    }

    func testSheetComposerGeometry() throws {
        let spec = SheetComposer.Spec()
        let subjects = [
            solidImage(w: 400, h: 400, r: 1, g: 0, b: 0),
            solidImage(w: 300, h: 600, r: 0, g: 1, b: 0),
            solidImage(w: 640, h: 360, r: 0, g: 0, b: 1),
        ]
        let location = solidImage(w: 1920, h: 1080, r: 1, g: 1, b: 0)
        let sheet = try SheetComposer.compose(subjects: subjects, location: location, spec: spec)
        XCTAssertEqual(sheet.width, 1456)
        XCTAssertEqual(sheet.height, 825)
        // Gutters are black: sheet edge + the seam between band and row.
        let edge = pixel(sheet, x: 2, y: 2)
        XCTAssertEqual(edge.r, 0); XCTAssertEqual(edge.g, 0); XCTAssertEqual(edge.b, 0)
        // Location band content (bottom 40%): yellow shows near the band center.
        let band = pixel(sheet, x: 728, y: 825 - 165)   // mid-band (CG y-up: bottom region)
        XCTAssertGreaterThan(band.r, 200); XCTAssertGreaterThan(band.g, 200); XCTAssertLessThan(band.b, 50)
        // First subject panel (top row, left) shows red at its center.
        let rowY = Int(825.0 * 0.4) + 12
        let rowH = 825 - rowY - 12
        let panelW = (1456 - 4 * 12) / 3
        let p1 = pixel(sheet, x: 12 + panelW / 2, y: 825 - (rowY + rowH / 2))
        XCTAssertGreaterThan(p1.r, 200); XCTAssertLessThan(p1.g, 50); XCTAssertLessThan(p1.b, 50)
    }

    func testSheetComposerLimitsAndEmpty() {
        XCTAssertThrowsError(try SheetComposer.compose(subjects: [], location: nil))
        let seven = (0 ..< 7).map { _ in solidImage(w: 10, h: 10, r: 1, g: 1, b: 1) }
        XCTAssertThrowsError(try SheetComposer.compose(subjects: seven, location: nil))
    }

    func testSheetComposerDataRoundTrip() throws {
        let img = solidImage(w: 100, h: 100, r: 1, g: 0, b: 0)
        let png = try SheetComposer.encodePNG(img)
        let out = try SheetComposer.compose(subjectData: [png], locationData: nil)
        XCTAssertFalse(out.isEmpty)
        let decoded = try XCTUnwrap(SheetComposer.decode(out))
        XCTAssertEqual(decoded.width, 1456)
    }

    // MARK: - Ingredients prompt convention (exact community-Space format)

    func testIngredientsDualPartPromptMatchesReferenceUsage() {
        let prompt = IngredientsPrompt.assemble(
            panelDescriptions: ["a knight in silver armor", nil, "an ancient oak staff"],
            locationDescription: "a foggy castle courtyard",
            actionBrief: "the knight raises the staff as dawn breaks")
        // build_prompt format from ltx-community/ltx-2.3-ingredients-distilled: no panel labels,
        // semicolon-joined elements, blank-line separator.
        XCTAssertEqual(prompt,
            "Reference sheet: a knight in silver armor; an ancient oak staff; a foggy castle courtyard"
            + "\n\nGenerated video: the knight raises the staff as dawn breaks")
    }

    func testIngredientsPromptWithoutDescriptions() {
        let prompt = IngredientsPrompt.assemble(panelDescriptions: [nil, nil],
                                                locationDescription: nil,
                                                actionBrief: "a fox runs")
        XCTAssertEqual(prompt, "Generated video: a fox runs")
    }

    // MARK: - Grid composer (community-reference layout)

    func testGridComposerLayout() throws {
        let imgs = (0 ..< 5).map { i in
            solidImage(w: 200, h: 200, r: i == 0 ? 1 : 0, g: i == 0 ? 0 : 1, b: 0)
        }
        let sheet = try SheetComposer.composeGrid(images: imgs)
        XCTAssertEqual(sheet.width, 1456)
        XCTAssertEqual(sheet.height, 825)
        // 5 images → 3 cols × 2 rows; first cell (top-left) shows red at its center.
        let cw = (1456.0 - 12.0 * 4) / 3, ch = (825.0 - 12.0 * 3) / 2
        let p = pixel(sheet, x: Int(12 + cw / 2), y: Int(12 + ch / 2))
        XCTAssertGreaterThan(p.r, 200); XCTAssertLessThan(p.g, 50)
        // Gutter stays black.
        let gutter = pixel(sheet, x: 3, y: 3)
        XCTAssertEqual(gutter.r, 0); XCTAssertEqual(gutter.g, 0)
    }

    func testGridComposerSingleImagePassthrough() throws {
        let img = solidImage(w: 123, h: 77, r: 1, g: 1, b: 1)
        let out = try SheetComposer.composeGrid(images: [img])
        XCTAssertEqual(out.width, 123)
        XCTAssertEqual(out.height, 77)
    }
}
