//
//  AppConfig.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/9/26.
//


import Foundation

enum AppConfig {
    #if DEBUG && targetEnvironment(simulator)
    static let backendBaseURL: URL = URL(string: "http://127.0.0.1:8000")!
    #else
    static let backendBaseURL: URL = URL(string: "https://web-production-98ea9.up.railway.app")!
    #endif
}
