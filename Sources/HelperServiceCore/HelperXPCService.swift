import AppKit
import Darwin
import FanCore
import FanDaemonCore
import FanProtocol
import Foundation
import HelperProtocol
import IOKit.ps
import Security

public final class HelperXPCService: NSObject, HelperXPCProtocol, @unchecked Sendable {
  public typealias RequestHandler = @Sendable (FanRequest) async -> FanResponse
  public typealias DisconnectHandler = @Sendable () async -> Void
  public typealias SessionRequestHandler =
    @Sendable (FanRequest, UUID) async -> FanResponse
  public typealias SessionDisconnectHandler = @Sendable (UUID) async -> Void

  private let handler: SessionRequestHandler
  private let disconnectHandler: SessionDisconnectHandler
  private let sessionID = UUID()
  private let sessionLock = NSLock()
  private var fanSessionStarted = false

  public init(
    handler: @escaping RequestHandler,
    disconnectHandler: @escaping DisconnectHandler = {}
  ) {
    self.handler = { request, _ in await handler(request) }
    self.disconnectHandler = { _ in await disconnectHandler() }
  }

  public init(
    sessionHandler: @escaping SessionRequestHandler,
    sessionDisconnectHandler: @escaping SessionDisconnectHandler = { _ in }
  ) {
    self.handler = sessionHandler
    self.disconnectHandler = sessionDisconnectHandler
  }

  public func ping(withReply reply: @escaping (String) -> Void) {
    reply(HelperServiceDescriptor.protocolVersion)
  }

  public func performFanRequest(
    _ requestData: Data,
    withReply reply: @escaping (Data?, NSError?) -> Void
  ) {
    let replyBox = HelperXPCReplyBox(reply)
    let request: FanRequest
    do {
      request = try JSONLineCodec.decode(
        FanRequest.self,
        from: requestData,
        maximumBytes: JSONLineCodec.maximumRequestBytes
      )
    } catch {
      replyBox.call(nil, Self.xpcError(error.localizedDescription))
      return
    }

    if request.command == .hello {
      sessionLock.withLock {
        fanSessionStarted = true
      }
    }

    Task {
      let response = await handler(request, sessionID)
      do {
        replyBox.call(try JSONLineCodec.encode(response), nil)
      } catch {
        replyBox.call(nil, Self.xpcError(error.localizedDescription))
      }
    }
  }

  public func connectionInvalidated() {
    let shouldHandleDisconnect = sessionLock.withLock {
      let wasStarted = fanSessionStarted
      fanSessionStarted = false
      return wasStarted
    }
    guard shouldHandleDisconnect else { return }
    Task {
      await disconnectHandler(sessionID)
    }
  }

  private static func xpcError(_ message: String) -> NSError {
    NSError(
      domain: HelperXPCError.errorDomain,
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

private final class HelperXPCReplyBox: @unchecked Sendable {
  private let reply: (Data?, NSError?) -> Void

  init(_ reply: @escaping (Data?, NSError?) -> Void) {
    self.reply = reply
  }

  func call(_ data: Data?, _ error: NSError?) {
    reply(data, error)
  }
}

public enum HelperClientRequirement {
  public static func make(teamIdentifier: String) -> String {
    "identifier \"io.clover.mfancontrol\" and anchor apple generic "
      + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
  }

  public static func forCurrentHelper() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
      return nil
    }
    var staticCode: SecStaticCode?
    guard
      SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
      let staticCode
    else {
      return nil
    }

    var information: CFDictionary?
    guard
      SecCodeCopySigningInformation(
        staticCode,
        SecCSFlags(rawValue: kSecCSSigningInformation),
        &information
      ) == errSecSuccess,
      let values = information as? [CFString: Any],
      let teamIdentifier = values[kSecCodeInfoTeamIdentifier] as? String,
      !teamIdentifier.isEmpty
    else {
      return nil
    }
    return make(teamIdentifier: teamIdentifier)
  }
}

public final class HelperXPCListenerDelegate: NSObject, NSXPCListenerDelegate {
  private let serviceFactory: @Sendable () -> HelperXPCService
  private let clientRequirement: String

  public init(
    clientRequirement: String,
    serviceFactory: @escaping @Sendable () -> HelperXPCService
  ) {
    self.clientRequirement = clientRequirement
    self.serviceFactory = serviceFactory
    super.init()
  }

  public func listener(
    _ listener: NSXPCListener,
    shouldAcceptNewConnection connection: NSXPCConnection
  ) -> Bool {
    let service = serviceFactory()
    connection.setCodeSigningRequirement(clientRequirement)
    connection.exportedInterface = NSXPCInterface(with: HelperXPCProtocol.self)
    connection.exportedObject = service
    connection.invalidationHandler = {
      service.connectionInvalidated()
    }
    connection.resume()
    return true
  }
}

public enum HelperXPCServiceRunner {
  public static func run() -> Never {
    let runtime: PrivilegedFanRuntime
    do {
      runtime = try PrivilegedFanRuntime()
    } catch {
      fatalError("Could not initialize fan controller: \(error.localizedDescription)")
    }
    guard let clientRequirement = HelperClientRequirement.forCurrentHelper() else {
      fatalError("The helper must have an Apple Development Team signature")
    }

    let listener = NSXPCListener(
      machServiceName: HelperServiceDescriptor.machServiceName
    )
    let delegate = HelperXPCListenerDelegate(
      clientRequirement: clientRequirement,
      serviceFactory: {
        runtime.makeService()
      }
    )
    let lifecycle = HelperSafetyLifecycle(processor: runtime.processor)
    listener.delegate = delegate
    listener.resume()

    return withExtendedLifetime((delegate, lifecycle)) {
      dispatchMain()
    }
  }
}

private final class PrivilegedFanRuntime: @unchecked Sendable {
  let processor: RequestProcessor

  init() throws {
    processor = try RequestProcessor(controller: FanController())
  }

  func makeService() -> HelperXPCService {
    HelperXPCService(
      sessionHandler: { [processor] request, sessionID in
        await processor.handle(request, sessionID: sessionID).response
      },
      sessionDisconnectHandler: { [processor] sessionID in
        await processor.handleDisconnect(sessionID: sessionID)
      }
    )
  }
}

private final class HelperSafetyLifecycle: @unchecked Sendable {
  private let processor: RequestProcessor
  private var tickTask: Task<Void, Never>?
  private var signalSources: [DispatchSourceSignal] = []
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var powerSourceRunLoopSource: CFRunLoopSource?

  init(processor: RequestProcessor) {
    self.processor = processor
    installTick()
    installSignals()
    installSystemObservers()
    installPowerSourceObserver()
  }

  deinit {
    tickTask?.cancel()
    signalSources.forEach { $0.cancel() }
    observers.forEach { center, token in
      center.removeObserver(token)
    }
    if let powerSourceRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceRunLoopSource, .defaultMode)
    }
  }

  private func installTick() {
    tickTask = Task { [processor] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        await processor.tick()
      }
    }
  }

  private func installSignals() {
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    signalSources = [SIGINT, SIGTERM].map { signalNumber in
      let source = DispatchSource.makeSignalSource(
        signal: signalNumber,
        queue: .global()
      )
      source.setEventHandler { [processor] in
        Task {
          await processor.restoreForShutdown()
          Darwin.exit(0)
        }
      }
      source.resume()
      return source
    }
  }

  private func installSystemObservers() {
    let workspaceCenter = NSWorkspace.shared.notificationCenter
    let sleepObserver = workspaceCenter.addObserver(
      forName: NSWorkspace.willSleepNotification,
      object: nil,
      queue: nil
    ) { [processor] _ in
      Task { await processor.handleSystemWillSleep() }
    }
    let wakeObserver = workspaceCenter.addObserver(
      forName: NSWorkspace.didWakeNotification,
      object: nil,
      queue: nil
    ) { [processor] _ in
      Task { await processor.handleSystemDidWake() }
    }
    let thermalObserver = NotificationCenter.default.addObserver(
      forName: ProcessInfo.thermalStateDidChangeNotification,
      object: ProcessInfo.processInfo,
      queue: nil
    ) { [processor] _ in
      switch ProcessInfo.processInfo.thermalState {
      case .serious, .critical:
        Task { await processor.handleThermalEmergency() }
      default:
        break
      }
    }

    observers = [
      (workspaceCenter, sleepObserver),
      (workspaceCenter, wakeObserver),
      (NotificationCenter.default, thermalObserver),
    ]
  }

  private func installPowerSourceObserver() {
    let context = Unmanaged.passUnretained(self).toOpaque()
    guard let unmanaged = IOPSNotificationCreateRunLoopSource(
      { context in
        guard let context else { return }
        let lifecycle = Unmanaged<HelperSafetyLifecycle>
          .fromOpaque(context)
          .takeUnretainedValue()
        Task { await lifecycle.processor.handlePowerSourceChanged() }
      },
      context
    ) else {
      return
    }
    let source = unmanaged.takeRetainedValue()
    powerSourceRunLoopSource = source
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
  }
}
