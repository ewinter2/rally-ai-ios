//
//  Models.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/9/26.
//

import Foundation

// What is sent to the backend
// Codable allows easy conversion of data to and from JSON data
struct ParseTextRequest: Codable {
    let text: String
    let setNumber: Int?
}

// Mirrors the backend response
struct BackendParsedEvent: Codable {
    let playerNumber: Int?
    let event: String
    let pointAwardedTo: String? ///should this be a string?
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
    case kill = "KILL"
    case dig = "DIG"
    case ace = "ACE"
    case block = "BLOCK"
    case hitError = "HIT_ERROR"
    case serveError = "SERVE_ERROR"
    case pointUs = "POINT_US"
    case pointThem = "POINT_THEM"
    case unknown = "UNKNOWN"
}
