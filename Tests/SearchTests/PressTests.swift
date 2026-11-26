import AppKit
import SwiftUI
import XCTest
@testable import Search

/// What a press reaches in the shared pieces: a row with a switch in it,
/// a row that is a button with other buttons beside it, a small symbol
/// with more to land on than it draws, a link, a heading that opens.
/// Pressed for real, in a window off the screen, as SidebarPressTests does.
@MainActor
final class PressTests: XCTestCase {
    private var windows: [NSWindow] = []

    override class func setUp() {
        TestWorld.enter()
        super.setUp()
    }

    override func tearDown() async throws {
        for window in windows { window.contentView = nil; window.close() }
        windows.removeAll()
        try await super.tearDown()
    }

    // MARK: - a row and its switch

    func testClickAnywhereOnTheRowTurnsItsSwitch() async throws {
        let state = Flag()
        let window = makeWindow(root: Line("Block ads") { Switch(on: state.binding) }, width: 300, height: 44)
        try await settle()
        try await click(NSPoint(x: 40, y: 22), in: window)
        XCTAssertTrue(state.on, "A click on the row's words turns the switch")
        try await click(NSPoint(x: 150, y: 22), in: window)
        XCTAssertFalse(state.on, "And one on the empty middle of the row turns it back")
    }

    func testClickOnTheSwitchTurnsItOnce() async throws {
        let state = Flag()
        let window = makeWindow(root: Line("Block ads") { Switch(on: state.binding) }, width: 300, height: 44)
        try await settle()
        // The switch is 32 wide, 16 in from the row's end.
        try await click(NSPoint(x: 268, y: 22), in: window)
        XCTAssertEqual(state.turns, 1, "The switch takes its own click; the row doesn't turn it a second time")
        XCTAssertTrue(state.on)
    }

    func testSettingRowTurnsItsSwitchToo() async throws {
        let state = Flag()
        let row = SettingRow(icon: "", title: "Sleeping tabs", detail: "Tabs you haven't used go to sleep.") {
            Switch(on: state.binding)
        }
        let window = makeWindow(root: row, width: 420, height: 60)
        try await settle()
        try await click(NSPoint(x: 60, y: 30), in: window)
        XCTAssertTrue(state.on)
        XCTAssertEqual(state.turns, 1)
    }

    func testSwitchThatCantBeTurnedIsNotTurnedByItsRow() async throws {
        let state = Flag()
        let window = makeWindow(root: Line("Block ads") { Switch(on: state.binding).disabled(true) }, width: 300, height: 44)
        try await settle()
        try await click(NSPoint(x: 40, y: 22), in: window)
        XCTAssertFalse(state.on)
        XCTAssertEqual(state.turns, 0)
    }

    func testRowWithAnotherControlIsLeftAsItWas() async throws {
        var pressed = 0
        let window = makeWindow(root: Line("History") { Pill("Clear") { pressed += 1 } }, width: 300, height: 44)
        try await settle()
        try await click(NSPoint(x: 40, y: 22), in: window)
        XCTAssertEqual(pressed, 0, "Only a switch is turned from its row; a pill is pressed where it is")
        try await click(NSPoint(x: 262, y: 22), in: window)
        XCTAssertEqual(pressed, 1)
    }

    // MARK: - a row that is a button

    func testRowButtonOpensAndWhatIsBesideItTakesItsOwnClick() async throws {
        var opened = 0, removed = 0
        let row = RowButton(action: { opened += 1 }) {
            Text("A visit").frame(height: 36).padding(.leading, 14)
        } trailing: {
            Button("Remove") { removed += 1 }
                .buttonStyle(.plain)
                .frame(width: 60, height: 36)
        }
        let window = makeWindow(root: row, width: 300, height: 36)
        try await settle()
        try await click(NSPoint(x: 30, y: 18), in: window)
        XCTAssertEqual(opened, 1)
        // Past the words, still the row: all of it is the button.
        try await click(NSPoint(x: 200, y: 18), in: window)
        XCTAssertEqual(opened, 2)
        try await click(NSPoint(x: 270, y: 18), in: window)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(opened, 2, "A press on what is beside the button isn't the row's")
    }

    func testRowWithNothingToOpenStillLetsItBeRemoved() async throws {
        var opened = 0, removed = 0
        let row = RowButton(works: false, action: { opened += 1 }) {
            Text("Gone.zip").frame(height: 36).padding(.leading, 14)
        } trailing: {
            Button("Remove") { removed += 1 }
                .buttonStyle(.plain)
                .frame(width: 60, height: 36)
        }
        let window = makeWindow(root: row, width: 300, height: 36)
        try await settle()
        try await click(NSPoint(x: 30, y: 18), in: window)
        XCTAssertEqual(opened, 0)
        try await click(NSPoint(x: 270, y: 18), in: window)
        XCTAssertEqual(removed, 1)
    }

    func testRowThatCanBeCarriedStillOpensOnAClick() async throws {
        // A bookmark's row and a downloaded file's are carried by a drag
        // put on them from outside; the click is still the button's.
        var opened = 0
        let row = RowButton(action: { opened += 1 }) {
            Text("A file").frame(height: 36).padding(.leading, 14)
        }
        .onDrag { NSItemProvider(object: "a file" as NSString) }
        let window = makeWindow(root: row, width: 300, height: 36)
        try await settle()
        try await click(NSPoint(x: 30, y: 18), in: window)
        XCTAssertEqual(opened, 1)
    }

    // MARK: - a small symbol

    func testIconButtonIsLargerToLandOnThanItIsDrawn() async throws {
        var pressed = 0
        // Sixteen points drawn, in the middle of sixty: from 22 to 38.
        // Twenty-four to land on: from 18 to 42.
        let button = IconButton("xmark", label: "Remove", size: 16, hit: 24) { pressed += 1 }
            .frame(width: 60, height: 40)
        let window = makeWindow(root: button, width: 60, height: 40)
        try await settle()
        try await click(NSPoint(x: 30, y: 20), in: window)
        XCTAssertEqual(pressed, 1)
        try await click(NSPoint(x: 20, y: 20), in: window)
        XCTAssertEqual(pressed, 2, "Two points outside what is drawn still presses it")
        try await click(NSPoint(x: 10, y: 20), in: window)
        XCTAssertEqual(pressed, 2, "Well outside it doesn't")
    }

    func testIconButtonGrowsOnlyWhereItIsSmall() {
        XCTAssertEqual(IconButton("xmark", label: "Remove", size: 16, hit: 24) {}.grown, 4)
        XCTAssertEqual(IconButton("xmark", label: "Remove", size: 24, hit: 24) {}.grown, 0)
        XCTAssertEqual(IconButton("xmark", label: "Remove", size: 28, hit: 24) {}.grown, 0)
    }

    func testIconButtonThatCantBePressedIsnt() async throws {
        var pressed = 0
        let button = IconButton("minus", label: "Less") { pressed += 1 }
            .disabled(true)
            .frame(width: 60, height: 40)
        let window = makeWindow(root: button, width: 60, height: 40)
        try await settle()
        try await click(NSPoint(x: 30, y: 20), in: window)
        XCTAssertEqual(pressed, 0)
    }

    // MARK: - words that are pressed

    func testTextLinkIsPressed() async throws {
        var followed = 0
        let link = TextLink("Everything that's new…") { followed += 1 }
            .frame(width: 200, height: 30)
        let window = makeWindow(root: link, width: 200, height: 30)
        try await settle()
        try await click(NSPoint(x: 100, y: 15), in: window)
        XCTAssertEqual(followed, 1)
    }

    func testDisclosureOpensAndCloses() async throws {
        let state = Flag()
        let heading = Disclosure("Details", open: state.binding)
            .frame(width: 120, height: 30)
        let window = makeWindow(root: heading, width: 120, height: 30)
        try await settle()
        try await click(NSPoint(x: 60, y: 15), in: window)
        XCTAssertTrue(state.on)
        try await click(NSPoint(x: 60, y: 15), in: window)
        XCTAssertFalse(state.on)
    }


    func testSwitchIsLargerToLandOnThanItIsDrawn() async throws {
        let state = Flag()
        // 32 by 18 drawn, in the middle of 60 by 40: across from 14 to 46,
        // up from 11 to 29. Six more to land on, every side.
        let window = makeWindow(root: Switch(on: state.binding).frame(width: 60, height: 40), width: 60, height: 40)
        try await settle()
        try await click(NSPoint(x: 10, y: 20), in: window)
        XCTAssertEqual(state.turns, 1, "Four points before it")
        try await click(NSPoint(x: 30, y: 33), in: window)
        XCTAssertEqual(state.turns, 2, "Four points over it")
        try await click(NSPoint(x: 4, y: 20), in: window)
        XCTAssertEqual(state.turns, 2, "Ten points before it is not the switch")
    }

    func testTextLinkIsTallerToPressThanItsWords() async throws {
        var followed = 0
        // Its words are about 15 points high, in the middle of 40.
        let window = makeWindow(root: TextLink("Privacy") { followed += 1 }.frame(width: 80, height: 40), width: 80, height: 40)
        try await settle()
        try await click(NSPoint(x: 40, y: 30), in: window)
        XCTAssertEqual(followed, 1, "Just over the words")
        try await click(NSPoint(x: 40, y: 37), in: window)
        XCTAssertEqual(followed, 1, "Well over them")
    }

    // MARK: - the pieces stay in use

    /// The rows these pieces were made for are buttons: none is a tap on a
    /// stack again, which the keyboard and VoiceOver can't press.
    func testTheListsRowsAreButtons() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Search", isDirectory: true)
        for name in ["Recall.swift", "Bookmarks.swift", "ImportPanel.swift", "Archive.swift"] {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            let taps = text.components(separatedBy: "\n").filter {
                !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") && $0.contains(".onTapGesture")
            }
            XCTAssertEqual(taps, [], "\(name): a row is a Button (RowButton), not a tap on a stack")
        }
    }

    // MARK: - by hand

    /// What a test's switch or disclosure writes to, and how often.
    private final class Flag {
        var on = false
        var turns = 0
        var binding: Binding<Bool> {
            Binding(get: { self.on }, set: { self.on = $0; self.turns += 1 })
        }
    }

    private func makeWindow<V: View>(root: V, width: CGFloat, height: CGFloat) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: root.frame(width: width, height: height))
        window.orderFrontRegardless()
        windows.append(window)
        return window
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(250))
    }

    private func click(_ point: NSPoint, in window: NSWindow) async throws {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(40))
        }
        try await Task.sleep(for: .milliseconds(60))
    }
}
