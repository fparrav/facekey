//
//  SudoIntegrationInstaller.swift
//  facekey
//
//  Installs and removes the sudo integration by running the scripts bundled in the app
//  through `sudo -S` with a password prompt of the app's own. The scripts and the PAM module are read from the app's
//  Resources, and nothing is elevated unless the app on disk still matches the signature of
//  the process that is running.
//

import AppKit
import CryptoKit
import Foundation
import Security

enum SudoIntegrationInstaller {
    enum Failure: LocalizedError {
        case resourcesMissing
        case bundleModified
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .resourcesMissing:
                return String(localized: "The sudo integration files are missing from this copy of Facekey.")
            case .bundleModified:
                return String(localized: "This copy of Facekey does not pass its signature check, so it will not change the system.")
            case .cancelled:
                return String(localized: "The administrator prompt was cancelled.")
            case .failed(let detail):
                return detail.isEmpty ? String(localized: "The installer failed.") : detail
            }
        }
    }

    private static var resourceDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("sudo", isDirectory: true)
    }

    static var bundledModuleURL: URL? { resourceDirectory?.appendingPathComponent("pam_facekey.so") }

    /// The version the installer records for the bundled module: its SHA-256, as hex.
    static func bundledVersion() -> String? {
        guard let url = bundledModuleURL, let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The state of the installed integration against the module shipped in this app.
    static func currentState() -> SudoIntegrationState {
        guard let version = bundledVersion() else { return .notInstalled }
        return SudoIntegrationStatus.evaluate(bundledVersion: version)
    }

    static func install() async throws {
        guard let directory = resourceDirectory, let module = bundledModuleURL,
              FileManager.default.fileExists(atPath: module.path) else { throw Failure.resourcesMissing }
        let script = directory.appendingPathComponent("install.sh")
        guard FileManager.default.fileExists(atPath: script.path) else { throw Failure.resourcesMissing }
        try await runElevated(script: script, module: module)
    }

    static func remove() async throws {
        guard let directory = resourceDirectory else { throw Failure.resourcesMissing }
        let script = directory.appendingPathComponent("uninstall.sh")
        guard FileManager.default.fileExists(atPath: script.path) else { throw Failure.resourcesMissing }
        try await runElevated(script: script, module: nil)
    }

    /// Runs the script as root through `sudo -S`, so it stays a child of this app. macOS refuses a write to
    /// `/etc/pam.d/sudo_local` from the root shell that the system administrator prompt starts, and allows it
    /// from a child of this app. The password comes from a prompt of the app's own and goes to sudo's standard
    /// input; it is never written to disk or put on a command line.
    private static func runElevated(script: URL, module: URL?) async throws {
        guard bundleSignatureIsValid() else { throw Failure.bundleModified }
        try await Task.detached(priority: .userInitiated) {
            let workDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("facekey-install-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
                at: workDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: workDirectory) }

            // Root runs private copies, not the files in the app bundle, which another process could swap after
            // the check. The signature is checked again once the copies exist, so they match the sealed files.
            let scriptCopy = workDirectory.appendingPathComponent(script.lastPathComponent)
            try FileManager.default.copyItem(at: script, to: scriptCopy)
            var arguments: [String] = []
            if let module {
                let moduleCopy = workDirectory.appendingPathComponent(module.lastPathComponent)
                try FileManager.default.copyItem(at: module, to: moduleCopy)
                arguments = [moduleCopy.path]
            }
            guard bundleSignatureIsValid() else { throw Failure.bundleModified }

            // sudo itself gives up after three wrong passwords; the prompt is shown again after each one.
            for attempt in 0..<3 {
                guard var password = await requestPassword(wasIncorrect: attempt > 0) else { throw Failure.cancelled }
                defer { password.resetBytes(in: 0..<password.count) }
                let (status, text) = try runSudo(scriptPath: scriptCopy.path, arguments: arguments, password: password)
                if status == 0 { return }
                if text.contains("incorrect password attempt"), attempt < 2 { continue }
                throw Failure.failed(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }.value
    }

    private static func runSudo(scriptPath: String, arguments: [String], password: Data) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // -k ignores cached credentials, -S reads the password from standard input, -p "" keeps the prompt out of the output.
        process.arguments = ["-S", "-k", "-p", "", "--", "/bin/bash", scriptPath] + arguments
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        input.fileHandleForWriting.write(password + Data("\n".utf8))
        try? input.fileHandleForWriting.close()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, text)
    }

    /// The app's own password sheet, styled like the system's: the app icon, a short sentence, a secure field.
    @MainActor
    private static func requestPassword(wasIncorrect: Bool) -> Data? {
        let alert = NSAlert()
        alert.messageText = String(localized: "Facekey wants to make changes.")
        alert.informativeText = wasIncorrect
            ? String(localized: "That password is incorrect. Try again.")
            : String(localized: "Enter your password to allow this.")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = String(localized: "Password")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return nil }
        return Data(field.stringValue.utf8)
    }

    /// Whether the app on disk still satisfies the designated requirement of the running
    /// process, so files swapped or re-signed after launch are refused.
    private static func bundleSignatureIsValid() -> Bool {
        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var onDisk: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess,
              SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &onDisk) == errSecSuccess,
              let onDisk else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        return SecStaticCodeCheckValidity(onDisk, flags, requirement) == errSecSuccess
    }
}
