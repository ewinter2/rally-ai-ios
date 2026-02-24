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
    
    let setNumber: Int
    let playerNumber: Int?
    let action: Action
    let pointAwardedTo: TeamSide?
    let needsReview: Bool
    let rawText: String
    
    static func fromBackend(
        _ backend: BackendParsedEvent,
        setNumber: Int,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        commandID: UUID? = nil
    ) -> RallyEvent {
        let action = Action(rawValue: backend.event.uppercased()) ?? .unknown
        let side = backend.pointAwardedTo
            .map { $0.lowercased() }
            .flatMap { TeamSide(rawValue: $0) }
        
        return RallyEvent(
            id: id,
            createdAt: createdAt,
            commandID: commandID,
            setNumber: setNumber,
            playerNumber: backend.playerNumber,
            action: action,
            pointAwardedTo: side,
            needsReview: backend.needsReview,
            rawText: backend.rawText
        )
    }
}
