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
    let gameState: GameState
    let commandQueue: [CommandInput]
    let inGameState: InGameState

    init(gameState: GameState, commandQueue: [CommandInput], inGameState: InGameState) {
        self.gameState = gameState
        self.commandQueue = commandQueue
        self.inGameState = inGameState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gameState = try container.decode(GameState.self, forKey: .gameState)
        commandQueue = try container.decodeIfPresent([CommandInput].self, forKey: .commandQueue) ?? []
        inGameState = try container.decodeIfPresent(InGameState.self, forKey: .inGameState) ?? InGameState()
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
    var opponentName: String
    var startedAt: Date
}

enum PlayerPosition: String, Codable, CaseIterable, Identifiable {
    case setter = "S"
    case outsideHitter = "OH"
    case middleBlocker = "M"
    case opposite = "OPP"
    case libero = "L"
    case defensiveSpecialist = "DS"

    var id: String { rawValue }
}

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var jerseyNumber: Int
    var firstName: String
    var lastName: String
    var displayName: String
    var positions: [PlayerPosition]
    var isActive: Bool
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

struct RosterState: Codable, Equatable {
    var players: [Player] = []
    var matchRosterEntries: [MatchRosterEntry] = []
    var lineupSlots: [LineupSlot] = []
    var playerMatchStates: [PlayerMatchState] = []

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
}
