import Foundation

public struct ReleaseHealthBuildContext: Equatable, Sendable {
    public let appVersion: String
    public let buildNumber: String
    public let bundleIdentifier: String
    public let buildEnvironment: String
    public let osVersion: String
    public let isUITesting: Bool

    public init(
        appVersion: String,
        buildNumber: String,
        bundleIdentifier: String,
        buildEnvironment: String,
        osVersion: String,
        isUITesting: Bool
    ) {
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.bundleIdentifier = bundleIdentifier
        self.buildEnvironment = buildEnvironment
        self.osVersion = osVersion
        self.isUITesting = isUITesting
    }

    public static func current(
        bundle: Bundle = .main,
        processInfo: ProcessInfo = .processInfo,
        isDebugBuild: Bool,
        isUITesting: Bool? = nil
    ) -> ReleaseHealthBuildContext {
        let info = bundle.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info["CFBundleVersion"] as? String ?? "unknown"
        let bundleID = bundle.bundleIdentifier ?? "unknown"
        let testing = isUITesting ?? processInfo.arguments.contains("-ui-testing")

        return ReleaseHealthBuildContext(
            appVersion: version,
            buildNumber: build,
            bundleIdentifier: bundleID,
            buildEnvironment: isDebugBuild ? "debug" : "release",
            osVersion: processInfo.operatingSystemVersionString,
            isUITesting: testing
        )
    }

    public var analyticsParameters: [String: Any] {
        [
            "app_version": appVersion,
            "build_number": buildNumber,
            "bundle_identifier": bundleIdentifier,
            "build_environment": buildEnvironment,
            "os_version": osVersion,
            "is_ui_testing": isUITesting ? "true" : "false"
        ]
    }
}

public enum ReleaseHealthArea: String, Sendable {
    case appLifecycle = "app_lifecycle"
    case authentication = "authentication"
    case database = "database"
    case nutrition = "nutrition"
    case workouts = "workouts"
    case healthKit = "healthkit"
    case notifications = "notifications"
    case ai = "ai"
    case release = "release"
}

public enum ReleaseHealth {
    public static let schemaVersion = "1"

    public static func configure(
        crashManager: CrashManagerProtocol,
        analyticsManager: AnalyticsManagerProtocol,
        context: ReleaseHealthBuildContext
    ) {
        crashManager.setCustomValue(schemaVersion, forKey: "release_health_schema")
        crashManager.setCustomValue(context.appVersion, forKey: "app_version")
        crashManager.setCustomValue(context.buildNumber, forKey: "build_number")
        crashManager.setCustomValue(context.bundleIdentifier, forKey: "bundle_identifier")
        crashManager.setCustomValue(context.buildEnvironment, forKey: "build_environment")
        crashManager.setCustomValue(context.osVersion, forKey: "os_version")
        crashManager.setCustomValue(context.isUITesting ? "true" : "false", forKey: "is_ui_testing")
        crashManager.log("release_health.session_started \(context.appVersion) (\(context.buildNumber))")

        analyticsManager.setUserProperty(context.appVersion, forName: "app_version")
        analyticsManager.setUserProperty(context.buildNumber, forName: "build_number")
        analyticsManager.setUserProperty(context.buildEnvironment, forName: "build_environment")
        analyticsManager.logEvent("app_session_started", parameters: context.analyticsParameters)
    }

    public static func identifyUser(
        userID: String?,
        crashManager: CrashManagerProtocol,
        analyticsManager: AnalyticsManagerProtocol
    ) {
        let safeUserID = userID ?? ""
        crashManager.setUserID(safeUserID)
        crashManager.setCustomValue(userID == nil ? "false" : "true", forKey: "is_logged_in")
        analyticsManager.setUserID(userID)
    }

    public static func recordStartupCompleted(
        duration: TimeInterval,
        crashManager: CrashManagerProtocol,
        analyticsManager: AnalyticsManagerProtocol
    ) {
        let milliseconds = max(0, Int((duration * 1_000).rounded()))
        let bucket = startupDurationBucket(milliseconds: milliseconds)

        crashManager.setCustomValue(milliseconds, forKey: "startup_duration_ms")
        crashManager.setCustomValue(bucket, forKey: "startup_duration_bucket")
        crashManager.log("release_health.startup_completed \(milliseconds)ms")

        analyticsManager.logEvent("app_startup_completed", parameters: [
            "duration_ms": milliseconds,
            "duration_bucket": bucket
        ])
    }

    public static func recordNonFatal(
        _ error: Error,
        area: ReleaseHealthArea,
        operation: String,
        metadata: [String: Any] = [:],
        crashManager: CrashManagerProtocol,
        analyticsManager: AnalyticsManagerProtocol? = nil
    ) {
        var userInfo = sanitized(metadata)
        userInfo["release_health_area"] = area.rawValue
        userInfo["release_health_operation"] = operation
        userInfo["release_health_schema"] = schemaVersion

        crashManager.record(error: error, additionalUserInfo: userInfo)
        crashManager.log("release_health.nonfatal \(area.rawValue).\(operation)")

        analyticsManager?.logEvent("nonfatal_error_recorded", parameters: [
            "area": area.rawValue,
            "operation": operation
        ])
    }

    public static func startupDurationBucket(milliseconds: Int) -> String {
        switch milliseconds {
        case ..<500:
            return "under_500ms"
        case ..<1_000:
            return "500ms_to_1s"
        case ..<2_000:
            return "1s_to_2s"
        case ..<4_000:
            return "2s_to_4s"
        default:
            return "over_4s"
        }
    }

    private static func sanitized(_ metadata: [String: Any]) -> [String: Any] {
        metadata.reduce(into: [:]) { result, pair in
            switch pair.value {
            case let value as String:
                result[pair.key] = value
            case let value as Int:
                result[pair.key] = value
            case let value as Double:
                result[pair.key] = value
            case let value as Bool:
                result[pair.key] = value ? "true" : "false"
            default:
                result[pair.key] = String(describing: type(of: pair.value))
            }
        }
    }
}
