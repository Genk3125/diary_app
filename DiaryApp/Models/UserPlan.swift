// UserPlan.swift
// Subscription plan definition.
// Digital limits and print limits are kept in sync by default.
import Foundation

enum UserPlan: String, Codable, CaseIterable {
    case free = "free"
    case pro = "pro"

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        }
    }

    // MARK: - Digital limits

    var maxPhotosPerEntry: Int {
        switch self {
        case .free: return 1
        case .pro: return 3
        }
    }

    var maxVideosPerEntry: Int {
        switch self {
        case .free: return 1
        case .pro: return 3
        }
    }

    // MARK: - Print limits
    // Kept aligned with digital limits.
    // The UI shows "最大◯枚まで反映" when an entry exceeds these limits.

    var maxPhotosInPrint: Int { maxPhotosPerEntry }
    var maxVideosInPrint: Int { maxVideosPerEntry }

    var isPro: Bool { self == .pro }
}
