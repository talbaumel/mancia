import Foundation
import Testing
@testable import Mancia

@Suite("Selection text verification")
struct SelectionTextVerificationTests {
    @Test("Rich-text representations verify without extending the saved range", arguments: [
        ("replacement", "replacement\n"),
        ("first  second", "first \u{00A0}second\n"),
        ("first  second", "first \u{00A0}second"),
        ("hello 😀 שלום", "hello 😀 שלום\n"),
        ("line\n", "line\n\n"),
    ])
    func richTextReplacement(pair: (String, String)) throws {
        let (replacement, actual) = pair
        let range = try #require(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: replacement,
            actualFieldValue: actual,
            replacing: CFRange(location: 0, length: 8),
            with: replacement,
            isRichTextField: true))
        #expect(range.location == 0)
        #expect(range.length == replacement.utf16.count)
    }

    @Test("Native fields still require exact text", arguments: [
        ("replacement", "replacement\n"),
        ("first  second", "first \u{00A0}second"),
    ])
    func nativeFieldsStayExact(pair: (String, String)) {
        let (replacement, actual) = pair
        #expect(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: replacement,
            actualFieldValue: actual,
            replacing: CFRange(location: 0, length: 8),
            with: replacement,
            isRichTextField: false) == nil)
    }

    @Test("Exact replacement keeps UTF-16 offsets in native fields")
    func exactReplacementRange() throws {
        let prefix = "😀 before "
        let replacement = "שלום"
        let value = prefix + replacement + " after"
        let range = try #require(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: value,
            actualFieldValue: value,
            replacing: CFRange(location: prefix.utf16.count, length: 8),
            with: replacement,
            isRichTextField: false))
        #expect(range.location == prefix.utf16.count)
        #expect(range.length == replacement.utf16.count)
    }

    @Test("Rich-text space conversion preserves surrounding plain text")
    func surroundingPlainTextIsPreserved() throws {
        let replacement = "first  second"
        let expected = "before " + replacement + " after"
        let actual = "before first \u{00A0}second after"
        let range = try #require(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: expected,
            actualFieldValue: actual,
            replacing: CFRange(location: 7, length: 8),
            with: replacement,
            isRichTextField: true))
        #expect(range.location == 7)
        #expect(range.length == replacement.utf16.count)

        let reencodedContext = "before\u{00A0}first \u{00A0}second\u{00A0}after"
        #expect(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: expected,
            actualFieldValue: reencodedContext,
            replacing: CFRange(location: 7, length: 8),
            with: replacement,
            isRichTextField: true) != nil)
        #expect(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: expected,
            actualFieldValue: reencodedContext,
            replacing: CFRange(location: 7, length: 8),
            with: replacement,
            isRichTextField: false) == nil)
        for changed in [
            "Before first \u{00A0}second after",
            "before first \u{00A0}second After",
            "before  first \u{00A0}second after",
            "before\u{202F}first \u{00A0}second after",
            actual + "\n\n",
        ] {
            #expect(SelectionTextVerification.verifiedReplacementRange(
                expectedFieldValue: expected,
                actualFieldValue: changed,
                replacing: CFRange(location: 7, length: 8),
                with: replacement,
                isRichTextField: true) == nil)
        }
    }

    @Test("A new structural newline can follow unchanged surrounding text")
    func structuralNewlineAfterSuffix() throws {
        let expected = "before value after"
        let range = try #require(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: expected,
            actualFieldValue: expected + "\n",
            replacing: CFRange(location: 7, length: 8),
            with: "value",
            isRichTextField: true))
        #expect(range.location == 7)
        #expect(range.length == 5)
        #expect(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: expected,
            actualFieldValue: expected + "\n",
            replacing: CFRange(location: 7, length: 8),
            with: "value",
            isRichTextField: false) == nil)
        #expect(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: expected + "\n",
            actualFieldValue: expected + "\n\n",
            replacing: CFRange(location: 7, length: 8),
            with: "value",
            isRichTextField: true) == nil)
    }

    @Test("Verification does not trim text or collapse real blank lines", arguments: [
        ("replacement", "Replacement\n"),
        ("replacement", "replacement\n\n"),
        ("first\nsecond", "first\n\nsecond"),
        ("replacement\n", "replacement"),
        (" replacement ", "replacement"),
        ("replacement\t", "replacement "),
        ("replacement", "replacement\u{200B}"),
    ])
    func changedTextIsRejected(pair: (String, String)) {
        let (replacement, actual) = pair
        #expect(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: replacement,
            actualFieldValue: actual,
            replacing: CFRange(location: 0, length: 8),
            with: replacement,
            isRichTextField: true) == nil)
    }

    @Test("Invalid replacement metadata cannot verify")
    func invalidRangesAreRejected() {
        for range in [
            CFRange(location: -1, length: 1),
            CFRange(location: 0, length: -1),
            CFRange(location: 20, length: 1),
            CFRange(location: 2, length: 1),
        ] {
            #expect(SelectionTextVerification.verifiedReplacementRange(
                expectedFieldValue: "text",
                actualFieldValue: "text",
                replacing: range,
                with: "text",
                isRichTextField: true) == nil)
        }
        #expect(SelectionTextVerification.verifiedReplacementRange(
            expectedFieldValue: "text",
            actualFieldValue: "text",
            replacing: CFRange(location: 0, length: 4),
            with: "",
            isRichTextField: true) == nil)
    }

    @Test("Rich-text Copy may encode AX non-breaking spaces as ordinary spaces")
    func selectedTextRepresentation() {
        #expect(SelectionTextVerification.matches(
            "first \u{00A0}second", "first  second", isRichTextField: true))
        #expect(!SelectionTextVerification.matches(
            "first \u{00A0}second", "first  second", isRichTextField: false))
        #expect(!SelectionTextVerification.matches(
            "first  second\n", "first  second", isRichTextField: true))
        #expect(!SelectionTextVerification.matches(
            "first  second", "first second", isRichTextField: true))
    }

    @Test("Select All can omit one structural newline in rich-text fields")
    func fullFieldSelection() {
        #expect(SelectionTextVerification.coversField(
            "text\n", range: CFRange(location: 0, length: 4),
            selectedText: "text", isRichTextField: true))
        #expect(SelectionTextVerification.coversField(
            "text\n", range: CFRange(location: 0, length: 5),
            selectedText: "text", isRichTextField: true))
        #expect(SelectionTextVerification.coversField(
            "text\n\n", range: CFRange(location: 0, length: 5),
            selectedText: "text\n", isRichTextField: true))
        #expect(SelectionTextVerification.coversField(
            "\n", range: CFRange(location: 0, length: 0),
            selectedText: "", isRichTextField: true))
        #expect(SelectionTextVerification.coversField(
            "\n", range: CFRange(location: 0, length: 1),
            selectedText: "", isRichTextField: true))
        #expect(SelectionTextVerification.coversField(
            "text", range: CFRange(location: 0, length: 4),
            selectedText: "text", isRichTextField: false))
        #expect(!SelectionTextVerification.coversField(
            "text\n", range: CFRange(location: 0, length: 4),
            selectedText: "text", isRichTextField: false))
        #expect(!SelectionTextVerification.coversField(
            "text\n", range: CFRange(location: 0, length: 5),
            selectedText: "text", isRichTextField: false))
        #expect(!SelectionTextVerification.coversField(
            "text\n\n", range: CFRange(location: 0, length: 4),
            selectedText: "text", isRichTextField: true))
        #expect(!SelectionTextVerification.coversField(
            "text\n", range: CFRange(location: 1, length: 4),
            selectedText: "text", isRichTextField: true))
        #expect(!SelectionTextVerification.coversField(
            "text\n", range: CFRange(location: 0, length: 4),
            selectedText: nil, isRichTextField: true))
    }
}
