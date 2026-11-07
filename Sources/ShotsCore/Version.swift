import Foundation

/// Single source of truth for the release version, used by the CLI and by the
/// build scripts (which grep this file), so they can never drift apart.
public enum ShotsVersion {
    public static let current = "1.2.0"
}
