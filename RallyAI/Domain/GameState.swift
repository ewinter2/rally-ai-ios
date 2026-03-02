//
//  GameState.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/15/26.
//

import Foundation

struct Score: Codable, Equatable {
    var us: Int = 0
    var them: Int = 0
}

struct GameState: Codable, Equatable {
    var teamID: UUID = UUID()
    var matchID: UUID = UUID()
    var currentSetNumber: Int = 1
    var events: [RallyEvent] = []
    
    var score = Score()

    init(
        teamID: UUID = UUID(),
        matchID: UUID = UUID(),
        currentSetNumber: Int = 1,
        events: [RallyEvent] = [],
        score: Score = Score()
    ) {
        self.teamID = teamID
        self.matchID = matchID
        self.currentSetNumber = currentSetNumber
        self.events = events
        self.score = score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamID = try container.decodeIfPresent(UUID.self, forKey: .teamID) ?? UUID()
        matchID = try container.decodeIfPresent(UUID.self, forKey: .matchID) ?? UUID()
        currentSetNumber = try container.decodeIfPresent(Int.self, forKey: .currentSetNumber) ?? 1
        events = try container.decodeIfPresent([RallyEvent].self, forKey: .events) ?? []
        score = try container.decodeIfPresent(Score.self, forKey: .score) ?? Score()
    }
    
    mutating func apply(_ action: GameAction) {
        switch action {
        case .addEvent(let event):
            events.append(event)
            rebuildScoreForCurrentSet()
            
        case .deleteEvent(let id):
            events.removeAll { $0.id == id }
            rebuildScoreForCurrentSet()
        
        case .replaceEvent(let id, let newEvent):
            if let idx = events.firstIndex(where: {$0.id == id}) {
                let old = events[idx]
                events[idx] = RallyEvent(
                    id: old.id,
                    createdAt: old.createdAt,
                    commandID: old.commandID,
                    teamID: old.teamID,
                    matchID: old.matchID,
                    setNumber: newEvent.setNumber,
                    playerID: old.playerID ?? newEvent.playerID,
                    playerNumber: newEvent.playerNumber,
                    action: newEvent.action,
                    backendEventRaw: newEvent.backendEventRaw,
                    pointAwardedTo: newEvent.pointAwardedTo,
                    needsReview: newEvent.needsReview,
                    rawText: newEvent.rawText
                )
            }
            rebuildScoreForCurrentSet()
            
        case .startNewSet:
            currentSetNumber += 1
            rebuildScoreForCurrentSet()
            
        case .manualScore(let us, let them):
            score.us = max(0, us)
            score.them = max(0, them)
        
        }
    }
    
    mutating func rebuildScoreForCurrentSet() {
        score = Score()
        
        let setEvents = events.filter {$0.setNumber == currentSetNumber}
        for e in setEvents {
            guard let side = e.pointAwardedTo else { continue }
            if side == .us {
                score.us += 1
            }
            else {
                score.them += 1
            }
        }
    }
}
