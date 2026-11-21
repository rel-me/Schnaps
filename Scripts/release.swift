#!/usr/bin/env swift
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let manager = FileManager.default

struct PackagingFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}

struct CommandFailure: LocalizedError {
    let executable: String
    let status: Int32
    let diagnostic: String
    var errorDescription: String? { "\(executable) exited with status \(status)." }
}

func report(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

enum Capture {
    case standardOutput
    case standardError
}

@discardableResult
func run(_ executable: String, _ arguments: [String], capture: Capture? = nil, directory: URL? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory ?? root
    let pipe = Pipe()
    if capture == .standardOutput { process.standardOutput = pipe }
    if capture == .standardError { process.standardError = pipe }
    try process.run()
    let data = capture != nil ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
    process.waitUntilExit()
    if capture == .standardError { FileHandle.standardError.write(data) }
    guard process.terminationStatus == 0 else {
        throw CommandFailure(executable: executable, status: process.terminationStatus,
                             diagnostic: capture == .standardError ? String(decoding: data, as: UTF8.self) : "")
    }
    return capture == .standardOutput ? String(decoding: data, as: UTF8.self) : ""
}

func signDiskImage(_ dmg: URL, identity: String) throws {
    let arguments = ["--force", "--sign", identity, "--timestamp", dmg.path]
    for retryDelay: TimeInterval? in [2, 5, nil] {
        do {
            try run("/usr/bin/codesign", arguments, capture: .standardError)
            return
        } catch let error as CommandFailure {
            let diagnostic = error.diagnostic.lowercased()
            guard diagnostic.contains("a timestamp was expected but was not found")
                || diagnostic.contains("the timestamp service is not available") else {
                throw error
            }
            guard let retryDelay else {
                throw PackagingFailure("Could not obtain a secure timestamp for \(dmg.lastPathComponent) after three attempts. Check access to timestamp.apple.com, then rerun the original release command.")
            }
            report("Apple's secure timestamp was unavailable for \(dmg.lastPathComponent). Retrying in \(Int(retryDelay)) seconds.")
            Thread.sleep(forTimeInterval: retryDelay)
        }
    }
}

func packageRelease() throws {
    let environment = ProcessInfo.processInfo.environment
    let config = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: environment["SCHNAPS_RELEASE_CONFIG"] ?? root.appendingPathComponent("Config/Release.json").path))) as! [String: String]
    guard let identity = environment["SCHNAPS_SIGN_IDENTITY"], identity.hasPrefix("Developer ID Application:") else {
        throw PackagingFailure("Set SCHNAPS_SIGN_IDENTITY to your Developer ID Application signing identity.")
    }
    let profile = environment["SCHNAPS_NOTARY_PROFILE"] ?? "Schnaps"
    let version = config["version"]!, account = config["keychainAccount"]!
    let output = root.appendingPathComponent("build/releases/\(version)")
    guard !manager.fileExists(atPath: output.appendingPathComponent("appcast.xml").path) else {
        throw PackagingFailure("This version is already packaged. Publish the existing verified files or increment the version before building again.")
    }
    try manager.createDirectory(at: output, withIntermediateDirectories: true)

    func notarize(_ file: URL) throws {
        let response = try run("/usr/bin/xcrun", ["notarytool", "submit", file.path, "--keychain-profile", profile, "--wait", "--output-format", "json"], capture: .standardOutput)
        let result = try JSONSerialization.jsonObject(with: Data(response.utf8)) as! [String: Any]
        try Data(response.utf8).write(to: output.appendingPathComponent(file.lastPathComponent + ".notary.json"))
        guard result["status"] as? String == "Accepted" else {
            throw PackagingFailure("Notarization rejected (submission \(result["id"] ?? "unknown")). See the saved report for \(file.lastPathComponent).")
        }
        print("Notarization accepted: \(file.lastPathComponent)")
    }

    try run("/usr/bin/xcrun", ["swift", "Scripts/build-app.swift", "--universal"])
    let app = root.appendingPathComponent("build/Schnaps.app")
    let zip = output.appendingPathComponent("Schnaps-notarization.zip")
    try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
    try notarize(zip)
    try run("/usr/bin/xcrun", ["stapler", "staple", app.path])
    try run("/usr/bin/xcrun", ["stapler", "validate", app.path])
    try run("/usr/sbin/spctl", ["--assess", "--type", "execute", "--verbose=2", app.path])
    let staging = root.appendingPathComponent("build/DMG-Staging")
    if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
    try manager.createDirectory(at: staging, withIntermediateDirectories: true)
    try run("/usr/bin/ditto", [app.path, staging.appendingPathComponent("Schnaps.app").path])
    try manager.createSymbolicLink(atPath: staging.appendingPathComponent("Applications").path, withDestinationPath: "/Applications")
    let dmg = output.appendingPathComponent("Schnaps-\(version).dmg")
    try run("/usr/bin/hdiutil", ["create", "-volname", "Schnaps \(version)", "-srcfolder", staging.path, "-format", "UDZO", "-ov", dmg.path])
    try signDiskImage(dmg, identity: identity)
    try notarize(dmg)
    try run("/usr/bin/xcrun", ["stapler", "staple", dmg.path])
    try run("/usr/bin/xcrun", ["stapler", "validate", dmg.path])
    try run("/usr/bin/hdiutil", ["verify", dmg.path])
    // Do not let generate_appcast discover the intermediate ZIP as a second update.
    try manager.removeItem(at: zip)
    let notes = root.appendingPathComponent("releases/\(version).md")
    if manager.fileExists(atPath: notes.path) {
        let destination = output.appendingPathComponent("Schnaps-\(version).md")
        if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
        try manager.copyItem(at: notes, to: destination)
    }
    let tools = root.appendingPathComponent(".build/artifacts/sparkle/Sparkle/bin")
    try run(tools.appendingPathComponent("generate_appcast").path,
            (config["defaultChannel"] == "beta" ? ["--channel", "beta"] : []) + ["--account", account, "--download-url-prefix", "https://github.com/\(config["repository"]!)/releases/download/v\(version)/", "--embed-release-notes", output.path])
    let appcast = output.appendingPathComponent("appcast.xml")
    try run(tools.appendingPathComponent("sign_update").path, ["--account", account, "--verify", appcast.path])
    let xml = try XMLDocument(contentsOf: appcast)
    let enclosure = try xml.nodes(forXPath: "//enclosure").first as! XMLElement
    let signature = enclosure.attribute(forName: "sparkle:edSignature")!.stringValue!
    try run(tools.appendingPathComponent("sign_update").path, ["--account", account, "--verify", dmg.path, signature])
    let alias = output.appendingPathComponent("Schnaps.dmg")
    if manager.fileExists(atPath: alias.path) { try manager.removeItem(at: alias) }
    try manager.copyItem(at: dmg, to: alias)
    let checksums = try run("/usr/bin/shasum", ["-a", "256", dmg.lastPathComponent, alias.lastPathComponent], capture: .standardOutput, directory: output)
    try Data(checksums.utf8).write(to: output.appendingPathComponent("SHA256SUMS"))
    try Data("verified\n".utf8).write(to: output.appendingPathComponent("packaged.txt"))
    print("Ready to publish: \(output.path)")
}

do {
    try packageRelease()
} catch {
    report("Packaging failed: \(error.localizedDescription)")
    exit(1)
}
