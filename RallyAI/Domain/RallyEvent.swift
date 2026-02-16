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
    
    let setNumber: Int
    let playerNumber: Int?
    let action: Action
    let pointAwardedTo: TeamSide?
    let needsReview: Bool
    let rawText: String
    
    static func fromBackend(
        _ backend: BackendParsedEvent, //DTO's are unstable and the domain should not depend on backend naming and structure
        setNumber: Int,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) -> RallyEvent {
        let action = Action(rawValue: backend.event) ?? .unknown
        let side = backend.pointAwardedTo.flatMap{ TeamSide(rawValue: $0)}
        
        return RallyEvent(
            id: id,
            createdAt: createdAt,
            setNumber: setNumber,
            playerNumber: backend.playerNumber,
            action: action,
            pointAwardedTo: side,
            needsReview: backend.needsReview,
            rawText: backend.rawText
        )
    }
}
