// swiftc -parse-as-library Sources/QuietTranslate/Phonetics.swift scripts/check-phonetics.swift -o /tmp/quiettranslate-phonetics-check
import Foundation

@main struct PhoneticChecks {
    static func main() async throws {
        for text in ["hello", "  Hello  ", "take care", "mother-in-law", "don't"] {
            assert(Phonetics.supports(text), text)
        }
        for text in ["", "你好", "hello world!", "This is a full English sentence", "hello\nworld", "foo_bar", "123"] {
            assert(!Phonetics.supports(text), text)
        }
        let html = """
        <html><body><div class="pr entry-body__el"><div class="pos-header dpos-h">
        <span class="hw dhw">hello</span>
        <span class="uk dpron-i"><span class="ipa dipa">heˈləʊ</span></span>
        <span class="us dpron-i"><span class="ipa dipa">heˈloʊ</span></span>
        </div></div></body></html>
        """
        let result = try Phonetics.parseHTML(Data(html.utf8), word: "hello")
        assert(result.us == "heˈloʊ")
        assert(try! Phonetics.parseHTML(Data(html.utf8), word: "other").us == nil)
        let ukOnly = html.replacingOccurrences(of: "us dpron-i", with: "uk dpron-i")
        assert(try! Phonetics.parseHTML(Data(ukOnly.utf8), word: "hello").us == nil)
        let unsafe = html.replacingOccurrences(of: "heˈloʊ", with: "not an IPA\nresponse")
        assert(try! Phonetics.parseHTML(Data(unsafe.utf8), word: "hello").us == nil)
        let duplicate = html.replacingOccurrences(of: "</body>", with: html + "</body>")
        assert(try! Phonetics.parseHTML(Data(duplicate.utf8), word: "hello").us == "heˈloʊ")
        if CommandLine.arguments.contains("--live") {
            for word in ["hello", "apple", "water", "record", "read", "lead", "live", "qzxvplm"] {
                let result = try await Phonetics.lookup(word)
                if word == "qzxvplm" { assert(result.us == nil) }
                else { assert(result.us != nil, word) }
                print("\(word): \(result.us ?? "not found")")
            }
        }
        print("Phonetic checks passed: English input, US-only extraction, exact headword, missing IPA, invalid text, deduplication.")
    }
}
