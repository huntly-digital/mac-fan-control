import FanProtocol

struct HardwareValidationPresentation: Equatable {
  let title: String
  let message: String
  let canValidate: Bool

  static func resolve(
    eligibility: WriteEligibility,
    controlAccess: ControlAccess?
  ) -> Self {
    if controlAccess == .observer {
      return Self(
        title: "Read-only session",
        message: "Another MFanControl instance owns the fan controller.",
        canValidate: false
      )
    }
    switch eligibility {
    case .approved:
      return Self(
        title: "Hardware validation passed",
        message: "This exact model, macOS build, and capability fingerprint is approved.",
        canValidate: false
      )
    case .validationRequired:
      return Self(
        title: "Hardware validation required",
        message: "Validation briefly tests each fan and then fully restores Auto.",
        canValidate: true
      )
    case .unsupported:
      return Self(
        title: "Hardware is read-only",
        message: "Required fan capabilities are missing or inconsistent.",
        canValidate: false
      )
    case .blocked:
      return Self(
        title: "Fan writes are blocked",
        message: "Recovery or capability verification failed. Do not retry writes.",
        canValidate: false
      )
    }
  }
}

enum TemperaturePreference {
  static func primary(
    in snapshot: TemperatureSnapshot?,
    selectedID: String?
  ) -> TemperatureReading? {
    snapshot?.primaryReading(selectedID: selectedID)
  }
}
