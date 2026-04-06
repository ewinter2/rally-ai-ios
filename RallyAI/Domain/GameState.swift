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

struct ScoreAdjustment: Codable, Equatable {
    var us: Int = 0
    var them: Int = 0
}

struct GameState: Codable, Equatable {
    var teamID: UUID = UUID()
    var matchID: UUID = UUID()
    var currentSetNumber: Int = 1
    var events: [RallyEvent] = []
    var currentSetScoreAdjustment: ScoreAdjustment = ScoreAdjustment()
    /// Final (adjusted) score saved for each completed set keyed by set number.
    var completedSetScores: [Int: Score] = [:]

    var score = Score()

    init(
        teamID: UUID = UUID(),
        matchID: UUID = UUID(),
        currentSetNumber: Int = 1,
        events: [RallyEvent] = [],
        currentSetScoreAdjustment: ScoreAdjustment = ScoreAdjustment(),
        completedSetScores: [Int: Score] = [:],
        score: Score = Score()
    ) {
        self.teamID = teamID
        self.matchID = matchID
        self.currentSetNumber = currentSetNumber
        self.events = events
        self.currentSetScoreAdjustment = currentSetScoreAdjustment
        self.completedSetScores = completedSetScores
        self.score = score
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teamID = try container.decodeIfPresent(UUID.self, forKey: .teamID) ?? UUID()
        matchID = try container.decodeIfPresent(UUID.self, forKey: .matchID) ?? UUID()
        currentSetNumber = try container.decodeIfPresent(Int.self, forKey: .currentSetNumber) ?? 1
        events = try container.decodeIfPresent([RallyEvent].self, forKey: .events) ?? []
        currentSetScoreAdjustment = try container.decodeIfPresent(ScoreAdjustment.self, forKey: .currentSetScoreAdjustment) ?? ScoreAdjustment()
        completedSetScores = try container.decodeIfPresent([Int: Score].self, forKey: .completedSetScores) ?? [:]
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
            completedSetScores[currentSetNumber] = score   // snapshot final score before reset
            currentSetNumber += 1
            currentSetScoreAdjustment = ScoreAdjustment()
            rebuildScoreForCurrentSet()
            
        case .manualScore(let us, let them):
            let derived = derivedScoreForCurrentSet()
            currentSetScoreAdjustment = ScoreAdjustment(
                us: max(0, us) - derived.us,
                them: max(0, them) - derived.them
            )
            rebuildScoreForCurrentSet()
        
        }
    }
    
    private func derivedScoreForCurrentSet() -> Score {
        var derived = Score()
        let setEvents = events.filter { $0.setNumber == currentSetNumber }

        for event in setEvents {
            guard let side = event.pointAwardedTo else { continue }
            if side == .us {
                derived.us += 1
            } else {
                derived.them += 1
            }
        }

        return derived
    }

    mutating func rebuildScoreForCurrentSet() {
        let derived = derivedScoreForCurrentSet()

        score.us = max(0, derived.us + currentSetScoreAdjustment.us)
        score.them = max(0, derived.them + currentSetScoreAdjustment.them)
    }

    /// The authoritative score for any set number.
    /// For completed sets uses the saved snapshot (includes manual adjustments).
    /// For the current live set uses the running score.
    /// Falls back to event-derived score for old data that predates snapshotting.
    func scoreForSet(_ setNumber: Int) -> Score {
        if setNumber == currentSetNumber { return score }
        return completedSetScores[setNumber] ?? derivedScore(forSet: setNumber)
    }

    func derivedScore(forSet setNumber: Int) -> Score {
        var derived = Score()
        let setEvents = events.filter { $0.setNumber == setNumber }

        for event in setEvents {
            guard let side = event.pointAwardedTo else { continue }
            if side == .us {
                derived.us += 1
            } else {
                derived.them += 1
            }
        }

        return derived
    }

    func setsWonBeforeCurrentSet() -> Score {
        guard currentSetNumber > 1 else { return Score() }

        var wins = Score()
        for set in 1..<currentSetNumber {
            let setScore = scoreForSet(set)
            if setScore.us > setScore.them {
                wins.us += 1
            } else if setScore.them > setScore.us {
                wins.them += 1
            }
        }

        return wins
    }
}
