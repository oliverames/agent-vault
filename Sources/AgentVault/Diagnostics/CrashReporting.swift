import Foundation
import os.log
import Sentry

private let log = Logger(subsystem: "com.oliverames.AgentVault", category: "CrashReporting")

/// Crash and error reporting through Sentry.
///
/// A build without `AgentVaultSentryDSN` in its Info.plist never starts the
/// SDK. Only release builds carry one: `scripts/build-app.sh` writes it into
/// the bundle from the `SENTRY_DSN` environment variable (a GitHub Actions
/// secret in the signed release workflow) or from 1Password, so it is not in
/// Git. Settings > Privacy > Share Crash Reports turns reporting off; it is on
/// by default in those builds. Debug builds report only when launched with
/// `-AgentVaultCrashReports YES` or `-AgentVaultSentryTest message|error|crash`.
///
/// What is sent is an allowlist enforced in `beforeSend`, not a text filter:
/// - Crash reports and uncaught exceptions: the exception type and mechanism,
///   and each thread's stack frames (function, image, code addresses, and a
///   path reduced to its place inside the app, a macOS system path, or a file
///   name). Exception messages, thread names, register values, source
///   context, frame variables, extra data, the request, the transaction and
///   every context outside the allowlist (including an error's user info) are
///   removed.
/// - Failed saves, exports, backups and restores built from fixed fields: the
///   area, a fixed message, and the error's domain and numeric code. At most
///   one per kind an hour and ten per run.
/// - App version and build, macOS version, and the Mac's model and architecture.
///
/// Never sent: file contents, artifact names, scan roots, repository or other
/// paths, inventory data, secrets found in scanned files, the IP address (no
/// `sendDefaultPii`, and the project discards IP addresses), sessions,
/// performance traces, network requests, screenshots or user interface details.
enum CrashReporting {
    static let preferenceKey = "AgentVaultShareCrashReports"
    private static let dsnKey = "AgentVaultSentryDSN"
    static let ownEventFingerprintHead = "agentvault-report"
    static let releasePrefix = "com.oliverames.AgentVault"

    static var preferences: UserDefaults { .standard }

    /// The validated DSN this build carries, or nil when reporting isn't built in.
    static let dsn: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: dsnKey) as? String,
              !value.isEmpty, !value.contains("$("),
              let url = URLComponents(string: value), url.scheme == "https",
              url.host?.hasSuffix(".sentry.io") == true, url.user?.isEmpty == false,
              url.password == nil, url.query == nil else { return nil }
        return value
    }()

    static var isConfigured: Bool { dsn != nil }

    /// On unless the person turned it off.
    static var isPreferenceOn: Bool {
        preferences.object(forKey: preferenceKey) as? Bool ?? true
    }

    /// Starts reporting when the build has a DSN and the person hasn't turned
    /// it off. Call first thing at launch.
    static func start() {
        guard let dsn, isPreferenceOn, !SentrySDK.isEnabled else { return }
        #if DEBUG
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "AgentVaultCrashReports") || defaults.string(forKey: "AgentVaultSentryTest") != nil else {
            return
        }
        #endif
        SentrySDK.start(options: options(dsn: dsn))
        log.info("Crash reporting started")
    }

    /// Share Crash Reports. Takes effect at once: off closes the SDK and its
    /// crash handler, on starts it again.
    static func setEnabled(_ enabled: Bool) {
        preferences.set(enabled, forKey: preferenceKey)
        if enabled { start() } else if SentrySDK.isEnabled { SentrySDK.close() }
    }

    // MARK: Reports

    /// A non-fatal failure worth fixing. Only the error's domain and numeric
    /// code go with it: its description can name a file or a path.
    static func report(_ area: DiagnosticsArea, _ message: StaticString, error: any Error) {
        guard SentrySDK.isEnabled, !DiagnosticsPrivacy.isExpectedNetworkCondition(error) else { return }
        let nsError = error as NSError
        let text = "\(message)"
        let parts = [area.rawValue, text, nsError.domain, String(nsError.code)]
        guard DiagnosticsPrivacy.shouldSend(key: parts.joined(separator: "|")) else { return }
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: text)
        event.tags = [
            "area": area.rawValue,
            "error_domain": nsError.domain,
            "error_code": String(nsError.code),
        ]
        event.fingerprint = [ownEventFingerprintHead] + parts
        SentrySDK.capture(event: event)
    }

    // MARK: Options

    private static func options(dsn: String) -> Options {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "0"
        let build = info["CFBundleVersion"] as? String ?? "0"
        let options = Options()
        options.dsn = dsn
        // Matches scripts/package-release.sh, so uploaded dSYMs attach to the release.
        options.releaseName = "\(releasePrefix)@\(version)+\(build)"
        options.dist = build
        #if DEBUG
        options.environment = "debug"
        #else
        options.environment = "production"
        #endif
        options.debug = false
        options.sendDefaultPii = false
        options.enableCrashHandler = true
        options.enableUncaughtNSExceptionReporting = true
        // No sessions (they carry an installation identifier), tracing,
        // network capture, automatic breadcrumbs, hangs or MetricKit.
        options.enableAutoSessionTracking = false
        options.tracesSampleRate = 0
        options.enableAutoPerformanceTracing = false
        options.enableNetworkTracking = false
        options.enableNetworkBreadcrumbs = false
        options.enableCaptureFailedRequests = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
        options.enableAutoBreadcrumbTracking = false
        options.enableSwizzling = false
        options.enableAppHangTracking = false
        options.enableMetricKit = false
        options.enableLogs = false
        options.attachStacktrace = false
        options.maxAttachmentSize = 0
        options.tracePropagationTargets = []
        options.failedRequestTargets = []
        // Counts of dropped reports and why, with no contents.
        options.sendClientReports = true
        options.beforeBreadcrumb = { crumb in
            filter(crumb)
        }
        options.beforeSend = { event in
            guard isPreferenceOn else { return nil }
            return scrub(event)
        }
        return options
    }

    /// Keep only the app's own breadcrumbs, with counts and a cleaned message.
    static func filter(_ crumb: Breadcrumb) -> Breadcrumb? {
        guard DiagnosticsPrivacy.isAllowedBreadcrumb(category: crumb.category) else { return nil }
        crumb.message = crumb.message.map { DiagnosticsPrivacy.scrub($0) }
        let data = crumb.data ?? [:]
        let numbers = DiagnosticsPrivacy.filterBreadcrumbData(data)
        for key in data.keys where numbers[key] == nil { crumb.setData(value: nil, key: key) }
        return crumb
    }

    /// The running app's bundle, used to reduce frame and image paths.
    static let bundlePath = Bundle.main.bundlePath

    /// Allowlist every event before it leaves the Mac, including crash reports
    /// written by an earlier run. Free-text fields the SDK fills are removed,
    /// not filtered.
    static func scrub(_ event: Event) -> Event {
        event.serverName = nil
        event.user = nil
        event.extra = nil
        event.transaction = nil
        event.modules = nil
        event.request = nil
        event.stacktrace = nil
        event.context = event.context.flatMap {
            let kept = DiagnosticsPrivacy.filterContexts($0)
            return kept.isEmpty ? nil : kept
        }
        if event.fingerprint?.first == ownEventFingerprintHead {
            event.message = event.message.map { SentryMessage(formatted: DiagnosticsPrivacy.scrub($0.formatted)) }
            event.tags = event.tags.map(DiagnosticsPrivacy.filterTags)
            // Fingerprints are sent too; they hold the error domain and code.
            event.fingerprint = event.fingerprint?.map { DiagnosticsPrivacy.scrub($0) }
        } else {
            event.message = nil
            event.tags = nil
            event.fingerprint = nil
        }
        for exception in event.exceptions ?? [] {
            exception.value = nil
            exception.type = exception.type.map { DiagnosticsPrivacy.scrub($0) }
            if let mechanism = exception.mechanism {
                mechanism.desc = nil
                mechanism.data = nil
                mechanism.helpLink = nil
                mechanism.type = DiagnosticsPrivacy.scrub(mechanism.type)
            }
            reduceFrames(exception.stacktrace)
        }
        for thread in event.threads ?? [] {
            thread.name = nil
            reduceFrames(thread.stacktrace)
        }
        for image in event.debugMeta ?? [] {
            image.codeFile = image.codeFile.map { DiagnosticsPrivacy.reducePath($0, bundlePath: bundlePath) }
        }
        event.breadcrumbs = event.breadcrumbs?.compactMap(filter)
        return event
    }

    /// Keep function names, images and code addresses; reduce paths; drop
    /// register values (they can hold short strings), source context and variables.
    private static func reduceFrames(_ stacktrace: SentryStacktrace?) {
        stacktrace?.registers = [:]
        for frame in stacktrace?.frames ?? [] {
            frame.package = frame.package.map { DiagnosticsPrivacy.reducePath($0, bundlePath: bundlePath) }
            frame.fileName = frame.fileName.map { DiagnosticsPrivacy.reducePath($0, bundlePath: bundlePath) }
            frame.contextLine = nil
            frame.preContext = nil
            frame.postContext = nil
            frame.vars = nil
        }
    }

    // MARK: Debug checks

    #if DEBUG
    /// Handles `-AgentVaultSentryTest message|error|crash` and returns true when
    /// the process should exit without starting the app, so a delivery check
    /// never scans or reads a file. The
    /// breadcrumb and error carry synthetic private text, so the received event
    /// shows whether scrubbing worked: none of it should arrive. `message` also
    /// uploads a crash report left by an earlier `crash` run.
    static func runDebugTestIfRequested() -> Bool {
        guard let kind = UserDefaults.standard.string(forKey: "AgentVaultSentryTest") else { return false }
        guard SentrySDK.isEnabled else {
            log.notice("Sentry test skipped: no DSN in this build, or reporting is off")
            return true
        }
        let crumb = Breadcrumb(level: .info, category: DiagnosticsArea.test.rawValue)
        crumb.message = "Scrub check for \"secret-project-skill\" in /Users/jane/Developer/Projects/secret-project/CLAUDE.md /opt/homebrew/lib/acme-mcp sk-ant-api03-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA jane@example.com https://github.com/jane/secret-project"
        crumb.setData(value: 3, key: "count")
        crumb.setData(value: "secret-project-skill", key: "artifactName")
        crumb.setData(value: "/Users/jane/Developer/Projects/secret-project", key: "root")
        SentrySDK.addBreadcrumb(crumb)
        switch kind {
        case "crash":
            SentrySDK.crash()
        case "error":
            let error = NSError(domain: "AgentVault.DiagnosticsCheck", code: 7, userInfo: [
                NSLocalizedDescriptionKey: "Could not save /Users/jane/Developer/Projects/secret-project/CLAUDE.md",
                NSFilePathErrorKey: "/Users/jane/Developer/Projects/secret-project/CLAUDE.md",
            ])
            report(.test, "Agent Vault diagnostics check (error)", error: error)
        default:
            let event = Event(level: .info)
            event.message = SentryMessage(formatted: "Agent Vault diagnostics check")
            event.fingerprint = [ownEventFingerprintHead, "delivery-test"]
            event.tags = ["area": DiagnosticsArea.test.rawValue, "delivery_test": "true"]
            let eventID = SentrySDK.capture(event: event)
            print("Sentry test event: \(eventID.sentryIdString)")
        }
        SentrySDK.flush(timeout: 10)
        return true
    }
    #endif
}
