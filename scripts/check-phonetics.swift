// swiftc -parse-as-library Sources/QuietTranslate/Phonetics.swift scripts/check-phonetics.swift -o /tmp/quiettranslate-phonetics-check
import Foundation

final class DictionaryStub: URLProtocol {
    static var requests: [URL] = []
    static var html = ""
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request.url!)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.html.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

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
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DictionaryStub.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        DictionaryStub.html = html.replacingOccurrences(of: "hello", with: "cacheword")
        let first = try await Phonetics.lookup("cacheword", session: session)
        assert(first.us == "heˈloʊ")
        assert(DictionaryStub.requests.last?.path == "/dictionary/english-chinese-simplified/cacheword")
        let count = DictionaryStub.requests.count
        let cached = try await Phonetics.lookup("  CACHEWORD  ", session: session)
        assert(cached.us == first.us && DictionaryStub.requests.count == count)
        DictionaryStub.html = html.replacingOccurrences(of: "hello", with: "don't")
        let contraction = try await Phonetics.lookup("don't", session: session)
        assert(contraction.us != nil)
        assert(DictionaryStub.requests.last?.path == "/search/direct")
        for _ in 0..<2 { _ = try await Phonetics.lookup("unknownword", session: session) }
        assert(DictionaryStub.requests.count == count + 3, "Missing IPA must remain retryable")
        DictionaryStub.status = 503
        for _ in 0..<2 {
            do {
                _ = try await Phonetics.lookup("failedword", session: session)
                assertionFailure("HTTP error accepted")
            } catch {}
        }
        assert(DictionaryStub.requests.count == count + 5, "Failures must not be cached")
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await Phonetics.lookup("cacheword", session: session)
        }
        do { _ = try await cancelled.value; assertionFailure("Cancelled cache lookup accepted") }
        catch is CancellationError {}
        if CommandLine.arguments.contains("--live") {
            for word in ["hello", "apple", "water", "record", "read", "lead", "live", "qzxvplm"] {
                let result = try await Phonetics.lookup(word)
                if word == "qzxvplm" { assert(result.us == nil) }
                else { assert(result.us != nil, word) }
                print("\(word): \(result.us ?? "not found")")
            }
        }
        print("Phonetic checks passed: English input, US-only extraction, exact headword, missing IPA, invalid text, deduplication, direct URL, normalized cache, retryable failures, cancellation.")
    }
}
