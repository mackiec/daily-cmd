import Foundation

enum Links {
    // "nuevo.tokyo/agbr" → https://nuevo.tokyo/agbr. Anything without a host, or with spaces, isn't a link.
    static func parse(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        let full = t.contains("://") ? t : (t.contains(".") ? "https://" + t : t)
        guard let u = URL(string: full), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = u.host, host.contains(".") || host == "localhost" else { return nil }
        return u
    }

    // What a reference shows until (or if) its page title arrives.
    static func placeholder(_ u: URL) -> String {
        let h = u.host ?? u.absoluteString
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    private static let titleTag = try! NSRegularExpression(pattern: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.caseInsensitive])
    private static let ogTitle = try! NSRegularExpression(
        pattern: #"<meta[^>]+property=["']og:title["'][^>]*content=["']([^"']+)["']"#, options: [.caseInsensitive])

    // Plain GET with a 10-second timeout, reading <title> (or og:title). Calls back on the main queue,
    // with nil if there's no usable title.
    static func fetchTitle(_ u: URL, done: @escaping (String?) -> Void) {
        var req = URLRequest(url: u, timeoutInterval: 10)
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                     forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let title = data.flatMap { d -> String? in
                let html = String(decoding: d.prefix(1_000_000), as: UTF8.self)
                return first(ogTitle, html) ?? first(titleTag, html)
            }
            DispatchQueue.main.async { done(title) }
        }.resume()
    }

    private static func first(_ re: NSRegularExpression, _ html: String) -> String? {
        let ns = html as NSString
        guard let m = re.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let t = decode(ns.substring(with: m.range(at: 1)))
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return t.isEmpty ? nil : String(t.prefix(140))
    }

    private static func decode(_ s: String) -> String {
        var out = s
        for (k, v) in ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
                       "&mdash;": "—", "&ndash;": "–", "&hellip;": "…", "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”"] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        let numeric = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for m in numeric.matches(in: out, range: NSRange(location: 0, length: (out as NSString).length)).reversed() {
            let ns = out as NSString
            let hex = ns.substring(with: m.range(at: 1)) == "x"
            guard let code = UInt32(ns.substring(with: m.range(at: 2)), radix: hex ? 16 : 10), let ch = Unicode.Scalar(code) else { continue }
            out = ns.replacingCharacters(in: m.range, with: String(Character(ch)))
        }
        return out
    }
}

// "fix the photo grid @garden" → ("fix the photo grid", garden-journal). A token that names no project
// stays in the text, and `unknown` says which token didn't match.
struct ScopeToken {
    var text: String
    var scope: Scope?
    var unknown: String?

    init(_ input: String, projects: [Project]) {
        var words = input.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        text = input
        guard let i = words.lastIndex(where: { $0.hasPrefix("@") && $0.count > 1 }) else { return }
        let key = words[i].dropFirst().lowercased()
        let match: Scope? = "inbox".hasPrefix(key) ? .inbox
            : (projects.first { $0.name.lowercased() == key } ?? projects.first { $0.name.lowercased().hasPrefix(key) }
               ?? projects.first { $0.name.lowercased().contains(key) }).map { Scope(project: $0.url) }
        guard let match else { unknown = String(key); return }
        scope = match
        words.remove(at: i)
        text = words.joined(separator: " ")
    }
}
