import AppKit
import Darwin
import FanCore
import FanDaemonCore
import FanProtocol
import Foundation
import HelperServiceCore

@main
enum FanControlDaemonMain {
  static func main() async {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.first == "--service-managed" {
      guard geteuid() == 0 else {
        fail("service-managed fancontrold must run as root")
      }
      HelperXPCServiceRunner.run()
    }
    if arguments.first == "probe" {
      await runProbe()
      return
    }

    guard geteuid() == 0 else {
      fail("fancontrold must be started with sudo")
    }
    guard let uid = allowedUID(from: arguments) else {
      fail("usage: fancontrold --allowed-uid <uid> | fancontrold probe")
    }

    do {
      let controller = try FanController()
      _ = try await controller.discoverHardware()
      _ = try await controller.snapshot()

      let processor = RequestProcessor(controller: controller)
      let server = DaemonServer(allowedUID: uid, processor: processor)
      let lifecycle = installLifecycleHandlers(processor: processor, server: server)

      print("fancontrold listening on \(server.socketPath) for uid \(uid)")
      do {
        try await server.run()
      } catch {
        await processor.restoreForShutdown()
        lifecycle.cancel()
        throw error
      }
      await processor.restoreForShutdown()
      lifecycle.cancel()
    } catch {
      fail(error.localizedDescription)
    }
  }

  private static func runProbe() async {
    do {
      let controller = try FanController()
      let report = try await controller.probe()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(report)
      FileHandle.standardOutput.write(data)
      FileHandle.standardOutput.write(Data([0x0A]))
    } catch {
      fail(error.localizedDescription)
    }
  }

  private static func allowedUID(from arguments: [String]) -> uid_t? {
    guard let index = arguments.firstIndex(of: "--allowed-uid"),
      arguments.indices.contains(index + 1),
      let value = UInt32(arguments[index + 1])
    else { return nil }
    return uid_t(value)
  }

  private static func installLifecycleHandlers(
    processor: RequestProcessor,
    server: DaemonServer
  ) -> LifecycleHandlers {
    signal(SIGPIPE, SIG_IGN)
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    let signalSources = [SIGINT, SIGTERM].map { signalNumber in
      let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
      source.setEventHandler {
        Task {
          await processor.restoreForShutdown()
          server.requestStop()
        }
      }
      source.resume()
      return source
    }

    let workspaceCenter = NSWorkspace.shared.notificationCenter
    let sleepObserver = workspaceCenter.addObserver(
      forName: NSWorkspace.willSleepNotification,
      object: nil,
      queue: nil
    ) { _ in
      Task { await processor.handleSystemWillSleep() }
    }
    let wakeObserver = workspaceCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: nil
    ) { _ in
      Task { await processor.handleSystemDidWake() }
    }
    let thermalObserver = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: ProcessInfo.processInfo,
      queue: nil
    ) { _ in
      switch ProcessInfo.processInfo.thermalState {
      case .serious, .critical:
        Task { await processor.handleThermalEmergency() }
      default:
        break
      }
    }

    return LifecycleHandlers(
      signalSources: signalSources,
      observers: [
        (workspaceCenter, sleepObserver),
        (workspaceCenter, wakeObserver),
        (NotificationCenter.default, thermalObserver),
      ]
    )
  }

  private static func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("fancontrold: \(message)\n".utf8))
    Darwin.exit(1)
  }
}

private final class LifecycleHandlers {
  private let signalSources: [DispatchSourceSignal]
  private let observers: [(NotificationCenter, NSObjectProtocol)]

  init(
    signalSources: [DispatchSourceSignal],
    observers: [(NotificationCenter, NSObjectProtocol)]
  ) {
    self.signalSources = signalSources
    self.observers = observers
  }

  func cancel() {
    for source in signalSources {
      source.cancel()
    }
    for (center, token) in observers {
      center.removeObserver(token)
    }
  }
}
