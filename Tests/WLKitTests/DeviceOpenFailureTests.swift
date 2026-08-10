import XCTest
import IOKit
@testable import WLKit

/// A refused open must read as a permission problem, whichever code the OS
/// picks for it. macOS 15 answers `IOHIDDeviceOpen` with
/// `kIOReturnNotPermitted` (0xE00002E2) where earlier versions used
/// `kIOReturnNotPrivileged` (0xE00002C1); the app only recognised the latter,
/// so a TCC denial surfaced as a bare hex code and the bridge never lit its
/// permission UI.
final class DeviceOpenFailureTests: XCTestCase {

    func testNotPermittedReadsAsAPermissionProblem() {
        let failure = WLDevice.Failure.openFailed(kIOReturnNotPermitted)
        XCTAssertTrue(failure.isPermissionDenied)
        XCTAssertTrue(
            failure.errorDescription?.contains("Input Monitoring") == true,
            "got: \(failure.errorDescription ?? "nil")"
        )
    }

    func testNotPrivilegedStillReadsAsAPermissionProblem() {
        let failure = WLDevice.Failure.openFailed(kIOReturnNotPrivileged)
        XCTAssertTrue(failure.isPermissionDenied)
        XCTAssertTrue(failure.errorDescription?.contains("Input Monitoring") == true)
    }

    /// The message names the code either way, so a report can be diagnosed.
    func testThePermissionMessageStillCarriesTheCode() {
        XCTAssertTrue(
            WLDevice.Failure.openFailed(kIOReturnNotPermitted)
                .errorDescription?.contains("0xE00002E2") == true
        )
    }

    /// Another client holding the pad is not a permission problem, and telling
    /// someone to grant Input Monitoring they already granted sends them in
    /// circles.
    func testExclusiveAccessIsNotAPermissionProblem() {
        let failure = WLDevice.Failure.openFailed(kIOReturnExclusiveAccess)
        XCTAssertFalse(failure.isPermissionDenied)
        XCTAssertFalse(failure.errorDescription?.contains("Input Monitoring") == true)
        XCTAssertTrue(failure.errorDescription?.contains("0xE00002C5") == true)
    }

    func testOtherFailuresAreNotPermissionProblems() {
        XCTAssertFalse(WLDevice.Failure.notFound.isPermissionDenied)
        XCTAssertFalse(WLDevice.Failure.noVendorCollection.isPermissionDenied)
    }
}
