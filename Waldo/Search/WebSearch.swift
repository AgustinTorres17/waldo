import Foundation

/// One web result: what the model reads and the panel links to.
struct SearchResult: Sendable, Equatable, Codable {
    let title: String
    let url: URL
    let snippet: String
}

/// Where searches go. Only the query leaves the Mac, never the capture.
enum SearchProvider: String, CaseIterable, Identifiable, Sendable {
    /// DuckDuckGo's HTML page, read directly: nothing to install, no key.
    case duckDuckGo
    /// The user's own SearXNG instance (JSON API).
    case searXNG

    var id: String { rawValue }

    var title: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .searXNG: "SearXNG"
        }
    }
}

enum WebSearchError: LocalizedError {
    case blocked
    case badResponse(Int)
    case unreadable
    case noSearXNGURL
    case searXNGJSONDisabled

    var errorDescription: String? {
        switch self {
        case .blocked: "DuckDuckGo asked to verify you're human (too many searches). Try again later, or use SearXNG in Settings › General."
        case .badResponse(let status): "The search engine answered with status \(status)."
        case .unreadable: "Couldn't read the search results. DuckDuckGo may have changed its page."
        case .noSearXNGURL: "Set your SearXNG address in Settings › General › Web search."
        case .searXNGJSONDisabled: "Your SearXNG doesn't allow JSON results. Add json to search › formats in its settings.yml."
        }
    }
}

enum WebSearch {
    /// Enough for the model to cross-check without filling its context (~100 tokens each).
    static let maxResults = 6
    private static let maxSnippet = 320
    /// A regular browser's; DuckDuckGo's HTML page turns away unknown clients.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func search(_ query: String, provider: SearchProvider, searXNGURL: String) async throws -> [SearchResult] {
        switch provider {
        case .duckDuckGo: try await duckDuckGo(query)
        case .searXNG: try await searXNG(query, base: searXNGURL)
        }
    }

    // MARK: DuckDuckGo

    private static func duckDuckGo(_ query: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Locale.preferredLanguages.first ?? "en", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let html = String(decoding: data, as: UTF8.self)
        // The captcha page comes back as 202 (sometimes 200) with an "anomaly" form.
        if status == 202 || html.contains("anomaly-modal") { throw WebSearchError.blocked }
        guard status == 200 else { throw WebSearchError.badResponse(status) }
        let results = parseDuckDuckGo(html)
        // No results is still a results page; without its container the page changed.
        if results.isEmpty, !html.contains("serp__results") { throw WebSearchError.unreadable }
        return results
    }

    private static let titlePattern = try! NSRegularExpression(
        pattern: #"class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators])
    private static let snippetPattern = try! NSRegularExpression(
        pattern: #"class="result__snippet"[^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators])

    /// Each result is a `div.result` with a `result__a` link (title) and a
    /// `result__snippet`. Ads are left out.
    static func parseDuckDuckGo(_ html: String) -> [SearchResult] {
        var results: [SearchResult] = []
        for block in html.components(separatedBy: #"<div class="result "#).dropFirst() {
            guard !block.contains("result--ad"), results.count < maxResults else { continue }
            let range = NSRange(block.startIndex..., in: block)
            guard let title = titlePattern.firstMatch(in: block, range: range),
                  let href = Range(title.range(at: 1), in: block).map({ String(block[$0]) }),
                  let titleHTML = Range(title.range(at: 2), in: block).map({ String(block[$0]) }),
                  let url = resolveDuckDuckGoLink(decodeEntities(href)) else { continue }
            let snippet = snippetPattern.firstMatch(in: block, range: range)
                .flatMap { Range($0.range(at: 1), in: block) }
                .map { plainText(String(block[$0])) } ?? ""
            results.append(SearchResult(title: plainText(titleHTML), url: url, snippet: shortened(snippet)))
        }
        return results
    }

    /// Links are usually direct, sometimes DuckDuckGo redirects (`/l/?uddg=<target>`).
    private static func resolveDuckDuckGoLink(_ href: String) -> URL? {
        let absolute = href.hasPrefix("//") ? "https:" + href : href
        guard let url = URL(string: absolute), let host = url.host else { return nil }
        if host.hasSuffix("duckduckgo.com") {
            guard url.path == "/l" || url.path.hasPrefix("/l/"),
                  let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "uddg" })?.value else { return nil }
            return URL(string: target)
        }
        return url
    }

    // MARK: SearXNG

    private struct SearXNGResponse: Decodable {
        struct Result: Decodable {
            let title: String?
            let url: String?
            let content: String?
        }

        let results: [Result]
    }

    private static func searXNG(_ query: String, base: String) async throws -> [SearchResult] {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var components = URLComponents(string: trimmed.hasSuffix("/") ? trimmed + "search" : trimmed + "/search")
        else { throw WebSearchError.noSearXNGURL }
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "format", value: "json")]
        guard let url = components.url else { throw WebSearchError.noSearXNGURL }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 403 { throw WebSearchError.searXNGJSONDisabled }
        guard status == 200 else { throw WebSearchError.badResponse(status) }
        guard let decoded = try? JSONDecoder().decode(SearXNGResponse.self, from: data) else { throw WebSearchError.unreadable }
        return decoded.results.prefix(maxResults).compactMap { result in
            guard let link = result.url.flatMap(URL.init(string:)) else { return nil }
            return SearchResult(title: result.title ?? link.host ?? link.absoluteString, url: link,
                                snippet: shortened(result.content ?? ""))
        }
    }

    // MARK: Text

    private static func shortened(_ text: String) -> String {
        text.count > maxSnippet ? String(text.prefix(maxSnippet)) + "…" : text
    }

    /// Tags removed, entities decoded, whitespace collapsed.
    static func plainText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#x27;": "'", "&#39;": "'", "&nbsp;": " "]

    static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in entities where entity != "&amp;" {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        // Numeric entities (&#8217; &#x2019;).
        let pattern = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for match in pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let whole = Range(match.range, in: result), let hex = Range(match.range(at: 1), in: result),
                  let digits = Range(match.range(at: 2), in: result),
                  let value = UInt32(result[digits], radix: result[hex].isEmpty ? 10 : 16),
                  let scalar = Unicode.Scalar(value) else { continue }
            result.replaceSubrange(whole, with: String(Character(scalar)))
        }
        // Last, so "&amp;lt;" becomes "&lt;" and not "<".
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }
}
