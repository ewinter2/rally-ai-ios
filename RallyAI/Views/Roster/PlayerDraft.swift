import Foundation

struct PlayerDraft {
    var jerseyNumber: Int = 0
    var firstName: String = ""
    var lastName: String = ""
    var displayName: String = ""
    var isActive: Bool = true

    init() {}

    init(player: Player) {
        jerseyNumber = player.jerseyNumber
        firstName = player.firstName
        lastName = player.lastName
        displayName = player.displayName
        isActive = player.isActive
    }

    var isValid: Bool {
        jerseyNumber > 0 && !resolvedDisplayName.isEmpty
    }

    var resolvedDisplayName: String {
        let explicit = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        return "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toPlayer(existingID: UUID?) -> Player {
        Player(
            id: existingID ?? UUID(),
            jerseyNumber: jerseyNumber,
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: resolvedDisplayName,
            isActive: isActive
        )
    }
}
