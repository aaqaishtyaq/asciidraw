import AsciiDrawCore
import CoreGraphics
import Foundation
import ImageIO
import XCTest

final class BehaviorTests: XCTestCase {
    func testProductVersionIsSemantic() {
        XCTAssertTrue(ProductVersion.isSemantic)
        XCTAssertEqual(ProductVersion.semantic, "1.0.0")
        XCTAssertEqual(ProductVersion.author, "Aaqa Ishtyaq")
        XCTAssertEqual(ProductVersion.github.host, "github.com")
    }

    func testRectangleSingleAndDoubleBorders() {
        var single = Editor()
        _ = single.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: .single, fill: nil, shadow: nil)
        XCTAssertEqual(single.render().plainText, ["┌──┐", "│  │", "└──┘"].joined(separator: "\n"))

        var double = Editor()
        _ = double.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: .double, fill: nil, shadow: nil)
        XCTAssertEqual(double.render().plainText, ["╔══╗", "║  ║", "╚══╝"].joined(separator: "\n"))
        XCTAssertNotEqual(single.render().plainText, double.render().plainText)
    }

    func testRectangleFill() {
        var editor = Editor()
        _ = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 6, height: 5), border: .single, fill: ".", shadow: nil)
        XCTAssertEqual(
            editor.render().plainText,
            ["┌────┐", "│....│", "│....│", "│....│", "└────┘"].joined(separator: "\n")
        )
    }

    func testRectangleShadowOffsetAndCharacter() {
        var editor = Editor()
        _ = editor.addRectangle(
            frame: GridRect(x: 0, y: 0, width: 4, height: 3),
            border: .single,
            fill: nil,
            shadow: ShadowStyle(character: "#", dx: 1, dy: 1)
        )
        let grid = editor.render()
        expect(grid, 0, 0, "┌")
        expect(grid, 1, 1, " ")
        expect(grid, 3, 1, "│")
        expect(grid, 4, 1, "#")
        expect(grid, 4, 2, "#")
        expect(grid, 4, 3, "#")
        expect(grid, 1, 3, "#")
        expect(grid, 2, 3, "#")
        expect(grid, 3, 3, "#")
    }

    func testDiamondOutline() {
        var editor = Editor()
        _ = editor.addDiamond(frame: GridRect(x: 0, y: 0, width: 5, height: 5))
        let grid = editor.render()
        XCTAssertEqual(
            grid.plainText,
            ["  +  ", " / \\ ", "+   +", " \\ / ", "  +  "].joined(separator: "\n")
        )
        expect(grid, 2, 0, "+")
        expect(grid, 1, 1, "/")
        expect(grid, 3, 1, "\\")
        expect(grid, 0, 2, "+")
        expect(grid, 4, 2, "+")
    }

    func testTextAlignmentPositionSweepAndLineMovement() {
        var editor = Editor()
        let left = editor.addText(frame: GridRect(x: 0, y: 0, width: 6, height: 1), text: "ab", style: plain("ab"))
        expect(editor.render(), 0, 0, "a")
        expect(editor.render(), 1, 0, "b")

        editor.setText(left) { $0.alignment = .center }
        expect(editor.render(), 2, 0, "a")
        expect(editor.render(), 0, 0, " ")

        editor.setText(left) { $0.alignment = .right }
        expect(editor.render(), 4, 0, "a")
        expect(editor.render(), 5, 0, "b")

        let vertical = editor.addText(frame: GridRect(x: 10, y: 0, width: 1, height: 5), text: "A", style: plain("A"))
        expect(editor.render(), 10, 0, "A")
        editor.setText(vertical) { $0.position = .middle }
        expect(editor.render(), 10, 2, "A")
        expect(editor.render(), 10, 0, " ")
        editor.setText(vertical) { $0.position = .bottom }
        expect(editor.render(), 10, 4, "A")

        let swept = editor.addText(frame: GridRect(x: 0, y: 8, width: 4, height: 4), text: "A\nB", style: plain("A\nB"))
        expect(editor.render(), 0, 8, "A")
        expect(editor.render(), 0, 9, "B")
        editor.setText(swept) { $0.sweep = .up }
        expect(editor.render(), 0, 8, "B")
        expect(editor.render(), 0, 9, "A")

        let columns = editor.addText(frame: GridRect(x: 8, y: 8, width: 4, height: 4), text: "AB\nCD", style: plain("AB\nCD"))
        editor.setText(columns) { $0.sweep = .right }
        expect(editor.render(), 8, 8, "A")
        expect(editor.render(), 9, 8, "C")
        expect(editor.render(), 8, 9, "B")
        expect(editor.render(), 9, 9, "D")
        editor.setText(columns) { $0.sweep = .left }
        expect(editor.render(), 8, 8, "C")
        expect(editor.render(), 9, 8, "A")
        expect(editor.render(), 8, 9, "D")
        expect(editor.render(), 9, 9, "B")

        let anchored = editor.addText(frame: GridRect(x: 20, y: 0, width: 6, height: 4), text: "Hi", style: plain("Hi", movement: .right))
        expect(editor.render(), 24, 0, "H")
        expect(editor.render(), 25, 0, "i")
        editor.setFrame(anchored, GridRect(x: 20, y: 0, width: 10, height: 4))
        expect(editor.render(), 28, 0, "H")
        expect(editor.render(), 29, 0, "i")
        expect(editor.render(), 24, 0, " ")

        let bottom = editor.addText(frame: GridRect(x: 20, y: 8, width: 1, height: 4), text: "A", style: plain("A", movement: .bottom))
        expect(editor.render(), 20, 11, "A")
        editor.setFrame(bottom, GridRect(x: 20, y: 8, width: 1, height: 6))
        expect(editor.render(), 20, 13, "A")
        expect(editor.render(), 20, 11, " ")
    }

    func testTextOptionalBorderChangesGrid() {
        var editor = Editor()
        let id = editor.addText(frame: GridRect(x: 0, y: 0, width: 6, height: 3), text: "ab", style: plain("ab"))
        let open = editor.render()
        expect(open, 0, 0, "a")
        expect(open, 1, 0, "b")

        editor.setText(id) { $0.border = .single }
        let bordered = editor.render()
        XCTAssertNotEqual(open.plainText, bordered.plainText)
        expect(bordered, 0, 0, "┌")
        expect(bordered, 5, 0, "┐")
        expect(bordered, 1, 1, "a")
        expect(bordered, 2, 1, "b")
        expect(bordered, 0, 2, "└")
    }

    func testOrthogonalVersusStaircase() {
        var orthogonal = Editor()
        _ = orthogonal.addLine(LineProps(start: GridPoint(x: 0, y: 0), end: GridPoint(x: 3, y: 3), routing: .orthogonal, horizontalFirst: true))
        let elbow = orthogonal.render()
        expect(elbow, 3, 0, "┐")
        expect(elbow, 3, 2, "│")
        expect(elbow, 0, 0, "─")

        var stairs = Editor()
        _ = stairs.addLine(LineProps(start: GridPoint(x: 0, y: 0), end: GridPoint(x: 3, y: 3), routing: .staircase))
        let diagonal = stairs.render()
        expect(diagonal, 0, 0, "\\")
        expect(diagonal, 1, 1, "\\")
        expect(diagonal, 2, 2, "\\")
        expect(diagonal, 3, 3, "\\")
        XCTAssertNotEqual(elbow.plainText, diagonal.plainText)
    }

    func testDashGaps() {
        var editor = Editor()
        _ = editor.addLine(LineProps(
            start: GridPoint(x: 0, y: 0),
            end: GridPoint(x: 6, y: 0),
            routing: .orthogonal,
            dash: DashPattern(on: 1, off: 1)
        ))
        let grid = editor.render()
        expect(grid, 0, 0, "─")
        expect(grid, 1, 0, " ")
        expect(grid, 2, 0, "─")
        expect(grid, 3, 0, " ")
        expect(grid, 4, 0, "─")
        expect(grid, 5, 0, " ")
        expect(grid, 6, 0, "─")
    }

    func testArrowHeads() {
        var editor = Editor()
        _ = editor.addLine(LineProps(start: GridPoint(x: 0, y: 0), end: GridPoint(x: 5, y: 0), endCap: .arrow))
        expect(editor.render(), 5, 0, ">")
        expect(editor.render(), 4, 0, "─")

        _ = editor.addLine(LineProps(start: GridPoint(x: 0, y: 2), end: GridPoint(x: 0, y: 6), endCap: .arrow))
        expect(editor.render(), 0, 6, "v")

        _ = editor.addLine(LineProps(start: GridPoint(x: 0, y: 8), end: GridPoint(x: 4, y: 8), startCap: .arrow))
        expect(editor.render(), 0, 8, "<")
        expect(editor.render(), 1, 8, "─")

        _ = editor.addLine(LineProps(start: GridPoint(x: 8, y: 4), end: GridPoint(x: 8, y: 0), endCap: .arrow))
        expect(editor.render(), 8, 0, "^")
    }

    func testThreeCrowsFootStyles() {
        func render(_ style: CrowsFootStyle) -> RenderedGrid {
            var editor = Editor()
            _ = editor.addLine(LineProps(
                start: GridPoint(x: 0, y: 2),
                end: GridPoint(x: 6, y: 2),
                routing: .orthogonal,
                endCap: .crowsFoot(style)
            ))
            return editor.render()
        }

        let many = render(.many)
        let oneOrMany = render(.oneOrMany)
        let zeroOrMany = render(.zeroOrMany)

        expect(many, 6, 1, "┐")
        expect(many, 6, 2, "┤")
        expect(many, 6, 3, "┘")
        expect(many, 5, 2, "─")

        expect(oneOrMany, 6, 2, "┤")
        expect(oneOrMany, 5, 1, "│")
        expect(oneOrMany, 5, 2, "│")
        expect(oneOrMany, 5, 3, "│")

        expect(zeroOrMany, 6, 2, "┤")
        expect(zeroOrMany, 5, 2, "o")
        expect(zeroOrMany, 5, 1, " ")

        XCTAssertNotEqual(many.plainText, oneOrMany.plainText)
        XCTAssertNotEqual(many.plainText, zeroOrMany.plainText)
        XCTAssertNotEqual(oneOrMany.plainText, zeroOrMany.plainText)
    }

    func testAttachmentFollowsMoveAndBorderResize() {
        var editor = Editor()
        let rect = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 11, height: 7), border: .single, fill: nil, shadow: nil)
        let line = editor.addLine(LineProps(
            start: GridPoint(x: 0, y: 0),
            end: GridPoint(x: 18, y: 3),
            startAttachment: LineAnchor(shapeID: rect, edge: .right, t: 0.5),
            routing: .orthogonal,
            horizontalFirst: true
        ))
        guard case .line(let attached) = editor.object(line)?.kind else {
            return XCTFail("line missing")
        }
        XCTAssertEqual(attached.start, GridPoint(x: 10, y: 3))

        _ = editor.moveObjects([rect], by: GridPoint(x: 4, y: 3))
        guard case .line(let moved) = editor.object(line)?.kind else {
            return XCTFail("line missing after move")
        }
        let movedFrame = editor.object(rect)!.frame
        XCTAssertEqual(moved.start, GridPoint(x: 14, y: 6))
        XCTAssertEqual(moved.start.x, movedFrame.maxX - 1)
        XCTAssertGreaterThanOrEqual(moved.start.y, movedFrame.minY)
        XCTAssertLessThan(moved.start.y, movedFrame.maxY)
        expect(editor.render(), 15, 6, "─")

        let point = editor.addBorderPoint(rect, edge: .top, t: 0.5)!
        let userLine = editor.addLine(LineProps(
            start: GridPoint(x: 0, y: 0),
            end: GridPoint(x: 14, y: -3),
            startAttachment: LineAnchor(shapeID: rect, edge: .top, t: 0.5, pointID: point),
            routing: .orthogonal
        ))
        guard case .line(let onBorder) = editor.object(userLine)?.kind else {
            return XCTFail("user point line missing")
        }
        XCTAssertEqual(onBorder.start, GridPoint(x: 9, y: 3))
        XCTAssertEqual(onBorder.start.y, editor.object(rect)!.frame.minY)

        editor.setFrame(rect, GridRect(x: movedFrame.x, y: movedFrame.y, width: 21, height: 7))
        guard case .line(let resized) = editor.object(userLine)?.kind else {
            return XCTFail("user point line missing after resize")
        }
        let resizedFrame = editor.object(rect)!.frame
        XCTAssertEqual(resized.start, GridPoint(x: 14, y: resizedFrame.minY))
        XCTAssertEqual(resized.start.y, resizedFrame.minY)
        XCTAssertGreaterThanOrEqual(resized.start.x, resizedFrame.minX)
        XCTAssertLessThan(resized.start.x, resizedFrame.maxX)

        guard case .line(let rightEdge) = editor.object(line)?.kind else {
            return XCTFail("right edge line missing")
        }
        XCTAssertEqual(rightEdge.start.x, resizedFrame.maxX - 1)
        XCTAssertGreaterThanOrEqual(rightEdge.start.y, resizedFrame.minY)
        XCTAssertLessThan(rightEdge.start.y, resizedFrame.maxY)
    }

    func testAlphabetBlendFontAndOpaqueFill() throws {
        var ascii = Editor()
        _ = ascii.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: .single, fill: nil, shadow: nil)
        ascii.setAlphabet(.ascii)
        XCTAssertEqual(ascii.render().plainText, ["+--+", "|  |", "+--+"].joined(separator: "\n"))
        var heavy = Editor()
        _ = heavy.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: .double, fill: nil, shadow: nil)
        heavy.setAlphabet(.ascii)
        XCTAssertEqual(heavy.render().plainText, ["+==+", "|  |", "+==+"].joined(separator: "\n"))
        let saved = try ascii.saveData()
        let loaded = try Editor(data: saved)
        XCTAssertEqual(loaded.document.alphabet, .ascii)
        XCTAssertEqual(loaded.render().plainText, ascii.render().plainText)

        let legacyDocument = #"{"version":1,"objects":[],"groups":[],"stamps":[]}"#
        let decodedDocument = try JSONDecoder().decode(Document.self, from: Data(legacyDocument.utf8))
        XCTAssertEqual(decodedDocument.alphabet, .unicode)
        let legacyRect = #"{"border":"single","points":[]}"#
        let decodedRect = try JSONDecoder().decode(RectangleProps.self, from: Data(legacyRect.utf8))
        XCTAssertEqual(decodedRect.border, .single)
        XCTAssertTrue(decodedRect.blended)

        var blended = Editor()
        let box = blended.addRectangle(frame: GridRect(x: 0, y: 0, width: 7, height: 5), border: .single, fill: nil, shadow: nil)
        _ = blended.addLine(LineProps(start: GridPoint(x: 3, y: -1), end: GridPoint(x: 3, y: 2), routing: .orthogonal))
        XCTAssertEqual(blended.render().character(at: GridPoint(x: 3, y: 0)), "┼")
        blended.setRectangle(box) { $0.blended = false }
        XCTAssertEqual(blended.render().character(at: GridPoint(x: 3, y: 0)), "│")

        var covered = Editor()
        _ = covered.addLine(LineProps(start: GridPoint(x: 0, y: 1), end: GridPoint(x: 6, y: 1), routing: .orthogonal))
        _ = covered.addRectangle(frame: GridRect(x: 2, y: 0, width: 3, height: 3), border: nil, fill: " ", shadow: nil)
        expect(covered.render(), 1, 1, "─")
        expect(covered.render(), 2, 1, " ")
        expect(covered.render(), 4, 1, " ")
        expect(covered.render(), 5, 1, "─")

        var styled = Editor()
        let text = styled.addText(frame: GridRect(x: 0, y: 0, width: 12, height: 6), text: "H")
        styled.setText(text) { $0.fontName = "standard" }
        expect(styled.render(), 0, 0, "#")
        expect(styled.render(), 3, 0, "#")
        guard case .text(let props) = styled.object(text)?.kind else {
            return XCTFail("styled text missing")
        }
        XCTAssertEqual(TextLayout.rows(for: props).first, try FigletFont.bundled("standard").render("H").first)
    }

    func testCrossingJunctionIsNotEitherStroke() {
        var editor = Editor()
        _ = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 7, height: 5), border: .single, fill: nil, shadow: nil)
        _ = editor.addLine(LineProps(start: GridPoint(x: 3, y: -1), end: GridPoint(x: 3, y: 2), routing: .orthogonal))
        let grid = editor.render()
        let junction = grid.character(at: GridPoint(x: 3, y: 0))
        XCTAssertEqual(junction, "┼")
        XCTAssertNotEqual(junction, "─")
        XCTAssertNotEqual(junction, "│")
        expect(grid, 0, 0, "┌")
        expect(grid, 3, -1, "│")
        expect(grid, 1, 0, "─")
    }

    func testGroupMoveAndDuplicate() {
        var editor = Editor()
        let first = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: .single, fill: nil, shadow: nil)
        let second = editor.addRectangle(frame: GridRect(x: 6, y: 0, width: 4, height: 3), border: .single, fill: nil, shadow: nil)
        let group = editor.group([first, second])!
        _ = editor.moveObjects([first], by: GridPoint(x: 3, y: 2))
        XCTAssertEqual(editor.object(first)?.frame.x, 3)
        XCTAssertEqual(editor.object(first)?.frame.y, 2)
        XCTAssertEqual(editor.object(second)?.frame.x, 9)
        XCTAssertEqual(editor.object(second)?.frame.y, 2)

        let copy = editor.duplicateGroup(group, offset: GridPoint(x: 0, y: 6))!
        let copies = editor.document.groups.first { $0.id == copy }!.memberIDs
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(copies.allSatisfy { editor.object($0)?.frame.y == 8 })
        XCTAssertEqual(editor.object(first)?.frame.y, 2)
        XCTAssertEqual(editor.object(second)?.frame.y, 2)
        XCTAssertEqual(editor.document.objects.count, 4)
    }

    func testAlignmentSnapOnMoveAndResize() {
        var editor = Editor()
        editor.snapThreshold = 1
        _ = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 8, height: 4), border: .single, fill: nil, shadow: nil)
        let moving = editor.addRectangle(frame: GridRect(x: 20, y: 0, width: 4, height: 4), border: .single, fill: nil, shadow: nil)
        let edgeGuides = editor.moveObjects([moving], by: GridPoint(x: -11, y: 0))
        XCTAssertEqual(editor.object(moving)?.frame.x, 8)
        XCTAssertTrue(edgeGuides.contains { $0.kind == .edge && $0.axis == .vertical && $0.position == 8 })

        var centered = Editor()
        centered.snapThreshold = 1
        _ = centered.addRectangle(frame: GridRect(x: 0, y: 0, width: 10, height: 4), border: .single, fill: nil, shadow: nil)
        let box = centered.addRectangle(frame: GridRect(x: 10, y: 0, width: 4, height: 4), border: .single, fill: nil, shadow: nil)
        let centerGuides = centered.moveObjects([box], by: GridPoint(x: -6, y: 0))
        XCTAssertEqual(centered.object(box)?.frame.x, 3)
        XCTAssertTrue(centerGuides.contains { $0.kind == .center && $0.axis == .vertical && $0.position == 5 })

        var resizing = Editor()
        resizing.snapThreshold = 1
        let left = resizing.addRectangle(frame: GridRect(x: 0, y: 0, width: 8, height: 4), border: .single, fill: nil, shadow: nil)
        _ = resizing.addRectangle(frame: GridRect(x: 20, y: 0, width: 6, height: 4), border: .single, fill: nil, shadow: nil)
        let guides = resizing.resizeObject(left, to: GridRect(x: 0, y: 0, width: 19, height: 4))
        XCTAssertEqual(resizing.object(left)?.frame.width, 20)
        XCTAssertTrue(guides.contains { $0.kind == .edge && $0.position == 20 })
    }

    func testResizeEdgeUnderPointerDoesNotGrow() {
        var editor = Editor()
        let original = GridRect(x: 0, y: 0, width: 10, height: 4)
        let rect = editor.addRectangle(frame: original, border: .single, fill: nil, shadow: nil)
        let right = editor.resizedFrame(original: original, handle: .right, to: GridPoint(x: 10, y: 2))
        XCTAssertEqual(right, original)
        _ = editor.resizeObject(rect, to: right, snap: false)
        XCTAssertEqual(editor.object(rect)?.frame, original)

        let bottom = editor.resizedFrame(original: original, handle: .bottom, to: GridPoint(x: 4, y: 4))
        XCTAssertEqual(bottom, original)
        let corner = editor.resizedFrame(original: original, handle: .bottomRight, to: GridPoint(x: 10, y: 4))
        XCTAssertEqual(corner, original)
        XCTAssertEqual(editor.resizedFrame(original: original, handle: .left, to: GridPoint(x: 0, y: 1)), original)
        XCTAssertEqual(editor.resizedFrame(original: original, handle: .top, to: GridPoint(x: 3, y: 0)), original)

        let grown = editor.resizedFrame(original: original, handle: .right, to: GridPoint(x: 14, y: 2))
        XCTAssertEqual(grown, GridRect(x: 0, y: 0, width: 14, height: 4))
        _ = editor.resizeObject(rect, to: grown, snap: false)
        XCTAssertEqual(editor.object(rect)?.frame.width, 14)
    }

    func testAlignEdgesAndDistribute() {
        var editor = Editor()
        let left = editor.addRectangle(frame: GridRect(x: 0, y: 5, width: 4, height: 3), border: .single, fill: nil, shadow: nil)
        let right = editor.addRectangle(frame: GridRect(x: 12, y: 1, width: 6, height: 3), border: .single, fill: nil, shadow: nil)
        let locked = editor.addRectangle(frame: GridRect(x: 30, y: 8, width: 4, height: 3), border: .single, fill: nil, shadow: nil)
        editor.setLocked(locked, true)

        editor.align([left, right, locked], to: .top)
        XCTAssertEqual(editor.object(left)?.frame.y, 1)
        XCTAssertEqual(editor.object(right)?.frame.y, 1)
        XCTAssertEqual(editor.object(locked)?.frame, GridRect(x: 30, y: 8, width: 4, height: 3))
        editor.align([left, right], to: .left)
        XCTAssertEqual(editor.object(left)?.frame.x, 0)
        XCTAssertEqual(editor.object(right)?.frame.x, 0)
        editor.align([left, right], to: .right)
        XCTAssertEqual(editor.object(left)?.frame.maxX, editor.object(right)?.frame.maxX)

        var spaced = Editor()
        let a = spaced.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 2), border: .single, fill: nil, shadow: nil)
        let b = spaced.addRectangle(frame: GridRect(x: 10, y: 0, width: 4, height: 2), border: .single, fill: nil, shadow: nil)
        let c = spaced.addRectangle(frame: GridRect(x: 30, y: 0, width: 4, height: 2), border: .single, fill: nil, shadow: nil)
        spaced.distribute([a, b, c], along: .horizontal)
        XCTAssertEqual(spaced.object(a)?.frame.x, 0)
        XCTAssertEqual(spaced.object(c)?.frame.x, 30)
        XCTAssertEqual(spaced.object(b)?.frame.x, 15)
        spaced.undo()
        XCTAssertEqual(spaced.object(b)?.frame.x, 10)
    }

    func testLockedHiddenAndZOrder() {
        var editor = Editor()
        let back = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: nil, fill: "A", shadow: nil)
        let front = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: nil, fill: "B", shadow: nil)
        expect(editor.render(), 1, 1, "B")
        editor.setZIndex(back, 5)
        expect(editor.render(), 1, 1, "A")
        editor.setZIndex(front, 9)
        expect(editor.render(), 1, 1, "B")

        editor.setLocked(front, true)
        _ = editor.moveObjects([front], by: GridPoint(x: 6, y: 0))
        XCTAssertEqual(editor.object(front)?.frame.x, 0)

        editor.setHidden(front, true)
        expect(editor.render(), 1, 1, "A")
        editor.setHidden(back, true)
        XCTAssertEqual(editor.render().plainText, "")
        XCTAssertFalse(editor.render().plainText.contains("A"))
        XCTAssertFalse(editor.render().plainText.contains("B"))
    }

    func testUndoRestoresPriorGrid() {
        var editor = Editor()
        let before = editor.render().plainText
        _ = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: .single, fill: nil, shadow: nil)
        XCTAssertNotEqual(editor.render().plainText, before)
        XCTAssertTrue(editor.undo())
        XCTAssertEqual(editor.render().plainText, before)
    }

    func testPencilAndEraser() {
        var editor = Editor()
        editor.pencil(at: GridPoint(x: 1, y: 1), character: "X")
        expect(editor.render(), 1, 1, "X")
        editor.erase(at: GridPoint(x: 1, y: 1))
        expect(editor.render(), 1, 1, " ")

        _ = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 4, height: 3), border: .single, fill: nil, shadow: nil)
        expect(editor.render(), 0, 0, "┌")
        editor.erase(at: GridPoint(x: 0, y: 0))
        expect(editor.render(), 0, 0, " ")
        expect(editor.render(), 1, 0, "─")
    }

    func testBucketFillDoesNotLeak() {
        var editor = Editor()
        _ = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 7, height: 5), border: .single, fill: nil, shadow: nil)
        editor.pencil(at: GridPoint(x: 12, y: 8), character: "Z")
        editor.bucketFill(at: GridPoint(x: 2, y: 2), character: "*")
        let grid = editor.render()
        for y in 1...3 {
            for x in 1...5 {
                expect(grid, x, y, "*")
            }
        }
        expect(grid, 0, 0, "┌")
        expect(grid, 6, 4, "┘")
        expect(grid, 0, 2, "│")
        expect(grid, 10, 6, " ")
        expect(grid, 12, 8, "Z")
    }

    func testCharacterPicker() {
        var editor = Editor()
        editor.pencil(at: GridPoint(x: 2, y: 2), character: "Q")
        let picked = editor.pickCharacter(at: GridPoint(x: 2, y: 2))
        XCTAssertEqual(picked, "Q")
        XCTAssertEqual(editor.pencilCharacter, "Q")
        editor.pencil(at: GridPoint(x: 4, y: 1))
        expect(editor.render(), 4, 1, "Q")
    }

    func testFigletStringFontAlignmentAndResize() throws {
        var editor = Editor()
        let banner = editor.addBanner(frame: GridRect(x: 0, y: 0, width: 20, height: 6), text: "HI", fontName: "standard", alignment: .left)
        let standard = editor.render()
        expect(standard, 0, 0, "#")
        expect(standard, 1, 0, " ")
        expect(standard, 3, 0, "#")
        expect(standard, 4, 0, "#")
        expect(standard, 6, 0, "#")
        expect(standard, 0, 1, "#")
        expect(standard, 4, 1, " ")
        expect(standard, 5, 1, "#")
        expect(standard, 0, 3, "#")
        expect(standard, 6, 3, "#")

        editor.setFrame(banner, GridRect(x: 0, y: 0, width: 16, height: 6))
        editor.setBanner(banner) { $0.alignment = .right }
        let right = editor.render()
        expect(right, 9, 0, "#")
        expect(right, 0, 0, " ")
        XCTAssertNotEqual(standard.plainText, right.plainText)

        editor.setBanner(banner) { $0.alignment = .left }
        editor.setFrame(banner, GridRect(x: 0, y: 0, width: 20, height: 2))
        let clipped = editor.render()
        expect(clipped, 0, 0, "#")
        expect(clipped, 0, 3, " ")
        XCTAssertNotEqual(clipped.plainText, standard.plainText)

        editor.setFrame(banner, GridRect(x: 0, y: 0, width: 20, height: 6))
        editor.setBanner(banner) { $0.text = "I" }
        expect(editor.render(), 0, 0, "#")
        expect(editor.render(), 1, 0, "#")
        expect(editor.render(), 2, 0, "#")
        XCTAssertNotEqual(editor.render().plainText, standard.plainText)

        editor.setBanner(banner) {
            $0.text = "HI"
            $0.fontName = "slim"
            $0.customFLF = nil
            $0.alignment = .left
        }
        let slim = editor.render()
        expect(slim, 0, 0, "|")
        XCTAssertNotEqual(slim.plainText, standard.plainText)

        editor.setBanner(banner) { $0.fontName = "block" }
        let block = editor.render()
        expect(block, 1, 0, "-")
        XCTAssertNotEqual(block.plainText, standard.plainText)
        XCTAssertNotEqual(block.plainText, slim.plainText)
        for name in BundledFonts.names {
            _ = try FigletFont.bundled(name)
        }
    }

    func testFigletLettersBeyondHI() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for name in BundledFonts.names {
            let font = try FigletFont.bundled(name)
            let disk = try FigletFont.load(contentsOf: root.appendingPathComponent("Fonts/\(name).flf"))
            XCTAssertEqual(disk.glyphs, font.glyphs)
            for code in 32...126 {
                let character = Character(UnicodeScalar(code)!)
                let glyph = try XCTUnwrap(font.glyphs[character])
                XCTAssertEqual(glyph.count, 4, "\(name) \(character)")
                let width = glyph.map(\.count).max() ?? 0
                XCTAssertEqual(glyph.map(\.count), Array(repeating: width, count: 4))
                let placeholder = glyph.dropFirst().allSatisfy { $0.trimmingCharacters(in: .whitespaces) == "." }
                XCTAssertFalse(placeholder, "\(name) \(character) is a placeholder")
            }
            for code in Array(65...90) + Array(97...122) {
                let character = Character(UnicodeScalar(code)!)
                let glyph = try XCTUnwrap(font.glyphs[character])
                XCTAssertFalse(glyph.joined().contains(character), "\(name) \(character) is the literal character")
            }
            let a = try XCTUnwrap(font.glyphs["A"])
            let w = try XCTUnwrap(font.glyphs["W"])
            XCTAssertGreaterThanOrEqual(a[0].count, 3)
            XCTAssertGreaterThanOrEqual(w[0].count, 5)
            XCTAssertGreaterThanOrEqual(a.joined().filter { $0 != " " }.count, 4)
            XCTAssertGreaterThanOrEqual(w.joined().filter { $0 != " " }.count, 4)
            XCTAssertNotEqual(a[0].trimmingCharacters(in: .whitespaces), "A")
            XCTAssertNotEqual(w[0].trimmingCharacters(in: .whitespaces), "W")

            var editor = Editor()
            _ = editor.addBanner(
                frame: GridRect(x: 0, y: 0, width: 24, height: 6),
                text: "AW",
                fontName: name,
                alignment: .left
            )
            let rendered = editor.render().plainText
            XCTAssertFalse(rendered.contains("A"))
            XCTAssertFalse(rendered.contains("W"))
            let ink = rendered.filter { $0 != " " && $0 != "\n" }
            XCTAssertGreaterThan(ink.count, 6)
        }
        let standardA = try FigletFont.bundled("standard").glyphs["A"]
        let slimA = try FigletFont.bundled("slim").glyphs["A"]
        let blockA = try FigletFont.bundled("block").glyphs["A"]
        XCTAssertNotEqual(standardA, slimA)
        XCTAssertNotEqual(standardA, blockA)
    }

    func testCustomFigletFontFile() throws {
        let source = customFont()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("asciidraw-\(UUID().uuidString).flf")
        try source.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        var editor = Editor()
        let banner = editor.addBanner(frame: GridRect(x: 0, y: 0, width: 12, height: 3), text: "HI", fontName: "standard")
        try editor.loadBannerFont(banner, from: url)
        let grid = editor.render()
        expect(grid, 0, 0, "H")
        expect(grid, 1, 0, "H")
        expect(grid, 2, 0, "I")
        expect(grid, 3, 0, "I")

        editor.setBanner(banner) { $0.alignment = .right }
        editor.setFrame(banner, GridRect(x: 0, y: 0, width: 10, height: 3))
        expect(editor.render(), 6, 0, "H")
        expect(editor.render(), 9, 0, "I")
        expect(editor.render(), 0, 0, " ")

        let saved = try editor.saveData()
        let loaded = try Editor(data: saved)
        XCTAssertEqual(loaded.render().plainText, editor.render().plainText)
    }

    func testSingleKeyToolMapAndSpacePan() throws {
        let expected: [Character: Tool] = [
            "v": .select, "r": .rect, "d": .diamond, "t": .text, "s": .surface, "l": .line,
            "p": .pencil, "e": .eraser, "b": .bucket, "k": .picker, "a": .banner, "h": .pan,
        ]
        XCTAssertEqual(Set(expected.values), Set(Tool.allCases))
        XCTAssertEqual(Set(ToolShortcut.map.map(\.1)), Set(Tool.allCases))
        for (key, tool) in expected {
            XCTAssertEqual(ToolShortcut.tool(for: key), tool)
            XCTAssertEqual(KeyBinding.interpret(KeyChord(character: key)), .selectTool(tool))
            var editor = Editor()
            XCTAssertTrue(editor.selectTool(key: key))
            XCTAssertEqual(editor.tool, tool)
            XCTAssertEqual(editor.activeTool, tool)
        }
        XCTAssertEqual(KeyBinding.interpret(KeyChord(character: "R", shift: true)), .selectTool(.rect))

        var surface = Editor()
        surface.pencilCharacter = "#"
        _ = surface.addRectangle(frame: GridRect(x: 0, y: 0, width: 3, height: 2), border: nil, fill: "#", name: "Surface")
        expect(surface.render(), 0, 0, "#")
        expect(surface.render(), 2, 1, "#")

        let legacy = #"{"text":"Hi","alignment":"center","position":"middle","sweep":"down","lineMovement":"none","border":"single"}"#
        let decoded = try JSONDecoder().decode(TextProps.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.text, "Hi")
        XCTAssertEqual(decoded.alignment, .center)
        XCTAssertTrue(decoded.textInsideBorder)
        XCTAssertNil(decoded.fill)
        XCTAssertNil(decoded.fontName)
        XCTAssertTrue(decoded.blended)
        XCTAssertNil(KeyBinding.interpret(KeyChord(character: "r", command: true)))
        XCTAssertNil(KeyBinding.interpret(KeyChord(character: "r", option: true)))
        XCTAssertNil(KeyBinding.interpret(KeyChord(character: "r", control: true)))
        XCTAssertEqual(KeyBinding.interpret(KeyChord(character: " ")), .beginSpacePan)

        var editor = Editor()
        XCTAssertTrue(editor.selectTool(key: "p"))
        editor.beginSpacePan()
        XCTAssertEqual(editor.activeTool, .pan)
        XCTAssertEqual(editor.tool, .pencil)
        editor.beginSpacePan()
        editor.endSpacePan()
        XCTAssertEqual(editor.activeTool, .pencil)
        XCTAssertEqual(editor.tool, .pencil)
    }

    func testZoomToVisibleIgnoresHidden() {
        var visible = Editor()
        _ = visible.addRectangle(frame: GridRect(x: 0, y: 0, width: 10, height: 5), border: .single, fill: nil, shadow: nil)
        var withHidden = Editor()
        _ = withHidden.addRectangle(frame: GridRect(x: 0, y: 0, width: 10, height: 5), border: .single, fill: nil, shadow: nil)
        let far = withHidden.addRectangle(frame: GridRect(x: 400, y: 400, width: 30, height: 12), border: .single, fill: nil, shadow: nil)
        withHidden.setHidden(far, true)

        let fitA = visible.fitVisible(viewportWidth: 200, viewportHeight: 200, cellWidth: 10, cellHeight: 20, padding: 0, minZoom: 0.01, maxZoom: 20)
        let fitB = withHidden.fitVisible(viewportWidth: 200, viewportHeight: 200, cellWidth: 10, cellHeight: 20, padding: 0, minZoom: 0.01, maxZoom: 20)
        XCTAssertEqual(fitA, fitB)
        XCTAssertEqual(fitA?.zoom, 2)
    }

    func testSaveReloadExportWrappersPNGAndSVG() throws {
        var editor = Editor()
        let rect = editor.addRectangle(frame: GridRect(x: 0, y: 0, width: 12, height: 5), border: .single, fill: nil, shadow: nil)
        _ = editor.addText(frame: GridRect(x: 2, y: 2, width: 8, height: 1), text: "Hi", style: plain("Hi"))
        let line = editor.addLine(LineProps(
            start: GridPoint(x: 0, y: 0),
            end: GridPoint(x: 20, y: 2),
            startAttachment: LineAnchor(shapeID: rect, edge: .right, t: 0.5),
            routing: .orthogonal,
            endCap: .arrow,
            horizontalFirst: true
        ))
        let plain = editor.exportPlainText()
        XCTAssertTrue(plain.contains("Hi"))
        XCTAssertTrue(plain.contains("┌"))
        XCTAssertTrue(plain.contains(">"))
        XCTAssertTrue(plain.contains("─"))

        let data = try editor.saveData()
        let loaded = try Editor(data: data)
        XCTAssertEqual(loaded.render().plainText, plain)
        XCTAssertEqual(try editor.saveData(), data)

        let shell = editor.exportShell()
        let ruby = editor.exportRuby()
        let python = editor.exportPython()
        XCTAssertTrue(shell.contains(plain))
        XCTAssertTrue(ruby.contains(plain))
        XCTAssertTrue(python.contains(plain))
        XCTAssertTrue(shell.contains(": <<'"))
        XCTAssertTrue(ruby.contains("=begin"))
        XCTAssertTrue(python.contains("\"\"\""))

        let svg = editor.exportSVG()
        let xml = try XMLDocument(data: Data(svg.utf8), options: [.nodeLoadExternalEntitiesNever])
        XCTAssertEqual(xml.rootElement()?.name, "svg")
        XCTAssertTrue(svg.contains("Hi"))
        XCTAssertTrue(svg.contains("┌"))

        let png = editor.exportPNG()
        XCTAssertEqual(Array(png.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let pixels = image.dataProvider?.data as Data? else {
            return XCTFail("png did not decode")
        }
        let grid = editor.render()
        XCTAssertEqual(image.width, grid.columnCount * ExportMetrics.cellWidth)
        XCTAssertEqual(image.height, grid.rowCount * ExportMetrics.cellHeight)
        XCTAssertFalse(pixels.isEmpty)
        XCTAssertFalse(pixels.allSatisfy { $0 == pixels.first })

        let json = try editor.exportJSON()
        XCTAssertEqual(try Exporter.plainText(fromJSON: json), plain)

        var reloaded = try Editor(data: data)
        _ = reloaded.moveObjects([rect], by: GridPoint(x: 3, y: 1))
        guard case .line(let props) = reloaded.object(line)?.kind else {
            return XCTFail("reloaded line missing")
        }
        XCTAssertEqual(props.start, GridPoint(x: 14, y: 3))

        if let directory = ProcessInfo.processInfo.environment["ASCIIDRAW_PROOF_DIR"], !directory.isEmpty {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: folder.appendingPathComponent("sample.asciidraw"))
            try plain.write(to: folder.appendingPathComponent("plain.txt"), atomically: true, encoding: .utf8)
            try shell.write(to: folder.appendingPathComponent("shell.txt"), atomically: true, encoding: .utf8)
            try ruby.write(to: folder.appendingPathComponent("ruby.txt"), atomically: true, encoding: .utf8)
            try python.write(to: folder.appendingPathComponent("python.txt"), atomically: true, encoding: .utf8)
            try png.write(to: folder.appendingPathComponent("sample.png"))
            try svg.write(to: folder.appendingPathComponent("sample.svg"), atomically: true, encoding: .utf8)
            try json.write(to: folder.appendingPathComponent("export.json"))
            print("proof-dir \(directory)")
        }
    }

    func testEmptyEditorIsBlank() {
        let editor = Editor()
        XCTAssertTrue(editor.document.objects.isEmpty)
        XCTAssertTrue(editor.document.stamps.isEmpty)
        XCTAssertEqual(editor.document.version, 1)
    }

    func testTextCaretTracksTheGrid() {
        let frame = GridRect(x: 4, y: 2, width: 8, height: 3)
        let props = plain("Hi")
        XCTAssertEqual(TextCaret.location("ab\nc", index: 3).line, 1)
        XCTAssertEqual(TextCaret.location("ab\nc", index: 3).column, 0)
        XCTAssertEqual(TextCaret.cell(text: "Hi", index: 2, frame: frame, props: props), GridPoint(x: 6, y: 2))
        XCTAssertEqual(TextCaret.index(in: "Hi", frame: frame, props: props, cell: GridPoint(x: 5, y: 2)), 1)

        var centered = plain("Hi")
        centered.alignment = .center
        XCTAssertEqual(
            TextCaret.cell(text: "Hi", index: 0, frame: GridRect(x: 4, y: 2, width: 6, height: 1), props: centered),
            GridPoint(x: 6, y: 2)
        )

        let moved = plain("Hi", movement: .right)
        XCTAssertEqual(
            TextCaret.cell(text: "Hi", index: 0, frame: GridRect(x: 0, y: 0, width: 6, height: 1), props: moved),
            GridPoint(x: 4, y: 0)
        )

        var up = plain("ab\ncd")
        up.sweep = .up
        XCTAssertEqual(
            TextCaret.cell(text: "ab\ncd", index: 3, frame: GridRect(x: 0, y: 0, width: 4, height: 2), props: up),
            GridPoint(x: 0, y: 0)
        )
        XCTAssertEqual(TextCaret.index(in: "ab\ncd", frame: GridRect(x: 0, y: 0, width: 4, height: 2), props: up, cell: GridPoint(x: 0, y: 0)), 3)

        var bordered = plain("Ab")
        bordered.border = .single
        XCTAssertEqual(
            TextCaret.cell(text: "Ab", index: 0, frame: GridRect(x: 0, y: 0, width: 6, height: 3), props: bordered),
            GridPoint(x: 1, y: 1)
        )

        let inserted = TextCaret.insert("", at: 0, "A")
        XCTAssertEqual(inserted.text, "A")
        XCTAssertEqual(inserted.caret, 1)
        let deleted = TextCaret.deleteBackward("AB", at: 1)
        XCTAssertEqual(deleted.text, "B")
        XCTAssertEqual(deleted.caret, 0)

        let fitted = TextCaret.fittedFrame(
            text: "Hello",
            props: plain(""),
            origin: GridRect(x: 4, y: 2, width: 1, height: 1),
            minimum: nil
        )
        XCTAssertEqual(fitted, GridRect(x: 4, y: 2, width: 5, height: 1))
        let kept = TextCaret.fittedFrame(
            text: "A",
            props: plain(""),
            origin: GridRect(x: 1, y: 1, width: 8, height: 4),
            minimum: GridRect(x: 1, y: 1, width: 8, height: 4)
        )
        XCTAssertEqual(kept, GridRect(x: 1, y: 1, width: 8, height: 4))
    }

    func testTextContentKeepsASingleCell() {
        var editor = Editor()
        let id = editor.addText(frame: GridRect(x: 1, y: 1, width: 1, height: 1), text: "")
        editor.setTextContent(id, text: "A", frame: GridRect(x: 1, y: 1, width: 1, height: 1))
        XCTAssertEqual(editor.object(id)?.frame, GridRect(x: 1, y: 1, width: 1, height: 1))
        guard case .text(let props) = editor.object(id)?.kind else {
            return XCTFail("missing text")
        }
        XCTAssertEqual(props.text, "A")
        let grid = editor.render()
        XCTAssertEqual(grid.character(at: GridPoint(x: 1, y: 1)), "A")
    }

    func testBundledFigletFontFileNames() throws {
        XCTAssertEqual(BundledFonts.fileNames, ["block.flf", "slim.flf", "standard.flf"])
        for name in BundledFonts.fileNames {
            print("bundled-font \(name)")
            _ = try FigletFont.bundled(name)
        }
    }
}

private func plain(_ text: String, movement: LineMovement = .none) -> TextProps {
    TextProps(text: text, alignment: .left, position: .top, sweep: .down, lineMovement: movement, border: nil)
}

private func expect(_ grid: RenderedGrid, _ x: Int, _ y: Int, _ character: Character, file: StaticString = #filePath, line: UInt = #line) {
    let actual = grid.character(at: GridPoint(x: x, y: y))
    XCTAssertEqual(actual, character, "expected \(character) at \(x),\(y), got \(actual)\n\(grid.plainText)", file: file, line: line)
}

private func customFont() -> String {
    var lines = ["flf2a$ 1 1 8 -1 0"]
    for code in 32...126 {
        let character = Character(UnicodeScalar(code)!)
        lines.append("\(character)\(character)@@")
    }
    return lines.joined(separator: "\n") + "\n"
}
