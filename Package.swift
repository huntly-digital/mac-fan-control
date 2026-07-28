// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "MFanControl",
  platforms: [.macOS(.v15)],
  products: [
    .library(name: "SMCBridge", targets: ["SMCBridge"]),
    .library(name: "FanProtocol", targets: ["FanProtocol"]),
    .library(name: "HelperProtocol", targets: ["HelperProtocol"]),
    .library(name: "HelperServiceCore", targets: ["HelperServiceCore"]),
    .library(name: "HelperManagement", targets: ["HelperManagement"]),
    .library(name: "FanCore", targets: ["FanCore"]),
    .library(name: "FanDaemonCore", targets: ["FanDaemonCore"]),
    .executable(name: "fancontrold", targets: ["fancontrold"]),
    .executable(name: "MFanControlApp", targets: ["MFanControlApp"]),
  ],
  targets: [
    .target(name: "SMCBridge"),
    .target(name: "FanProtocol"),
    .target(name: "HelperProtocol"),
    .target(
      name: "HelperServiceCore",
      dependencies: ["FanCore", "FanDaemonCore", "FanProtocol", "HelperProtocol"]
    ),
    .target(
      name: "HelperManagement",
      dependencies: ["FanProtocol", "HelperProtocol"]
    ),
    .target(
      name: "FanCore",
      dependencies: ["SMCBridge", "FanProtocol"]
    ),
    .target(
      name: "FanDaemonCore",
      dependencies: ["FanCore", "FanProtocol"]
    ),
    .executableTarget(
      name: "fancontrold",
      dependencies: ["FanDaemonCore", "FanCore", "FanProtocol", "HelperServiceCore"]
    ),
    .executableTarget(
      name: "MFanControlApp",
      dependencies: ["FanProtocol", "HelperManagement"]
    ),
    .testTarget(
      name: "SMCBridgeTests",
      dependencies: ["SMCBridge"]
    ),
    .testTarget(
      name: "FanProtocolTests",
      dependencies: ["FanProtocol"]
    ),
    .testTarget(
      name: "HelperProtocolTests",
      dependencies: ["HelperProtocol"]
    ),
    .testTarget(
      name: "HelperServiceCoreTests",
      dependencies: ["FanProtocol", "HelperProtocol", "HelperServiceCore"]
    ),
    .testTarget(
      name: "HelperManagementTests",
      dependencies: ["FanProtocol", "HelperManagement", "HelperProtocol"]
    ),
    .testTarget(
      name: "FanCoreTests",
      dependencies: ["FanCore", "FanProtocol", "SMCBridge"]
    ),
    .testTarget(
      name: "FanDaemonCoreTests",
      dependencies: ["FanDaemonCore", "FanProtocol"]
    ),
    .testTarget(
      name: "HardwareTests",
      dependencies: ["FanCore"],
      path: "Tests/HardwareTests",
      exclude: ["Fixtures"]
    ),
    .testTarget(
      name: "MFanControlAppTests",
      dependencies: ["MFanControlApp"]
    ),
  ]
)
