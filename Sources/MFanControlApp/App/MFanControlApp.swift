import AppKit
import Darwin
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    signal(SIGPIPE, SIG_IGN)
    NSApp.setActivationPolicy(.accessory)
  }
}

@main
struct MFanControlApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var store = FanStore()
  @StateObject private var presetStore = PresetStore()
  @StateObject private var helperStore = HelperStore()

  var body: some Scene {
    MenuBarExtra {
      FanMenuView(store: store, presetStore: presetStore, helperStore: helperStore)
    } label: {
      MenuBarLabel(store: store)
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView(store: store, presetStore: presetStore, helperStore: helperStore)
    }
  }
}

private struct MenuBarLabel: View {
  @ObservedObject var store: FanStore
  @AppStorage("showTemperatureInMenuBar") private var showTemperature = true

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "fanblades")
      if let title = MenuBarTemperaturePresentation.title(
        isEnabled: showTemperature,
        celsius: store.primaryTemperature?.celsius
      ) {
        Text(title)
          .monospacedDigit()
      }
    }
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    if let title = MenuBarTemperaturePresentation.title(
      isEnabled: showTemperature,
      celsius: store.primaryTemperature?.celsius
    ) {
      return "MFanControl, \(title)"
    }
    return "MFanControl"
  }
}
