//
//  setup_readiness_selftest.swift
//  facekey (tools)
//
//  Offline self-test for the Summary page checklist in facekey/Settings/SetupReadiness.swift:
//  the all-ready case, each single failing check, and the settings page each check points to.
//  This project has no test target, so this compiles as a standalone script against the real files:
//
//      /usr/bin/swiftc -O -parse-as-library -o /private/tmp/setup_readiness_selftest facekey/Settings/SettingsPage.swift facekey/Settings/SetupReadiness.swift tools/setup_readiness_selftest.swift && /private/tmp/setup_readiness_selftest
//
//  Prints PASS/FAIL per check; exits 0 when every check passes, 1 otherwise.
//

import Foundation

var failures = 0

func check(_ cond: Bool, _ name: String) {
    if cond {
        print("PASS: \(name)")
    } else {
        print("FAIL: \(name)")
        failures += 1
    }
}

func readiness(
    enrolled: Int = 1,
    password: Bool = true,
    liveness: ReadinessLiveness = .light,
    camera: Bool = true,
    accessibility: Bool = true,
    cameraPermission: ReadinessPermission = .granted
) -> SetupReadiness {
    SetupReadiness(
        enrolledCount: enrolled,
        hasPassword: password,
        liveness: liveness,
        hasCameraForCurrentSetup: camera,
        accessibilityGranted: accessibility,
        cameraPermission: cameraPermission
    )
}

func failing(_ r: SetupReadiness) -> [SetupCheckID] {
    r.checks.filter { !$0.passed }.map(\.id)
}

func page(of id: SetupCheckID, in r: SetupReadiness) -> SettingsPage? {
    r.checks.first { $0.id == id }?.targetPage
}

@main
enum SetupReadinessSelfTest {
    static func main() {
        let ready = readiness()
        check(ready.total == 5, "there are five checks")
        check(ready.passedCount == 5, "all ready passes 5 of 5")
        check(ready.isReady, "all ready is ready")
        check(failing(ready).isEmpty, "all ready has no failing check")

        check(failing(readiness(enrolled: 0)) == [.face], "no face fails only the face check")
        check(failing(readiness(password: false)) == [.password], "no password fails only the password check")
        check(failing(readiness(liveness: .off)) == [.liveness], "liveness off fails only the liveness check")
        check(readiness(liveness: .heavy).isReady, "heavy liveness counts as on")
        check(failing(readiness(camera: false)) == [.camera], "no camera fails only the camera check")
        check(failing(readiness(accessibility: false)) == [.permissions], "Accessibility revoked fails only the permissions check")
        check(failing(readiness(cameraPermission: .denied)) == [.permissions], "Camera denied fails only the permissions check")
        check(failing(readiness(cameraPermission: .notDetermined)) == [.permissions], "Camera not asked yet fails the permissions check")

        let none = readiness(enrolled: 0, password: false, liveness: .off, camera: false, accessibility: false, cameraPermission: .denied)
        check(none.passedCount == 0, "nothing set up passes 0 of 5")
        check(!none.isReady, "nothing set up is not ready")

        check(page(of: .face, in: none) == .access, "face points to Access")
        check(page(of: .password, in: none) == .access, "password points to Access")
        check(page(of: .liveness, in: none) == .access, "liveness points to Access")
        check(page(of: .camera, in: none) == .devices, "camera points to Camera and displays")
        check(page(of: .permissions, in: none) == .app, "permissions points to App")

        check(none.checks.map(\.id) == SetupCheckID.allCases, "checks follow the declared order")

        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("All checks passed")
    }
}
