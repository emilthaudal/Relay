//
//  AdapterError.swift
//  Relay
//
//  Shared error type used across all ConnectionAdapters.
//

import Foundation

enum AdapterError: LocalizedError {
    case unavailable(String)
    case authFailed(String)
    case networkError(String)
    case parseError(String)
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let msg):  return "Unavailable: \(msg)"
        case .authFailed(let msg):   return "Authentication failed: \(msg)"
        case .networkError(let msg): return "Network error: \(msg)"
        case .parseError(let msg):   return "Parse error: \(msg)"
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        }
    }
}
