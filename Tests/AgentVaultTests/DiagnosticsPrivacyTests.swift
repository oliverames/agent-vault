import Foundation
import Sentry
import Testing
@testable import AgentVault

struct DiagnosticsPrivacyTests {
    @Test func scrubRemovesInventoryText() {
        let text = DiagnosticsPrivacy.scrub(
            "Could not read \"secret-skill\" 'acme-mcp' for jane@example.com at https://github.com/jane/secret-project?token=abc from /Users/jane/Developer/Projects/secret-project/CLAUDE.md, /opt/homebrew/lib/node_modules/acme-mcp/index.js and ~/Library/Caches/x id 1234567",
            knownIdentifiers: ["janesmac"]
        )
        for secret in ["secret", "acme", "jane", "github", "1234567", "abc", "homebrew", "node_modules", "Caches", "CLAUDE"] {
            #expect(!text.contains(secret), "\(secret) leaked: \(text)")
        }
        #expect(text.hasPrefix("Could not read"))
    }

    @Test func scrubRemovesTokensIdentifiersAndLocalNames() {
        let text = DiagnosticsPrivacy.scrub(
            "Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig refresh_token=r1 id 6F9619FF-8B86-D011-B42D-00C04FC964FF on Janes-MacBook-Pro from 192.168.1.20",
            knownIdentifiers: ["Janes-MacBook-Pro"]
        )
        for secret in ["eyJ", "r1", "6F9619FF", "Janes", "192.168"] {
            #expect(!text.contains(secret), "\(secret) leaked: \(text)")
        }
    }

    @Test func scrubRemovesFileNamesAfterPathsWithSpaces() {
        let text = DiagnosticsPrivacy.scrub(
            "Could not open /Users/jane/Pictures/Beach Day.HEIC or Smith Family Budget.xlsx or notes.md",
            knownIdentifiers: []
        )
        for secret in ["Day", "HEIC", "Budget", "xlsx", "notes"] {
            #expect(!text.contains(secret), "\(secret) leaked: \(text)")
        }
    }

    @Test func scrubRemovesBearerTokensInHeaders() {
        for text in ["Authorization: Bearer xyz123", "authorization=Bearer xyz123", "Bearer xyz123"] {
            #expect(!DiagnosticsPrivacy.scrub(text, knownIdentifiers: []).contains("xyz123"))
        }
    }

    @Test func scrubKeepsTypeNamesAndCodes() {
        #expect(DiagnosticsPrivacy.scrub("AgentVault.FileBufferError code 3") == "AgentVault.FileBufferError code 3")
        #expect(DiagnosticsPrivacy.scrub("EXC_BAD_ACCESS") == "EXC_BAD_ACCESS")
    }

    @Test func pathsReduceToBundleSystemOrFileName() {
        let bundle = "/Applications/AgentVault.app"
        #expect(DiagnosticsPrivacy.reducePath(bundle + "/Contents/MacOS/AgentVault", bundlePath: bundle)
            == "AgentVault.app/Contents/MacOS/AgentVault")
        #expect(DiagnosticsPrivacy.reducePath("/System/Library/Frameworks/AppKit.framework/AppKit", bundlePath: bundle)
            == "/System/Library/Frameworks/AppKit.framework/AppKit")
        #expect(DiagnosticsPrivacy.reducePath("/Users/jane/Developer/agent-vault/Sources/AgentVault/Scanner.swift", bundlePath: bundle)
            == "Scanner.swift")
        #expect(DiagnosticsPrivacy.reducePath("/System/Library/../../Users/jane/x.dylib", bundlePath: bundle) == "x.dylib")
    }

    @Test func contextsKeepOnlyVersionsAndModel() {
        let kept = DiagnosticsPrivacy.filterContexts([
            "device": ["model": "Mac15,3", "name": "Jane's MacBook", "locale": "en_US", "arch": "arm64"],
            "culture": ["timezone": "America/New_York"],
            "app": ["app_version": "1.7.3", "device_app_hash": "abc", "app_start_time": "x"],
        ])
        let device = kept["device"].map { Array($0.keys).sorted() }
        let app = kept["app"].map { Array($0.keys).sorted() }
        #expect(device == ["arch", "model"])
        #expect(kept["culture"] == nil)
        #expect(app == ["app_version"])
    }

    @Test func contextsDropUserInfoAndFreeFormDictionaries() {
        let kept = DiagnosticsPrivacy.filterContexts([
            "user info": ["NSFilePath": "/Users/jane/Developer/Projects/secret-project/CLAUDE.md"],
            "AgentVaultCustom": ["root": "secret-project"],
            "os": ["name": "macOS", "version": "26.2", "rooted": false, "extra": "x"],
            "device": ["model": "Mac15,3", "memory_size": 34_359_738_368, "nested": ["name": "Jane"]],
        ])
        #expect(kept.keys.sorted() == ["device", "os"])
        let os = kept["os"].map { Array($0.keys).sorted() }
        let device = kept["device"].map { Array($0.keys).sorted() }
        #expect(os == ["name", "version"])
        #expect(device == ["memory_size", "model"])
    }

    @Test func rateLimiterAllowsOnePerHourAndTenPerRun() {
        var limiter = DiagnosticsRateLimiter()
        var results: [Bool] = []
        results.append(limiter.shouldSend(key: "a", now: 0))
        results.append(limiter.shouldSend(key: "a", now: 60))
        results.append(limiter.shouldSend(key: "a", now: 3_601))
        for index in 0..<8 { results.append(limiter.shouldSend(key: "k\(index)", now: 0)) }
        results.append(limiter.shouldSend(key: "another", now: 0))
        #expect(results == [true, false, true] + Array(repeating: true, count: 8) + [false])
    }

    @Test func offlineAndCancelledRequestsAreNotReported() {
        #expect(DiagnosticsPrivacy.isExpectedNetworkCondition(URLError(.notConnectedToInternet)))
        #expect(DiagnosticsPrivacy.isExpectedNetworkCondition(CancellationError()))
        #expect(!DiagnosticsPrivacy.isExpectedNetworkCondition(URLError(.badServerResponse)))
    }

    @Test func eventScrubRemovesFreeTextFromCrashReports() {
        let event = Event(level: .fatal)
        event.message = SentryMessage(formatted: "Save CLAUDE.md failed")
        event.tags = ["artifact": "secret-skill"]
        event.extra = ["email": "jane@example.com"]
        event.user = User(userId: "jane")
        event.serverName = "Janes-MacBook-Pro"
        event.context = ["device": ["name": "Jane's MacBook", "model": "Mac15,3"], "culture": ["locale": "en_US"]]
        let exception = Exception(value: "Could not open /Users/jane/Developer/Projects/secret-project/CLAUDE.md", type: "NSInvalidArgumentException")
        let frame = Frame()
        frame.fileName = "/Users/jane/Developer/agent-vault/Sources/AgentVault/Scanner.swift"
        frame.vars = ["title": "secret-skill"]
        let stack = SentryStacktrace(frames: [frame], registers: ["x0": "0x6a616e65"])
        exception.stacktrace = stack
        event.exceptions = [exception]
        let thread = SentryThread(threadId: 1)
        thread.name = "Scan secret-project"
        event.threads = [thread]
        let crumb = Breadcrumb(level: .info, category: "ui.click")
        crumb.message = "secret-skill"
        let own = Breadcrumb(level: .info, category: "editor")
        own.message = "Saved"
        own.setData(value: 2, key: "applied")
        own.setData(value: "secret-skill", key: "artifact")
        event.breadcrumbs = [crumb, own]

        let scrubbed = CrashReporting.scrub(event)
        #expect(scrubbed.message == nil)
        #expect(scrubbed.tags == nil)
        #expect(scrubbed.extra == nil)
        #expect(scrubbed.user == nil)
        #expect(scrubbed.serverName == nil)
        let context = scrubbed.context ?? [:]
        #expect(context["culture"] == nil)
        #expect(context["device"]?["name"] == nil)
        #expect(context["device"]?["model"] as? String == "Mac15,3")
        #expect(scrubbed.exceptions?.first?.value == nil)
        #expect(scrubbed.exceptions?.first?.type == "NSInvalidArgumentException")
        #expect(scrubbed.exceptions?.first?.stacktrace?.frames.first?.fileName == "Scanner.swift")
        #expect(scrubbed.exceptions?.first?.stacktrace?.frames.first?.vars == nil)
        let registers = scrubbed.exceptions?.first?.stacktrace?.registers ?? ["x": "y"]
        #expect(registers.isEmpty)
        #expect(scrubbed.threads?.first?.name == nil)
        #expect(scrubbed.breadcrumbs?.count == 1)
        let crumbKeys = scrubbed.breadcrumbs?.first?.data.map { Array($0.keys).sorted() }
        #expect(crumbKeys == ["applied"])
    }

    @Test func ownReportsKeepTheirFixedMessageAndAllowedTags() {
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: "Save failed")
        event.fingerprint = [CrashReporting.ownEventFingerprintHead, "editor", "jane@example.com"]
        event.tags = ["area": "editor", "error_code": "3", "path": "/Users/jane/x"]
        let scrubbed = CrashReporting.scrub(event)
        #expect(scrubbed.message?.formatted == "Save failed")
        #expect(scrubbed.tags == ["area": "editor", "error_code": "3"])
        let fingerprint = scrubbed.fingerprint ?? []
        #expect(!fingerprint.joined().contains("jane@example.com"))
    }
}
