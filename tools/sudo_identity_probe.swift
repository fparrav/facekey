//
//  sudo_identity_probe.swift
//  facekey (tools)
//
//  Standalone probe: prints this process's ancestor chain and resolves the
//  identity of the first regular GUI app in it via the real SudoAppIdentityResolver.
//  No test target exists for this, so it compiles against the real file:
//
//      /usr/bin/swiftc -parse-as-library -o /private/tmp/sudo_identity_probe \
//        facekey/Sudo/SudoAppIdentity.swift tools/sudo_identity_probe.swift \
//      && /private/tmp/sudo_identity_probe
//
//  Prints one "kind:/identifier:/teamID:/displayName:/key:" line set per resolution,
//  or "identity: none (no regular app in chain)"; exits 0 either way.
//

import Foundation
import AppKit

@main
enum SudoIdentityProbe {

    static func main() {
        let chain = ancestorChain()
        print("chain: \(chain.map { String($0) }.joined(separator: " "))")
        if let identity = SudoAppIdentityResolver.identity(forChain: chain) {
            print("kind: \(identity.kind.rawValue)")
            print("identifier: \(identity.identifier)")
            print("teamID: \(identity.teamID ?? "-")")
            print("displayName: \(identity.displayName)")
            print("key: \(identity.key)")
        } else {
            print("identity: none (no regular app in chain)")
        }
        exit(0)
    }

    /// Ancestor pids, nearest parent first, excluding the probe's own pid;
    /// stops at pid 1 (init) or the first sysctl failure, capped at 64 levels.
    private static func ancestorChain() -> [Int32] {
        var chain: [Int32] = []
        var pid = getpid()
        while pid > 1, chain.count < 64 {
            guard let parent = parentPID(of: pid) else { break }
            pid = parent
            chain.append(pid)
        }
        return chain
    }

    /// Parent pid of `pid` via sysctl; nil when the lookup fails.
    private static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var size = MemoryLayout<kinfo_proc>.size
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: Int.self, capacity: size / MemoryLayout<Int>.size) {
                sysctl(&mib, 4, $0, &size, nil, 0)
            }
        }
        guard result == 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
