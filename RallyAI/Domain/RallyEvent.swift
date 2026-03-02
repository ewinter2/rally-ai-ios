//
//  RallyEvent.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/15/26.
//

import Foundation

struct RallyEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    let commandID: UUID?
    let teamID: UUID
    let matchID: UUID
    
    let setNumber: Int
    let playerID: UUID?
    let playerNumber: Int?
    let action: Action
    let backendEventRaw: String
    let pointAwardedTo: TeamSide?
    let needsReview: Bool
    let rawText: String

    init(
        id: UUID,
        createdAt: Date,
        commandID: UUID?,
        teamID: UUID,
        matchID: UUID,
        setNumber: Int,
        playerID: UUID?,
        playerNumber: Int?,
        action: Action,
        backendEventRaw: String,
        pointAwardedTo: TeamSide?,
        needsReview: Bool,
        rawText: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.commandID = commandID
        self.teamID = teamID
        self.matchID = matchID
        self.setNumber = setNumber
        self.playerID = playerID
        self.playerNumber = playerNumber
        self.action = action
        self.backendEventRaw = backendEventRaw
        self.pointAwardedTo = pointAwardedTo
        self.needsReview = needsReview
        self.rawText = rawText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        commandID = try container.decodeIfPresent(UUID.self, forKey: .commandID)
        teamID = try container.decodeIfPresent(UUID.self, forKey: .teamID) ?? UUID()
        matchID = try container.decodeIfPresent(UUID.self, forKey: .matchID) ?? UUID()
        setNumber = try container.decode(Int.self, forKey: .setNumber)
        playerID = try container.decodeIfPresent(UUID.self, forKey: .playerID)
        playerNumber = try container.decodeIfPresent(Int.self, forKey: .playerNumber)
        action = try container.decode(Action.self, forKey: .action)
        backendEventRaw = try container.decodeIfPresent(String.self, forKey: .backendEventRaw) ?? action.rawValue
        pointAwardedTo = try container.decodeIfPresent(TeamSide.self, forKey: .pointAwardedTo)
        needsReview = try container.decode(Bool.self, forKey: .needsReview)
        rawText = try container.decode(String.self, forKey: .rawText)
    }
    
    static func fromBackend(
        _ backend: BackendParsedEvent,
        teamID: UUID,
        matchID: UUID,
        setNumber: Int,
        playerID: UUID? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        commandID: UUID? = nil
    ) -> RallyEvent {
        let action = Action(rawValue: backend.event.uppercased()) ?? .unknown
        let side = backend.pointAwardedTo
            .map { $0.lowercased() }
            .flatMap { TeamSide(rawValue: $0) }
        let resolvedTeamID = backend.teamId ?? teamID
        let resolvedMatchID = backend.matchId ?? matchID
        let resolvedPlayerID = backend.playerId ?? playerID
        
        return RallyEvent(
            id: id,
            createdAt: createdAt,
            commandID: commandID,
            teamID: resolvedTeamID,
            matchID: resolvedMatchID,
            setNumber: setNumber,
            playerID: resolvedPlayerID,
            playerNumber: backend.playerNumber,
            action: action,
            backendEventRaw: backend.event,
            pointAwardedTo: side,
            needsReview: backend.needsReview,
            rawText: backend.rawText
        )
    }
}
