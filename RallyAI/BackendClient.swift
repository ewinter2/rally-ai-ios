//
//  BackendClient.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/11/26.
//

import Foundation

//Given some input text, call the backend and return a parsed result

struct ParseTextRequest: Codable {
    let text: String
    let setNumber: Int
}

//defines errors that occur during backend communication
enum BackendError: Error, LocalizedError {
    case badResponse(statusCode:Int)
    case decodeFailed
    
    var errorDescription: String? {
        switch self {
        case .badResponse(let code): return "Backend returned status \(code)"
        case .decodeFailed: return "Could not decode backend response"
        }
    }
}

protocol BackendClientProtocol {
    func parseText(_ text: String, setNumber: Int) async throws -> BackendParsedEvent
}

final class BackendClient: BackendClientProtocol {
    private let baseURL: URL
    
    // Pulls http://localhost:8000 from AppConfig rather than hardcoding the url
    // Will change when calling to the cloud
    init(baseURL: URL = AppConfig.backendBaseURL) {
        self.baseURL = baseURL
    }
    
    func parseText(_ text: String, setNumber: Int) async throws -> BackendParsedEvent {
        let url = baseURL.appendingPathComponent("parse-text")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST" //Using POST to send a body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type") //Telling the server the body is JSON
        
        // Create a swift struct, convert it to JSON, attach to request
        let body = ParseTextRequest(text: text, setNumber: setNumber)
        request.httpBody = try JSONEncoder().encode(body)
        
        //App send request over the network and retrives raw data and HTTP response metadata
        let (data, response) = try await URLSession.shared.data(for: request)
        
        print(String(data: data, encoding: .utf8) ?? "No JSON string")
        
        //Check for valid HTTP response
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.badResponse(statusCode: -1)
        }
        
        //Check for successfull response
        guard (200...299).contains(http.statusCode) else {
            throw BackendError.badResponse(statusCode: http.statusCode)
        }
        
        //If failed, throw backend error
        let decoder = JSONDecoder()
        guard let parsed = try? decoder.decode(BackendParsedEvent.self, from: data) else {
            throw BackendError.decodeFailed
        }
        
        return parsed
    }
}

