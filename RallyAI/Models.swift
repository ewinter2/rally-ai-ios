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
    let setNumber: Int?
}

// Mirrors the backend response
struct BackendParsedEvent: Codable, Equatable {
    let playerNumber: Int?
    let event: String
    let pointAwardedTo: String?
    let needsReview: Bool
    let rawText: String
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
    let source: CommandSource
    let setNumber: Int
    var rawText: String
    var status: CommandStatus
    var parsedEvent: BackendParsedEvent?
    var errorMessage: String?
}

struct PersistedAppState: Codable {
    let gameState: GameState
    let commandQueue: [CommandInput]
}
