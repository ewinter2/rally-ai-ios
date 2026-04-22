import XCTest
@testable import RallyTrack

// Tests for VoiceRecognitionManager.normalizeNumberWords(_:).
// This is a pure function — no audio session needed, so all tests run offline.
//
// Coverage:
//   - Single number words (zero–nineteen)
//   - Round tens (twenty–ninety)
//   - Compound numbers (twenty-one through ninety-nine)
//   - Real voice command phrases
//   - Word-boundary safety (no partial replacements)
//   - Case insensitivity (function lowercases input)
//   - Edge cases (empty string, already digits, etc.)
@MainActor
final class VoiceRecognitionTests: XCTestCase {

    private func normalize(_ input: String) -> String {
        VoiceRecognitionManager.normalizeNumberWords(input)
    }

    // MARK: - Zero through nine

    func test_normalize_zero()  { XCTAssertEqual(normalize("zero"),  "0") }
    func test_normalize_one()   { XCTAssertEqual(normalize("one"),   "1") }
    func test_normalize_two()   { XCTAssertEqual(normalize("two"),   "2") }
    func test_normalize_three() { XCTAssertEqual(normalize("three"), "3") }
    func test_normalize_four()  { XCTAssertEqual(normalize("four"),  "4") }
    func test_normalize_five()  { XCTAssertEqual(normalize("five"),  "5") }
    func test_normalize_six()   { XCTAssertEqual(normalize("six"),   "6") }
    func test_normalize_seven() { XCTAssertEqual(normalize("seven"), "7") }
    func test_normalize_eight() { XCTAssertEqual(normalize("eight"), "8") }
    func test_normalize_nine()  { XCTAssertEqual(normalize("nine"),  "9") }

    // MARK: - Ten through nineteen

    func test_normalize_ten()       { XCTAssertEqual(normalize("ten"),       "10") }
    func test_normalize_eleven()    { XCTAssertEqual(normalize("eleven"),    "11") }
    func test_normalize_twelve()    { XCTAssertEqual(normalize("twelve"),    "12") }
    func test_normalize_thirteen()  { XCTAssertEqual(normalize("thirteen"),  "13") }
    func test_normalize_fourteen()  { XCTAssertEqual(normalize("fourteen"),  "14") }
    func test_normalize_fifteen()   { XCTAssertEqual(normalize("fifteen"),   "15") }
    func test_normalize_sixteen()   { XCTAssertEqual(normalize("sixteen"),   "16") }
    func test_normalize_seventeen() { XCTAssertEqual(normalize("seventeen"), "17") }
    func test_normalize_eighteen()  { XCTAssertEqual(normalize("eighteen"),  "18") }
    func test_normalize_nineteen()  { XCTAssertEqual(normalize("nineteen"),  "19") }

    // MARK: - Round tens

    func test_normalize_twenty()  { XCTAssertEqual(normalize("twenty"),  "20") }
    func test_normalize_thirty()  { XCTAssertEqual(normalize("thirty"),  "30") }
    func test_normalize_forty()   { XCTAssertEqual(normalize("forty"),   "40") }
    func test_normalize_fifty()   { XCTAssertEqual(normalize("fifty"),   "50") }
    func test_normalize_sixty()   { XCTAssertEqual(normalize("sixty"),   "60") }
    func test_normalize_seventy() { XCTAssertEqual(normalize("seventy"), "70") }
    func test_normalize_eighty()  { XCTAssertEqual(normalize("eighty"),  "80") }
    func test_normalize_ninety()  { XCTAssertEqual(normalize("ninety"),  "90") }

    // MARK: - Compound numbers (space-separated)

    func test_normalize_twentyOne_spaced()   { XCTAssertEqual(normalize("twenty one"),   "21") }
    func test_normalize_thirtyFive_spaced()  { XCTAssertEqual(normalize("thirty five"),  "35") }
    func test_normalize_fortyTwo_spaced()    { XCTAssertEqual(normalize("forty two"),    "42") }
    func test_normalize_ninetyNine_spaced()  { XCTAssertEqual(normalize("ninety nine"),  "99") }

    // MARK: - Compound numbers (hyphenated)

    func test_normalize_twentyOne_hyphen()   { XCTAssertEqual(normalize("twenty-one"),   "21") }
    func test_normalize_fiftyThree_hyphen()  { XCTAssertEqual(normalize("fifty-three"),  "53") }
    func test_normalize_ninetyNine_hyphen()  { XCTAssertEqual(normalize("ninety-nine"),  "99") }

    // MARK: - Real voice command phrases

    func test_normalize_singleDigitWithAction() {
        XCTAssertEqual(normalize("seven ace"), "7 ace")
    }

    func test_normalize_compoundPlayerNumberWithAction() {
        XCTAssertEqual(normalize("twenty one kill"), "21 kill")
    }

    func test_normalize_numberAndBadPass() {
        XCTAssertEqual(normalize("three bad pass"), "3 bad pass")
    }

    func test_normalize_multipleNumbersInPhrase() {
        XCTAssertEqual(normalize("one two three"), "1 2 3")
    }

    func test_normalize_mixedExistingDigitAndWord() {
        XCTAssertEqual(normalize("player 7 twenty one kill"), "player 7 21 kill")
    }

    // MARK: - Word-boundary safety

    func test_normalize_bone_unchanged() {
        XCTAssertEqual(normalize("bone"), "bone")
    }

    func test_normalize_anyone_unchanged() {
        XCTAssertEqual(normalize("anyone"), "anyone")
    }

    func test_normalize_stone_unchanged() {
        XCTAssertEqual(normalize("stone"), "stone")
    }

    func test_normalize_done_unchanged() {
        XCTAssertEqual(normalize("done"), "done")
    }

    func test_normalize_tone_unchanged() {
        XCTAssertEqual(normalize("tone"), "tone")
    }

    // MARK: - Case insensitivity (function lowercases input)

    func test_normalize_uppercase_one() {
        XCTAssertEqual(normalize("ONE"), "1")
    }

    func test_normalize_uppercase_compound() {
        XCTAssertEqual(normalize("TWENTY-ONE"), "21")
    }

    func test_normalize_mixedCase_action() {
        XCTAssertEqual(normalize("SEVEN ACE"), "7 ace")
    }

    // MARK: - Edge cases

    func test_normalize_emptyString_returnsEmpty() {
        XCTAssertEqual(normalize(""), "")
    }

    func test_normalize_noNumbers_unchanged() {
        XCTAssertEqual(normalize("kill ace dig"), "kill ace dig")
    }

    func test_normalize_alreadyDigits_unchanged() {
        XCTAssertEqual(normalize("7 ace"), "7 ace")
    }

    func test_normalize_outputIsAlwaysLowercased() {
        // normalizeNumberWords lowercases the whole string, not just number words
        XCTAssertEqual(normalize("KILL"), "kill")
        XCTAssertEqual(normalize("Bad Pass"), "bad pass")
    }
}
