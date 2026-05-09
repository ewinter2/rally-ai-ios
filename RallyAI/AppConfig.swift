//
//  AppConfig.swift
//  RallyAI
//
//  Created by Ellie Winter on 2/9/26.
//


import Foundation

enum AppConfig {
    // All builds (DEBUG, Release, Simulator, device, TestFlight) point at the
    // Railway-hosted FastAPI backend. No local backend is required.
    static let backendBaseURL: URL = URL(string: "https://web-production-98ea9.up.railway.app")!
}
