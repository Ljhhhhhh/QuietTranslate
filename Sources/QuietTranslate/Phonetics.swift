import Foundation

struct Phonetics {
    let us: String?

    static func supports(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count <= 64 && text.split(separator: " ").count <= 4
            && text.range(of: "^[A-Za-z]+(?:['’-][A-Za-z]+)*(?: +[A-Za-z]+(?:['’-][A-Za-z]+)*)*$",
                          options: .regularExpression) != nil
    }

    static func lookup(_ raw: String) async throws -> Phonetics {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard supports(word) else { return Phonetics(us: nil) }
        var components = URLComponents(string: "https://dictionary.cambridge.org/search/direct/")!
        components.queryItems = [URLQueryItem(name: "datasetsearch", value: "english-chinese-simplified"),
                                 URLQueryItem(name: "q", value: word)]
        var request = URLRequest(url: components.url!, timeoutInterval: 12)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.host == "dictionary.cambridge.org", data.count <= 2_000_000 else {
            throw URLError(.badServerResponse)
        }
        return try parseHTML(data, word: word)
    }

    static func parseHTML(_ data: Data, word: String) throws -> Phonetics {
        guard let html = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        let document = try XMLDocument(xmlString: html, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
        let headers = try document.nodes(forXPath: "//*[contains(concat(' ', normalize-space(@class), ' '), ' pos-header ')]")
        var values: [String] = []
        for header in headers {
            let headwords = try header.nodes(forXPath: ".//*[contains(concat(' ', normalize-space(@class), ' '), ' hw ')]")
            guard headwords.contains(where: {
                $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "’", with: "'").lowercased()
                    == word.replacingOccurrences(of: "’", with: "'").lowercased()
            }) else { continue }
            let regions = try header.nodes(forXPath: ".//*[contains(concat(' ', normalize-space(@class), ' '), ' us ') and contains(concat(' ', normalize-space(@class), ' '), ' dpron-i ')]")
            for region in regions {
                var nodes = try region.nodes(forXPath: ".//*[contains(concat(' ', normalize-space(@class), ' '), ' ipa ')]")
                // Foundation's HTML tidy moves Cambridge's pronunciation span past the audio divs.
                if nodes.isEmpty {
                    nodes = try region.nodes(forXPath: "following-sibling::*[not(self::div)][1][contains(concat(' ', normalize-space(@class), ' '), ' pron ')]//*[contains(concat(' ', normalize-space(@class), ' '), ' ipa ')]")
                }
                for node in nodes {
                    guard let raw = node.stringValue else { continue }
                    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, value.count <= 160,
                          value.unicodeScalars.allSatisfy({ scalar in
                              (0x61...0x7A).contains(scalar.value)
                                  || (0xC0...0x36F).contains(scalar.value)
                                  || (0x1D00...0x1DBF).contains(scalar.value)
                                  || " '’./()-".unicodeScalars.contains(scalar)
                          }), !values.contains(value) else { continue }
                    values.append(value)
                }
            }
        }
        return Phonetics(us: values.isEmpty ? nil : values.joined(separator: ", "))
    }
}
