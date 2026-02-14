//
//  Models.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/9/26.
//

import Foundation

// What is sent to the backend
// Codable allows easy conversion of data to and from JSON data
struct PartseTextRequest: Codable {
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

// App's Internal Model of Event
// Identifiable meaning that each event can be distinguished individually
// Enums for Action + Teamside to avoid issues with capitolization
struct Event: Identifiable, Codable {
    let id: String
    let createdAt: Date
    let setNumber: Int?
    let playerNumber: Int?
    let action: Action
    let pointAwardedTo: TeamSide?
    let needsReview: Bool
    let rawText:String
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
    case serveError = "SERVE ERROR"
    case pointUs = "POINT_US"
    case pointThem = "POINT_THEM"
    case unknown = "UNKNOWN"
}

// Takes raw backend response and converts it into an App Event
extension Event {
    static func fromBackend(_ backend: BackendParsedEvent, setNumber: Int) -> Event {
        //If backend.action is "KILL" it becomes .kill, if it's something that it doesn't recognize its .unknown
        let action = Action(rawValue: backend.event) ?? .unknown
        
        //if backend.pointAwardedTo is "us" -> .us, if its nil stays nil
        let side = backend.pointAwardedTo.flatMap { TeamSide(rawValue:$0) }
        
        //FUTURE UPGRADES: create this ID before calling the backend
        return Event(
            //ID is generated here because the backend doesnt generate ID's for events but the app can here. Later helps with Firestore document ID's and avoiding duplicates
            id: UUID().uuidString,
            createdAt: Date(),
            setNumber: setNumber,
            playerNumber: backend.playerNumber,
            action: action,
            pointAwardedTo: side,
            needsReview: backend.needsReview,
            rawText: backend.rawText
        )
    }
}
