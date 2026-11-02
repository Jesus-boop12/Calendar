import Foundation
import SwiftData

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var symbolName: String? {
        switch self {
        case .none: return nil
        case .low: return "exclamationmark"
        case .medium: return "exclamationmark.2"
        case .high: return "exclamationmark.3"
        }
    }
}

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String
    var dueDate: Date?
    var isCompleted: Bool
    var completedAt: Date?
    var createdAt: Date
    var priorityRaw: Int
    var createdByVoice: Bool

    init(title: String,
         details: String = "",
         dueDate: Date? = nil,
         priority: TaskPriority = .none,
         createdByVoice: Bool = false) {
        self.id = UUID()
        self.title = title
        self.details = details
        self.dueDate = dueDate
        self.isCompleted = false
        self.completedAt = nil
        self.createdAt = Date()
        self.priorityRaw = priority.rawValue
        self.createdByVoice = createdByVoice
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    /// Identifier used for the local notification tied to this task.
    var notificationIdentifier: String { "task-\(id.uuidString)" }

    var isOverdue: Bool {
        guard let dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }

    func markCompleted(_ completed: Bool) {
        isCompleted = completed
        completedAt = completed ? Date() : nil
    }
}
