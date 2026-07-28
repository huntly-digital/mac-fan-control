import XCTest

@testable import FanCore

final class SafetyStateMachineTests: XCTestCase {
  func testMissedHeartbeatReturnsEveryFanToAutomatic() {
    var machine = SafetyStateMachine(heartbeatTimeout: 5)
    let start = Date(timeIntervalSince1970: 1_000)
    machine.handle(.clientConnected(at: start))
    machine.handle(.manualActivated(at: start))

    XCTAssertEqual(machine.handle(.timerFired(at: start.addingTimeInterval(5.1))), .setAllAutomatic)
    XCTAssertEqual(machine.state, .returningAutomatic)
  }

  func testDisconnectSleepAndThermalPressureReturnToAutomatic() {
    for event in [
      SafetyEvent.clientDisconnected,
      .systemWillSleep,
      .thermalEmergency,
      .shutdown,
    ] {
      var machine = SafetyStateMachine()
      machine.handle(.clientConnected(at: .distantPast))
      machine.handle(.manualActivated(at: .distantPast))

      XCTAssertEqual(machine.handle(event), .setAllAutomatic)
    }
  }

  func testWakeDoesNotRestoreManualMode() {
    var machine = SafetyStateMachine()
    machine.handle(.systemWillSleep)
    machine.handle(.automaticRestored)

    XCTAssertEqual(machine.handle(.systemDidWake), .none)
    XCTAssertEqual(machine.state, .automatic)
  }
}
