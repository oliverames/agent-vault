import Foundation

/// Best-effort redaction for copies intended for browsing or sharing.
///
/// This is deliberately not used for restore backups. A backup must preserve
/// the original bytes, while a clean export should avoid copying common API
/// keys, passwords, and bearer tokens into a second location.
struct SensitiveValueRedactor: Sendable {
    private static let replacement = "<redacted>"

    private static let tokenPatterns: [NSRegularExpression] = [
        regex(#"(?is)-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----.*?-----END (?:[A-Z0-9]+ )*PRIVATE KEY-----"#),
        regex(#"(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]{12,}"#),
        regex(#"\bsk-[A-Za-z0-9_-]{16,}\b"#),
        regex(#"\bgithub_pat_[A-Za-z0-9_]{12,}\b"#),
        regex(#"\bgh[pousr]_[A-Za-z0-9]{12,}\b"#),
        regex(#"\bnpm_[A-Za-z0-9_]{12,}\b"#),
        regex(#"\bxox[baprs]-[A-Za-z0-9-]{12,}\b"#),
        regex(#"\bAKIA[0-9A-Z]{16}\b"#),
    ]

    func redact(_ source: String) -> String {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var redacted = lines.map { redactAssignment(in: String($0)) }.joined(separator: "\n")

        for pattern in Self.tokenPatterns {
            let range = NSRange(redacted.startIndex..<redacted.endIndex, in: redacted)
            let template = pattern.pattern.hasPrefix("(?i)(Bearer")
                ? "$1\(Self.replacement)"
                : Self.replacement
            redacted = pattern.stringByReplacingMatches(
                in: redacted,
                options: [],
                range: range,
                withTemplate: template
            )
        }

        return redacted
    }

    private func redactAssignment(in line: String) -> String {
        guard let separator = assignmentSeparator(in: line) else { return line }

        let keyPart = String(line[..<separator])
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "export ", with: "", options: [.anchored, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard isSensitiveKey(keyPart) else { return line }

        let valueStart = line.index(after: separator)
        let valueAndSuffix = String(line[valueStart...])
        let leadingWhitespace = valueAndSuffix.prefix { $0 == " " || $0 == "\t" }
        let value = valueAndSuffix.dropFirst(leadingWhitespace.count)
        guard !value.isEmpty else { return line }

        let suffix: Substring
        let quote = value.first
        if quote == "\"" || quote == "'" {
            suffix = suffixAfterQuotedValue(value, quote: quote!)
        } else if let comment = value.firstIndex(where: { $0 == "#" || $0 == "," }) {
            suffix = value[comment...]
        } else {
            suffix = ""
        }

        let prefix = line[...separator]
        let renderedReplacement: String
        if quote == "'" {
            renderedReplacement = "'\(Self.replacement)'"
        } else {
            renderedReplacement = "\"\(Self.replacement)\""
        }
        return "\(prefix)\(leadingWhitespace)\(renderedReplacement)\(suffix)"
    }

    private func assignmentSeparator(in line: String) -> String.Index? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("//") else { return nil }

        let equals = line.firstIndex(of: "=")
        let colon = line.firstIndex(of: ":")
        let separator = [equals, colon].compactMap { $0 }.min()
        guard let separator else { return nil }

        let key = line[..<separator]
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "_-. \t\"'"))
        guard key.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return separator
    }

    private func isSensitiveKey(_ key: String) -> Bool {
        let compact = key.lowercased().filter { $0.isLetter || $0.isNumber }
        let sensitiveSuffixes = [
            "apikey",
            "accesstoken",
            "authtoken",
            "bearertoken",
            "clientsecret",
            "privatekey",
            "accesskey",
            "authorization",
            "credential",
            "password",
            "passwd",
            "secret",
            "token",
        ]
        return sensitiveSuffixes.contains { compact == $0 || compact.hasSuffix($0) }
    }

    private func suffixAfterQuotedValue(_ value: Substring, quote: Character) -> Substring {
        var escaped = false
        for index in value.indices.dropFirst() {
            let character = value[index]
            if character == quote, !escaped {
                return value[value.index(after: index)...]
            }
            if character == "\\" {
                escaped.toggle()
            } else {
                escaped = false
            }
        }
        return ""
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // These patterns are constants covered by unit tests. Failing fast is
        // preferable to silently shipping a redactor with a disabled rule.
        try! NSRegularExpression(pattern: pattern)
    }
}
