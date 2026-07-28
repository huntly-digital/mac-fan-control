import SwiftUI

enum DaemonStatus: Equatable {
  case notRunning
  case connected
  case experimentalM3
  case error(String)

  var title: String {
    switch self {
    case .notRunning: "Not running"
    case .connected: "Connected"
    case .experimentalM3: "Experimental M3"
    case .error: "Error"
    }
  }

  var color: Color {
    switch self {
    case .notRunning: .secondary
    case .connected: .green
    case .experimentalM3: .orange
    case .error: .red
    }
  }
}
