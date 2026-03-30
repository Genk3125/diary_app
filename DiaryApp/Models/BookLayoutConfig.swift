// BookLayoutConfig.swift
// Configuration for the book export / preview.
// Persisted alongside entries in DiaryStore.
// TODO: Extend with font, page size, cover design options.

import Foundation

struct BookLayoutConfig: Codable {
    var title: String
    var subtitle: String
    var sortOrder: SortOrder
    var grouping: GroupingStyle
    /// Override per-entry photo limit. nil = use plan default.
    var maxPhotosPerEntry: Int?
    /// Override per-entry video limit. nil = use plan default.
    var maxVideosPerEntry: Int?
    var includeSourceApp: Bool

    enum SortOrder: String, Codable, CaseIterable {
        case dateAscending = "date_asc"
        case dateDescending = "date_desc"

        var displayName: String {
            switch self {
            case .dateAscending:
                return "日付昇順"
            case .dateDescending:
                return "日付降順"
            }
        }
    }

    enum GroupingStyle: String, Codable, CaseIterable {
        case none = "none"
        case byMonth = "by_month"
        case byYear = "by_year"

        var displayName: String {
            switch self {
            case .none:
                return "なし"
            case .byMonth:
                return "月ごと"
            case .byYear:
                return "年ごと"
            }
        }
    }

    init(
        title: String = "My Diary",
        subtitle: String = "",
        sortOrder: SortOrder = .dateAscending,
        grouping: GroupingStyle = .byMonth,
        maxPhotosPerEntry: Int? = nil,
        maxVideosPerEntry: Int? = nil,
        includeSourceApp: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.sortOrder = sortOrder
        self.grouping = grouping
        self.maxPhotosPerEntry = maxPhotosPerEntry
        self.maxVideosPerEntry = maxVideosPerEntry
        self.includeSourceApp = includeSourceApp
    }
}
