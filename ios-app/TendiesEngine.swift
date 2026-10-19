//
//  TendiesEngine.swift
//  AirCard-iOS
//
//  Engine for parsing, extracting, and flashing PosterBoard .tendies wallpapers.
//

import UIKit
import Foundation
import AirliftFFI

public final class TendiesEngine {
    public static let shared = TendiesEngine()

    public static var tendiesStorageDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Tendies", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    // MARK: - Import & Parse

    public func importTendie(from sourceURL: URL) async throws -> TendieItem {
        let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = sourceURL.lastPathComponent
        let baseName = (fileName as NSString).deletingPathExtension
        let destinationURL = Self.tendiesStorageDirectory.appendingPathComponent(fileName)

        if sourceURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            } catch {
                let fileData = try Data(contentsOf: sourceURL)
                try fileData.write(to: destinationURL, options: .atomic)
            }
        }

        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw NSError(
                domain: "TendiesEngine",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("Failed to store wallpaper file at %@", destinationURL.path)]
            )
        }

        // Staging extraction to inspect contents
        let tempExtractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tendie_inspect_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempExtractDir)
        }

        let extractRC = destinationURL.path.withCString { arcC in
            tempExtractDir.path.withCString { dstC in
                al_zip_extract_all(arcC, dstC)
            }
        }

        guard extractRC == 0 else {
            throw NSError(
                domain: "TendiesEngine",
                code: Int(extractRC),
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("Failed to extract .tendies zip archive (code %lld)", Int(extractRC))]
            )
        }

        // Analyze file structure
        var isContainer = false
        var unsafeContainer = false
        var descriptorCount = 0
        var posterType: TendiePosterType = .collections

        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(
            at: tempExtractDir,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )

        var candidateImages: [(url: URL, score: Int)] = []

        while let itemURL = enumerator?.nextObject() as? URL {
            let pathLower = itemURL.path.lowercased()
            let nameLower = itemURL.lastPathComponent.lowercased()

            if pathLower.contains("__macosx") || nameLower == ".ds_store" {
                continue
            }

            if pathLower.contains("/container/") || pathLower.hasSuffix("/container") {
                isContainer = true
                if nameLower.contains("pbfposterextensiondatastoresqlitedatabase.sqlite3") {
                    unsafeContainer = true
                }
            }

            // Image discovery
            let ext = itemURL.pathExtension.lowercased()
            if ["heic", "png", "jpg", "jpeg"].contains(ext) {
                var score = 10
                if pathLower.contains("proxy") || pathLower.contains("adjusted") {
                    score += 90
                } else if pathLower.contains("background") || pathLower.contains("settling") {
                    score += 70
                } else if pathLower.contains("preview") || pathLower.contains("thumb") {
                    score += 50
                } else if pathLower.contains("asset.resource") {
                    score += 40
                }
                candidateImages.append((itemURL, score))
            }
        }

        // Use findDescriptorsWithExtensions to get accurate descriptor count and poster type
        let foundDescriptors = findDescriptorsWithExtensions(in: tempExtractDir, defaultExt: "com.apple.WallpaperKit.CollectionsPoster")
        descriptorCount = max(foundDescriptors.count, 1)

        if let first = foundDescriptors.first {
            if first.ext == "com.apple.MercuryPoster" || first.ext == "com.apple.Posters.MercuryPosterApp" {
                posterType = .mercury
            } else if first.ext == "com.apple.PhotosUIPrivate.PhotosPosterProvider" {
                posterType = .suggestedPhotos
            } else {
                posterType = isContainer ? .container : .collections
            }
        } else if isContainer {
            posterType = .container
        }

        // Pick best preview image
        candidateImages.sort { $0.score > $1.score }
        var previewData: Data? = nil

        for candidate in candidateImages {
            if let img = UIImage(contentsOfFile: candidate.url.path) {
                let thumb = self.downsample(image: img, maxDimension: 600)
                if let jpeg = thumb.jpegData(compressionQuality: 0.85) {
                    previewData = jpeg
                    break
                }
            }
        }

        return TendieItem(
            name: baseName,
            fileName: fileName,
            relativePath: fileName,
            isContainer: isContainer,
            unsafeContainer: unsafeContainer,
            descriptorCount: descriptorCount,
            posterType: posterType,
            previewImageData: previewData,
            dateImported: Date(),
            isSelected: true
        )
    }

    // MARK: - Downsample Thumbnail

    private func downsample(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return image }

        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Auto-detect PosterBoard Container

    public func detectPosterBoardContainer(pairingPath: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var outContainer: UnsafeMutablePointer<CChar>? = nil
                var outError: UnsafeMutablePointer<CChar>? = nil

                let rc = pairingPath.withCString { pairC in
                    "com.apple.PosterBoard".withCString { bundleC in
                        al_find_app_container(pairC, bundleC, nil, nil, &outContainer, &outError)
                    }
                }

                if rc == 0, let p = outContainer {
                    let containerStr = String(cString: p)
                    al_string_free(p)
                    continuation.resume(returning: containerStr)
                } else {
                    let errStr = outError.flatMap { p in
                        let s = String(cString: p)
                        al_string_free(p)
                        return s
                    } ?? L10n.tr("Failed to find PosterBoard container")
                    continuation.resume(throwing: NSError(
                        domain: "TendiesEngine",
                        code: Int(rc),
                        userInfo: [NSLocalizedDescriptionKey: errStr]
                    ))
                }
            }
        }
    }

    // MARK: - Send Respring Signal via Tunnel

    public func sendRespringSignal(pairingPath: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var outError: UnsafeMutablePointer<CChar>? = nil
                let rc = pairingPath.withCString { pC in
                    al_device_respring(pC, nil, nil, &outError)
                }
                if let p = outError {
                    al_string_free(p)
                }
                continuation.resume(returning: rc == 0)
            }
        }
    }

    // MARK: - Flash Tendies to Device

    public func flashTendies(
        items: [TendieItem],
        containerPath: String,
        resetProtections: Bool,
        pairingPath: String,
        log: @escaping (String) -> Void,
        progress: @escaping (Double) -> Void
    ) async throws {
        guard !items.isEmpty else {
            log("⚠️ No wallpapers selected to flash")
            return
        }

        var normalizedContainer = containerPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedContainer.hasSuffix("/") {
            normalizedContainer = String(normalizedContainer.dropLast())
        }
        if normalizedContainer.isEmpty {
            throw NSError(
                domain: "TendiesEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("PosterBoard Container path is required.")]
            )
        }

        let majorVer = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let structVersion = (majorVer <= 16) ? 59 : 61

        log("🚀 Starting PosterBoard injection into \(normalizedContainer)")
        log("ℹ️ Target PosterBoard structure version: \(structVersion) (iOS \(majorVer))")

        let totalItems = Double(items.count)

        for (itemIndex, item) in items.enumerated() {
            log("\n📦 [\(itemIndex + 1)/\(items.count)] Processing '\(item.name)'…")

            let tempStageDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tendie_flash_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempStageDir, withIntermediateDirectories: true)
            defer {
                try? FileManager.default.removeItem(at: tempStageDir)
            }

            let extractRC = item.fileURL.path.withCString { arcC in
                tempStageDir.path.withCString { dstC in
                    al_zip_extract_all(arcC, dstC)
                }
            }
            guard extractRC == 0 else {
                log("❌ Failed to extract '\(item.name)'")
                continue
            }

            log("  🖼 Locating wallpaper descriptors…")
            let descriptors = findDescriptorsWithExtensions(in: tempStageDir, defaultExt: item.posterType.extensionBundleId)
            log("  ✨ Found \(descriptors.count) descriptor(s) to install")

            for (descIndex, descItem) in descriptors.enumerated() {
                let targetUUID = UUID().uuidString.uppercased()
                let randomizedID = Int.random(in: 10000...99999)
                log("  [\(descIndex + 1)/\(descriptors.count)] Descriptor \(targetUUID) for \(descItem.ext)…")

                // Update plist identifiers for templates/videos without suggestionMetadata
                updatePlistIdentifiers(in: descItem.url, randomizedID: randomizedID)

                // 1. Primary destination: matches descriptor extension bundle ID
                let primaryParentDir = "\(normalizedContainer)/Library/Application Support/PRBPosterExtensionDataStore/\(structVersion)/Extensions/\(descItem.ext)/descriptors"
                try await injectDescriptorFolder(
                    folderURL: descItem.url,
                    targetParentDir: primaryParentDir,
                    destName: targetUUID,
                    pairingPath: pairingPath,
                    log: log
                )

                // 2. On iOS 18+, also dual-inject to modern .Posters.<Name>App container if applicable
                var modernExt: String? = nil
                if descItem.ext == "com.apple.WallpaperKit.CollectionsPoster" {
                    modernExt = "com.apple.Posters.CollectionsPosterApp"
                } else if descItem.ext == "com.apple.MercuryPoster" {
                    modernExt = "com.apple.Posters.MercuryPosterApp"
                }

                if let modernExt = modernExt, majorVer >= 18 {
                    let modernParentDir = "\(normalizedContainer)/Library/Application Support/PRBPosterExtensionDataStore/\(structVersion)/Extensions/\(modernExt)/descriptors"
                    try? await injectDescriptorFolder(
                        folderURL: descItem.url,
                        targetParentDir: modernParentDir,
                        destName: targetUUID,
                        pairingPath: pairingPath,
                        log: log
                    )
                }
            }

            progress(Double(itemIndex + 1) / (totalItems + 1))
        }

        // Always force PosterBoard cache refresh and file protections reset
        log("\n🔄 Forcing PosterBoard cache refresh and file protections reset…")
        let stagePrefDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tendie_pref_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagePrefDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: stagePrefDir)
        }

        let prefPlistURL = stagePrefDir.appendingPathComponent("com.apple.PosterBoard.unprotectedUserDefaults.plist")
        let prefDict: [String: Any] = [
            "PBF_RESET_FILE_PROTECTIONS": true,
            "PBF_LOCALE_DID_CHANGE": true,
            "PersistedPosterContainerBundleIdentifiers": [
                "com.apple.Posters.CollectionsPosterApp",
                "com.apple.WallpaperKit.CollectionsPoster",
                "com.apple.MercuryPoster",
                "com.apple.Posters.MercuryPosterApp",
                "com.apple.PhotosUIPrivate.PhotosPosterProvider"
            ],
            "CompletedPosterBundleIdentifierMigrations": [
                "com.apple.Posters.UnityPosterApp.ExtragalacticPoster",
                "com.apple.Posters.WeatherPosterApp.WeatherPoster",
                "com.apple.Posters.UnityPosterApp.Unity2025Poster",
                "com.apple.Posters.UnityPosterApp.UnityPosterExtension",
                "com.apple.Posters.UnityPosterApp.RhizomePoster",
                "com.apple.Posters.KaleidoscopePosterApp.KaleidoscopePoster"
            ]
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: prefDict, format: .binary, options: 0)
        try plistData.write(to: prefPlistURL)

        let targetPrefDir = "\(normalizedContainer)/Library/Preferences"
        try await writeDirectoryTree(
            sourceBaseDir: stagePrefDir,
            targetBaseDir: targetPrefDir,
            pairingPath: pairingPath,
            log: log
        )

        // Also write to mobile global preferences for system daemon lookup
        let mobilePrefDir = "/var/mobile/Library/Preferences"
        try? await writeDirectoryTree(
            sourceBaseDir: stagePrefDir,
            targetBaseDir: mobilePrefDir,
            pairingPath: pairingPath,
            log: log
        )
        log("✅ PosterBoard preferences staged for reload")

        progress(1.0)
        log("\n🎉 All wallpapers injected successfully! Open Lock Screen settings or long-press lockscreen to choose your new wallpaper.")
    }

    // MARK: - Tree Writer Helper

    private func writeDirectoryTree(
        sourceBaseDir: URL,
        targetBaseDir: String,
        pairingPath: String,
        log: @escaping (String) -> Void
    ) async throws {
        let fileManager = FileManager.default

        // Gather all directories that contain files
        var dirsToWrite: Set<URL> = []
        if let enumerator = fileManager.enumerator(
            at: sourceBaseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            while let itemURL = enumerator.nextObject() as? URL {
                let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if !isDir {
                    dirsToWrite.insert(itemURL.deletingLastPathComponent())
                }
            }
        }

        // If no subfiles, write the source dir itself if not empty
        if dirsToWrite.isEmpty {
            let files = (try? fileManager.contentsOfDirectory(atPath: sourceBaseDir.path)) ?? []
            if !files.isEmpty {
                dirsToWrite.insert(sourceBaseDir)
            }
        }

        let canonicalSource = sourceBaseDir.resolvingSymlinksInPath().path

        for dir in dirsToWrite {
            let canonicalDir = dir.resolvingSymlinksInPath().path
            var relPath = ""
            if canonicalDir.hasPrefix(canonicalSource) {
                relPath = String(canonicalDir.dropFirst(canonicalSource.count))
                relPath = relPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }

            let targetDir: String
            if relPath.isEmpty {
                targetDir = targetBaseDir
            } else {
                targetDir = "\(targetBaseDir)/\(relPath)"
            }

            log("  Writing to \(targetDir)…")

            var writeOk = false
            var errDesc: String? = nil

            await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    var outError: UnsafeMutablePointer<CChar>? = nil
                    let rc = pairingPath.withCString { pairC in
                        dir.path.withCString { srcC in
                            targetDir.withCString { tgtC in
                                al_exploit_write_dir(pairC, srcC, tgtC, { _, msg in
                                    guard let msg = msg else { return }
                                    let line = String(cString: msg)
                                    DispatchQueue.main.async {
                                        AppViewModel.shared?.tendiesFlashLog.append("    " + line)
                                    }
                                }, nil, &outError)
                            }
                        }
                    }
                    if let p = outError {
                        errDesc = String(cString: p)
                        al_string_free(p)
                    }
                    writeOk = (rc == 0)
                    cont.resume()
                }
            }

            if !writeOk {
                throw NSError(
                    domain: "TendiesEngine",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: L10n.tr("Failed to write directory: %@", errDesc ?? "exploit error")]
                )
            }
        }
    }

    // MARK: - Plist Identifier Randomization (Matches Nugget implementation)

    func updatePlistIdentifiers(in folderURL: URL, randomizedID: Int) {
        // If suggestion metadata exists, the descriptor is pre-packaged with matching
        // descriptorIdentifier and wallpaper identifiers (e.g. 7400.DYNAMIC <-> 7400).
        // Randomizing only Wallpaper.plist desynchronizes PosterKit's suggestion lookup!
        let suggestionMetadataURL = folderURL.appendingPathComponent("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist")
        if FileManager.default.fileExists(atPath: suggestionMetadataURL.path) {
            return
        }

        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        while let fileURL = enumerator.nextObject() as? URL {
            let fileName = fileURL.lastPathComponent

            if fileName == "com.apple.posterkit.provider.descriptor.identifier" {
                // IMPORTANT: ONLY randomize if the file content is a pure integer!
                // For extensions like Mercury, Unity, Kaleidoscope, descriptor identifiers are
                // required string symbols (e.g. "v6x.colorA", "Unity2025")!
                // Overwriting them breaks extension lookup!
                if let content = try? String(contentsOf: fileURL, encoding: .utf8),
                   let _ = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    try? "\(randomizedID)".data(using: .utf8)?.write(to: fileURL)
                }
            } else if fileName == "com.apple.posterkit.provider.contents.userInfo" {
                if let data = try? Data(contentsOf: fileURL),
                   var plist = (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil)) as? [String: Any],
                   plist["wallpaperRepresentingIdentifier"] != nil {
                    plist["wallpaperRepresentingIdentifier"] = randomizedID
                    if let updated = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                        try? updated.write(to: fileURL)
                    }
                }
            } else if fileName.hasSuffix("Wallpaper.plist") {
                if let data = try? Data(contentsOf: fileURL),
                   var plist = (try? PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil)) as? [String: Any] {
                    plist["identifier"] = randomizedID
                    if let updated = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                        try? updated.write(to: fileURL)
                    }
                }
            }
        }
    }

    // MARK: - Folder Injector Helper (Single Atomic Move via AirTraffic)

    private func injectDescriptorFolder(
        folderURL: URL,
        targetParentDir: String,
        destName: String,
        pairingPath: String,
        log: @escaping (String) -> Void
    ) async throws {
        log("  📦 Injecting '\(destName)' into \(targetParentDir)…")
        var errDesc: String? = nil
        let ok: Bool = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var outError: UnsafeMutablePointer<CChar>? = nil
                let rc = pairingPath.withCString { pairC in
                    folderURL.path.withCString { folderC in
                        targetParentDir.withCString { parentC in
                            destName.withCString { destC in
                                al_exploit_inject_folder(
                                    pairC,
                                    folderC,
                                    parentC,
                                    destC,
                                    { _, msg in
                                        guard let msg = msg else { return }
                                        let line = String(cString: msg)
                                        DispatchQueue.main.async {
                                            AppViewModel.shared?.tendiesFlashLog.append("    " + line)
                                        }
                                    },
                                    nil,
                                    &outError
                                )
                            }
                        }
                    }
                }
                if let p = outError {
                    errDesc = String(cString: p)
                    al_string_free(p)
                }
                cont.resume(returning: rc == 0)
            }
        }

        if !ok {
            throw NSError(
                domain: "TendiesEngine",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.tr("Failed to inject descriptor: %@", errDesc ?? "exploit error")]
            )
        }
    }

    // MARK: - Find Descriptors With Targeted Extensions

    func isDescriptorFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name == "__MACOSX" { return false }

        // Must not be the container root or Library itself
        let ignoredNames: Set<String> = [
            "container", "library", "application support", "prbposterextensiondatastore",
            "extensions", "descriptors", "ordered-descriptors",
            "mercury-descriptors", "mercurydescriptors", "video-descriptors", "videodescriptors"
        ]
        if ignoredNames.contains(name.lowercased()) {
            return false
        }

        // 1. Has "versions" directory
        let versions = url.appendingPathComponent("versions")
        if fm.fileExists(atPath: versions.path) { return true }

        // 2. Has "providerInfo.plist"
        let providerInfo = url.appendingPathComponent("providerInfo.plist")
        if fm.fileExists(atPath: providerInfo.path) { return true }

        // 3. Has "com.apple.posterkit.provider.descriptor.identifier"
        let descId = url.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
        if fm.fileExists(atPath: descId.path) { return true }

        // 4. Has "Wallpaper.plist"
        let wallpaper = url.appendingPathComponent("Wallpaper.plist")
        if fm.fileExists(atPath: wallpaper.path) { return true }

        // 5. Ends with .wallpaper
        if url.pathExtension.lowercased() == "wallpaper" { return true }

        return false
    }

    func determineExtension(for folderURL: URL, defaultExt: String) -> String {
        let pathLower = folderURL.path.lowercased()

        // 1. Check path components for .../Extensions/<bundleID>/descriptors/<desc>
        let components = folderURL.pathComponents
        for i in 0..<components.count {
            if components[i].lowercased() == "extensions", i + 1 < components.count {
                let cand = components[i + 1]
                if cand.contains(".") {
                    return cand
                }
            }
            if components[i].lowercased() == "descriptors", i > 0 {
                let cand = components[i - 1]
                if cand.contains(".") && !cand.lowercased().contains("store") {
                    return cand
                }
            }
        }

        // 2. Check metadata inside suggestionMetadata.plist if present
        let metadataURL = folderURL.appendingPathComponent("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist")
        if let data = try? Data(contentsOf: metadataURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let objects = plist["$objects"] as? [Any] {
            for obj in objects {
                if let str = obj as? String {
                    if str.hasPrefix("com.apple.") && str.contains("Poster") {
                        return str
                    }
                }
            }
        }

        // 3. Check descriptor identifier content (e.g. "v6x.colorA" or "v5..." -> Mercury)
        let descIdURL = folderURL.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
        if let descId = try? String(contentsOf: descIdURL, encoding: .utf8) {
            let trimmed = descId.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("v6") || trimmed.hasPrefix("v5") || trimmed.hasPrefix("v4") || trimmed.contains(".color") {
                return "com.apple.MercuryPoster"
            }
        }

        // 4. Path string hints
        if pathLower.contains("mercury") {
            return "com.apple.MercuryPoster"
        }
        if pathLower.contains("video") || pathLower.contains("photo") {
            return "com.apple.PhotosUIPrivate.PhotosPosterProvider"
        }
        if pathLower.contains("collection") || pathLower.contains("wallpaperkit") {
            return "com.apple.WallpaperKit.CollectionsPoster"
        }
        if pathLower.contains("kaleidoscope") {
            return "com.apple.Posters.KaleidoscopePosterApp.KaleidoscopePoster"
        }
        if pathLower.contains("unity") {
            return "com.apple.Posters.UnityPosterApp.UnityPosterExtension"
        }

        return defaultExt
    }

    public func findDescriptorsWithExtensions(in rootURL: URL, defaultExt: String) -> [(ext: String, url: URL)] {
        let fileManager = FileManager.default
        var results: [(ext: String, url: URL)] = []

        if isDescriptorFolder(rootURL) {
            let ext = determineExtension(for: rootURL, defaultExt: defaultExt)
            return [(ext: ext, url: rootURL)]
        }

        // Recursive traversal to discover all descriptor directories
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [(ext: defaultExt, url: rootURL)] }

        while let itemURL = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if itemURL.lastPathComponent.hasPrefix(".") || itemURL.lastPathComponent == "__MACOSX" {
                enumerator.skipDescendants()
                continue
            }

            if isDescriptorFolder(itemURL) {
                let ext = determineExtension(for: itemURL, defaultExt: defaultExt)
                results.append((ext: ext, url: itemURL))
                enumerator.skipDescendants() // Do not look for nested descriptors inside a descriptor folder
            }
        }

        return results.isEmpty ? [(ext: defaultExt, url: rootURL)] : results
    }
}
