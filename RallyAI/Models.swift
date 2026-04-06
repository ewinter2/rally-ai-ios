//
//  Models.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/9/26.
//

import Foundation

// What is sent to the backend
// Codable allows easy conversion of data to and from JSON data
struct ParseTextRequest: Codable, Equatable {
    let text: String
    let setNumber: Int
    let teamId: UUID?
    let matchId: UUID?
}

// Mirrors the backend response
struct BackendParsedEvent: Codable, Equatable {
    let playerNumber: Int?
    let event: String
    let pointAwardedTo: String?
    let needsReview: Bool
    let rawText: String
    let playerId: UUID?
    let teamId: UUID?
    let matchId: UUID?
}

enum TeamSide: String, Codable {
    case us
    case them
}

// Maps backend action strings into typed swift values
// .unknown to handle unexpected returns from backend rather than crashing the app
enum Action: String, Codable {
    case serve = "SERVE"
    case ace = "ACE"
    case serveError = "SERVE_ERROR"
    case hitAttempt = "HIT_ATTEMPT"
    case kill = "KILL"
    case hitError = "HIT_ERROR"
    case goodPass = "GOOD_PASS"
    case badPass = "BAD_PASS"
    case passError = "PASS_ERROR"
    case block = "BLOCK"
    case blockAssist = "BLOCK_ASSIST"
    case blockError = "BLOCK_ERROR"
    case assist = "ASSIST"
    case ballHandlingError = "BALL_HANDLING_ERROR"
    case dig = "DIG"
    case digError = "DIG_ERROR"
    case pointUs = "POINT_US"
    case pointThem = "POINT_THEM"
    case unknown = "UNKNOWN"
}

enum CommandSource: String, Codable {
    case text
    case voice
}

enum CommandStatus: String, Codable {
    case captured
    case parsing
    case needsReview
    case accepted
    case committed
    case failed
}

struct CommandInput: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let teamID: UUID
    let matchID: UUID
    let source: CommandSource
    let setNumber: Int
    var rawText: String
    var status: CommandStatus
    var parsedEvent: BackendParsedEvent?
    var errorMessage: String?

    init(
        id: UUID,
        createdAt: Date,
        teamID: UUID,
        matchID: UUID,
        source: CommandSource,
        setNumber: Int,
        rawText: String,
        status: CommandStatus,
        parsedEvent: BackendParsedEvent?,
        errorMessage: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.teamID = teamID
        self.matchID = matchID
        self.source = source
        self.setNumber = setNumber
        self.rawText = rawText
        self.status = status
        self.parsedEvent = parsedEvent
        self.errorMessage = errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        teamID = try container.decodeIfPresent(UUID.self, forKey: .teamID) ?? UUID()
        matchID = try container.decodeIfPresent(UUID.self, forKey: .matchID) ?? UUID()
        source = try container.decode(CommandSource.self, forKey: .source)
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        rawText = try container.decode(String.self, forKey: .rawText)
        status = try container.decode(CommandStatus.self, forKey: .status)
        parsedEvent = try container.decodeIfPresent(BackendParsedEvent.self, forKey: .parsedEvent)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
}

struct PersistedAppState: Codable {
    let appState: AppState

    private enum CodingKeys: String, CodingKey {
        case appState
        case gameState  // legacy: used only in backward-compatible decoder path
        case inGameState
        case rosterState
    }

    init(appState: AppState) {
        self.appState = appState
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appState, forKey: .appState)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let appState = try container.decodeIfPresent(AppState.self, forKey: .appState) {
            self.appState = appState
            return
        }

        // Backward-compatible migration from the previous single-match persisted shape.
        let gameState = try container.decode(GameState.self, forKey: .gameState)
        let inGameState = try container.decodeIfPresent(InGameState.self, forKey: .inGameState) ?? InGameState()
        let rosterState = try container.decodeIfPresent(RosterState.self, forKey: .rosterState) ?? RosterState()
        let session = MatchSession(
            id: gameState.matchID,
            match: Match(
                id: gameState.matchID,
                teamID: gameState.teamID,
                opponentName: "",
                startedAt: Date()
            ),
            gameState: gameState,
            rosterState: rosterState,
            inGameState: inGameState,
            createdAt: Date(),
            updatedAt: Date()
        )
        self.appState = AppState(activeMatchID: session.id, matches: [session])
    }
}

// Roster and match entities use stable UUID identity.
// Jersey number remains editable and is not the primary key.
struct Team: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
}

struct Match: Identifiable, Codable, Equatable {
    let id: UUID
    let teamID: UUID
    var matchName: String       // User-editable label, e.g. "Regionals Game 1"
    var ourTeamName: String     // "Us" team display name
    var opponentName: String    // "Them" team display name
    var startedAt: Date
    var completedAt: Date?      // Set when coach finalises the match; nil = in progress

    var isCompleted: Bool { completedAt != nil }

    init(
        id: UUID,
        teamID: UUID,
        matchName: String = "",
        ourTeamName: String = "",
        opponentName: String = "",
        startedAt: Date,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.teamID = teamID
        self.matchName = matchName
        self.ourTeamName = ourTeamName
        self.opponentName = opponentName
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,   forKey: .id)
        teamID       = try c.decode(UUID.self,   forKey: .teamID)
        matchName    = try c.decodeIfPresent(String.self, forKey: .matchName)    ?? ""
        ourTeamName  = try c.decodeIfPresent(String.self, forKey: .ourTeamName) ?? ""
        opponentName = try c.decodeIfPresent(String.self, forKey: .opponentName) ?? ""
        startedAt    = try c.decode(Date.self,   forKey: .startedAt)
        completedAt  = try c.decodeIfPresent(Date.self,   forKey: .completedAt)
    }
}

struct MatchSession: Identifiable, Codable, Equatable {
    let id: UUID
    var match: Match
    var gameState: GameState
    var rosterState: RosterState
    var inGameState: InGameState
    var createdAt: Date
    var updatedAt: Date
}

struct AppState: Codable, Equatable {
    var activeMatchID: UUID?
    var matches: [MatchSession] = []
}

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var jerseyNumber: Int
    var firstName: String
    var lastName: String
    var displayName: String
    var isActive: Bool

    init(
        id: UUID,
        jerseyNumber: Int,
        firstName: String,
        lastName: String,
        displayName: String,
        isActive: Bool
    ) {
        self.id = id
        self.jerseyNumber = jerseyNumber
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
        self.isActive = isActive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        jerseyNumber = try container.decode(Int.self, forKey: .jerseyNumber)
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName) ?? ""
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName) ?? ""
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }
}

struct MatchRosterEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let matchID: UUID
    let playerID: UUID
    var isAvailable: Bool
    var isStarter: Bool
}

struct LineupSlot: Identifiable, Codable, Equatable {
    let id: UUID
    let matchID: UUID
    let setNumber: Int
    var rotationIndex: Int
    var playerID: UUID?
    var isLiberoSlot: Bool

    var hasValidRotationIndex: Bool {
        (1...6).contains(rotationIndex)
    }
}

struct PlayerMatchState: Identifiable, Codable, Equatable {
    let id: UUID
    let matchID: UUID
    let playerID: UUID
    var isOnCourt: Bool
    var isLibero: Bool
    var enteredAt: Date?
    var exitedAt: Date?
    var currentRotationIndex: Int?
    var availableForSubstitution: Bool
}

struct DesignatedLiberoSlot: Identifiable, Codable, Equatable {
    let slotNumber: Int
    var playerID: UUID?

    var id: Int { slotNumber }
}

struct RosterState: Codable, Equatable {
    var players: [Player] = []
    var matchRosterEntries: [MatchRosterEntry] = []
    var lineupSlots: [LineupSlot] = []
    var playerMatchStates: [PlayerMatchState] = []
    var designatedLiberoSlots: [DesignatedLiberoSlot] = [
        DesignatedLiberoSlot(slotNumber: 1, playerID: nil),
        DesignatedLiberoSlot(slotNumber: 2, playerID: nil)
    ]

    func playerByID(_ id: UUID) -> Player? {
        players.first(where: { $0.id == id })
    }

    func playerByJerseyNumber(_ jerseyNumber: Int) -> Player? {
        players.first(where: { $0.jerseyNumber == jerseyNumber })
    }

    func onCourtPlayers(matchID: UUID) -> [Player] {
        let onCourtIDs = Set(
            playerMatchStates
                .filter { $0.matchID == matchID && $0.isOnCourt }
                .map(\.playerID)
        )

        return players.filter { onCourtIDs.contains($0.id) }
    }

    func currentLineup(matchID: UUID, setNumber: Int) -> [LineupSlot] {
        lineupSlots
            .filter { $0.matchID == matchID && $0.setNumber == setNumber }
            .sorted { $0.rotationIndex < $1.rotationIndex }
    }

    mutating func upsertPlayer(_ player: Player) {
        if let index = players.firstIndex(where: { $0.id == player.id }) {
            players[index] = player
        } else {
            players.append(player)
        }
    }

    mutating func removePlayer(_ playerID: UUID) {
        players.removeAll { $0.id == playerID }
        matchRosterEntries.removeAll { $0.playerID == playerID }
        lineupSlots.removeAll { $0.playerID == playerID }
        playerMatchStates.removeAll { $0.playerID == playerID }
        for index in designatedLiberoSlots.indices where designatedLiberoSlots[index].playerID == playerID {
            designatedLiberoSlots[index].playerID = nil
        }
    }

    mutating func setDesignatedLibero(
        _ playerID: UUID?,
        for slotNumber: Int
    ) {
        guard let index = designatedLiberoSlots.firstIndex(where: { $0.slotNumber == slotNumber }) else { return }

        for otherIndex in designatedLiberoSlots.indices where otherIndex != index && designatedLiberoSlots[otherIndex].playerID == playerID {
            designatedLiberoSlots[otherIndex].playerID = nil
        }

        designatedLiberoSlots[index].playerID = playerID
    }

    mutating func ensureMatchRosterEntries(
        for matchID: UUID,
        availablePlayerIDs: [UUID]
    ) {
        let availableSet = Set(availablePlayerIDs)

        for playerID in availableSet {
            guard !matchRosterEntries.contains(where: { $0.matchID == matchID && $0.playerID == playerID }) else {
                continue
            }

            matchRosterEntries.append(
                MatchRosterEntry(
                    id: UUID(),
                    matchID: matchID,
                    playerID: playerID,
                    isAvailable: true,
                    isStarter: false
                )
            )
        }

        for index in matchRosterEntries.indices where matchRosterEntries[index].matchID == matchID {
            matchRosterEntries[index].isAvailable = availableSet.contains(matchRosterEntries[index].playerID)
        }
    }

    mutating func syncCurrentSetState(
        matchID: UUID,
        setNumber: Int,
        rotationSlotAssignments: [Int: UUID],
        activeLiberoAssignments: [Int: UUID],
        playerStatesByID: [UUID: PlayerMatchState]
    ) {
        lineupSlots.removeAll { $0.matchID == matchID && $0.setNumber == setNumber }
        playerMatchStates.removeAll { $0.matchID == matchID }

        let starterIDs = Set(rotationSlotAssignments.values)
        let availablePlayerIDs = players
            .filter(\.isActive)
            .map(\.id)

        ensureMatchRosterEntries(for: matchID, availablePlayerIDs: availablePlayerIDs)

        for rotationIndex in (1...6) {
            lineupSlots.append(
                LineupSlot(
                    id: UUID(),
                    matchID: matchID,
                    setNumber: setNumber,
                    rotationIndex: rotationIndex,
                    playerID: rotationSlotAssignments[rotationIndex],
                    isLiberoSlot: activeLiberoAssignments[rotationIndex] != nil
                )
            )
        }

        playerMatchStates = Array(playerStatesByID.values)

        for index in matchRosterEntries.indices where matchRosterEntries[index].matchID == matchID {
            matchRosterEntries[index].isStarter = starterIDs.contains(matchRosterEntries[index].playerID)
        }
    }
}
