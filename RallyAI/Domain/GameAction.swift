//
//  GameAction.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/15/26.
//

import Foundation

enum GameAction {
    case addEvent(RallyEvent)
    case deleteEvent(UUID)
    case replaceEvent(UUID, with: RallyEvent)
    
    case startNewSet
    case manualScore(us: Int, them: Int)
}
