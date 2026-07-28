import XCTest

@testable import SMCBridge

final class SMCABILayoutTests: XCTestCase {
  func testKernelParameterLayoutMatchesAppleSMCABI() {
    XCTAssertEqual(MemoryLayout<SMCParamStruct>.stride, 80)
    XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.keyInfo), 28)
    XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.result), 40)
    XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.data8), 42)
    XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.data32), 44)
    XCTAssertEqual(MemoryLayout<SMCParamStruct>.offset(of: \.bytes), 48)
  }
}
