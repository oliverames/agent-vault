import Testing
@testable import AgentVault

@Suite("Sensitive value redaction")
struct SensitiveValueRedactorTests {
    @Test("redacts secrets in common agent configuration formats")
    func redactsConfigurationSecrets() {
        let openAIKey = "sk-" + "test-0123456789abcdefghijklmnop"
        let gitHubToken = "github_" + "pat_11AA_fake_token_value"
        let npmToken = "npm_" + "fake_token_value_0123456789"
        let source = #"""
        {
          "apiKey": "\#(openAIKey)",
          "authorization": "Bearer \#(gitHubToken)",
          "safe": "keep me"
        }
        OPENAI_API_KEY = "op://Example/Demo/API Key"
        password: super-secret-password
        token = "\#(npmToken)"
        """#

        let redacted = SensitiveValueRedactor().redact(source)

        #expect(!redacted.contains(openAIKey))
        #expect(!redacted.contains(gitHubToken))
        #expect(!redacted.contains("op://Example/Demo/API Key"))
        #expect(!redacted.contains("super-secret-password"))
        #expect(!redacted.contains(npmToken))
        #expect(redacted.contains("keep me"))
        #expect(redacted.contains("<redacted>"))
    }

    @Test("redacts standalone private key blocks")
    func redactsPrivateKeyBlocks() {
        let beginMarker = "-----BEGIN " + "PRIVATE KEY-----"
        let endMarker = "-----END " + "PRIVATE KEY-----"
        let privateKey = "\(beginMarker)\nsynthetic-private-key-material-for-testing-only\n\(endMarker)"
        let source = "prefix\n\(privateKey)\nsuffix\n"

        let redacted = SensitiveValueRedactor().redact(source)

        #expect(!redacted.contains("synthetic-private-key-material"))
        #expect(redacted.contains("prefix"))
        #expect(redacted.contains("<redacted>"))
        #expect(redacted.contains("suffix"))
    }

    @Test("leaves ordinary prose and command arguments unchanged")
    func preservesOrdinaryText() {
        let source = "Use `token_budget` only when a budget is explicit.\ntoken_budget = 4096\ncommand = \"swift test\"\n"

        #expect(SensitiveValueRedactor().redact(source) == source)
    }
}
