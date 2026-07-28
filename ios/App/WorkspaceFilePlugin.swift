import Foundation
import UIKit
import Capacitor
import UniformTypeIdentifiers

@objc(WorkspaceFilePlugin)
public class WorkspaceFilePlugin: CAPPlugin, CAPBridgedPlugin, UIDocumentPickerDelegate {

    public let identifier = "WorkspaceFilePlugin"
    public let jsName = "WorkspaceFile"

    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "openFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "saveAs", returnType: CAPPluginReturnPromise),

        CAPPluginMethod(name: "chooseBackupFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getBackupFileInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "writeBackupFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "exportDatedBackup", returnType: CAPPluginReturnPromise)
    ]

    private var pendingCall: CAPPluginCall?
    private var pendingKind: String?
    private var pendingCompanyId: String?
    private var pendingTempURL: URL?

    private let workspaceBookmarkKey = "FU_WORKSPACE_BOOKMARK"

    // MARK: - Workspace

    @objc public func openFile(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.pendingCall = call
            self.pendingKind = "workspaceOpen"

            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [UTType.json],
                asCopy: false
            )

            picker.delegate = self
            picker.allowsMultipleSelection = false
            self.bridge?.viewController?.present(picker, animated: true)
        }
    }

    @objc public func saveFile(_ call: CAPPluginCall) {
        guard let json = call.getString("json") else {
            call.reject("Missing 'json'")
            return
        }

        guard let url = resolveBookmark(forKey: workspaceBookmarkKey) else {
            saveAs(call)
            return
        }

        writeText(json, to: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    call.resolve([
                        "ok": true,
                        "name": url.lastPathComponent
                    ])

                case .failure(let error):
                    call.reject(
                        "Failed to save workspace: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    @objc public func saveAs(_ call: CAPPluginCall) {
        guard let json = call.getString("json") else {
            call.reject("Missing 'json'")
            return
        }

        let suggestedName = safeJSONFilename(
            call.getString("suggestedName"),
            fallback: "bookkeeping.json"
        )

        presentJSONExport(
            call: call,
            kind: "workspaceSaveAs",
            companyId: nil,
            filename: suggestedName,
            json: json
        )
    }

    // MARK: - Automatic base backup file

    @objc public func chooseBackupFile(_ call: CAPPluginCall) {
        guard let companyId = normalizedCompanyId(
            call.getString("companyId")
        ) else {
            call.reject("Missing 'companyId'")
            return
        }

        guard let json = call.getString("json") else {
            call.reject("Missing 'json'")
            return
        }

        let suggestedName = safeJSONFilename(
            call.getString("suggestedName"),
            fallback: "FU-Bookkeeping_backup.json"
        )

        presentJSONExport(
            call: call,
            kind: "backupBase",
            companyId: companyId,
            filename: suggestedName,
            json: json
        )
    }

    @objc public func getBackupFileInfo(_ call: CAPPluginCall) {
        guard let companyId = normalizedCompanyId(
            call.getString("companyId")
        ) else {
            call.reject("Missing 'companyId'")
            return
        }

        let key = backupBookmarkKey(companyId: companyId)

        guard let url = resolveBookmark(forKey: key) else {
            call.resolve([
                "selected": false
            ])
            return
        }

        call.resolve([
            "selected": true,
            "name": url.lastPathComponent
        ])
    }

    @objc public func writeBackupFile(_ call: CAPPluginCall) {
        guard let companyId = normalizedCompanyId(
            call.getString("companyId")
        ) else {
            call.reject("Missing 'companyId'")
            return
        }

        guard let json = call.getString("json") else {
            call.reject("Missing 'json'")
            return
        }

        let key = backupBookmarkKey(companyId: companyId)

        guard let url = resolveBookmark(forKey: key) else {
            call.reject("No backup file selected")
            return
        }

        writeText(json, to: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    call.resolve([
                        "ok": true,
                        "name": url.lastPathComponent
                    ])

                case .failure(let error):
                    call.reject(
                        "Backup write failed: \(error.localizedDescription)"
                    )
                }
            }
        }
    }

    // MARK: - Manual dated backup copy

    @objc public func exportDatedBackup(_ call: CAPPluginCall) {
        guard let json = call.getString("json") else {
            call.reject("Missing 'json'")
            return
        }

        let filename = safeJSONFilename(
            call.getString("filename"),
            fallback: "FU-Bookkeeping_backup.json"
        )

        presentJSONExport(
            call: call,
            kind: "backupDated",
            companyId: nil,
            filename: filename,
            json: json
        )
    }

    // MARK: - Export helper

    private func presentJSONExport(
        call: CAPPluginCall,
        kind: String,
        companyId: String?,
        filename: String,
        json: String
    ) {
        DispatchQueue.main.async {
            do {
                let tempFolder = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        UUID().uuidString,
                        isDirectory: true
                    )

                try FileManager.default.createDirectory(
                    at: tempFolder,
                    withIntermediateDirectories: true
                )

                let tempURL = tempFolder.appendingPathComponent(
                    filename,
                    isDirectory: false
                )

                guard let data = json.data(using: .utf8) else {
                    throw NSError(
                        domain: "WorkspaceFile",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Could not encode JSON"
                        ]
                    )
                }

                try data.write(to: tempURL, options: .atomic)

                self.pendingCall = call
                self.pendingKind = kind
                self.pendingCompanyId = companyId
                self.pendingTempURL = tempURL

                let picker = UIDocumentPickerViewController(
                    forExporting: [tempURL],
                    asCopy: true
                )

                picker.delegate = self
                self.bridge?.viewController?.present(
                    picker,
                    animated: true
                )
            } catch {
                self.clearPending()
                call.reject(
                    "Could not prepare export: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Document picker

    public func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let call = pendingCall else {
            clearPending()
            return
        }

        guard let selectedURL = urls.first else {
            call.reject("No file selected")
            clearPending()
            return
        }

        let kind = pendingKind ?? ""

        if kind == "workspaceOpen" {
            let didAccess =
                selectedURL.startAccessingSecurityScopedResource()

            defer {
                if didAccess {
                    selectedURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: selectedURL)

                guard let json = String(
                    data: data,
                    encoding: .utf8
                ) else {
                    throw NSError(
                        domain: "WorkspaceFile",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "File is not valid UTF-8"
                        ]
                    )
                }

                try saveBookmark(
                    for: selectedURL,
                    key: workspaceBookmarkKey
                )

                call.resolve([
                    "json": json,
                    "name": selectedURL.lastPathComponent
                ])
            } catch {
                call.reject(
                    "Failed to read file: \(error.localizedDescription)"
                )
            }

            clearPending()
            return
        }

        if kind == "workspaceSaveAs" {
            do {
                try saveBookmark(
                    for: selectedURL,
                    key: workspaceBookmarkKey
                )

                call.resolve([
                    "ok": true,
                    "name": selectedURL.lastPathComponent
                ])
            } catch {
                call.reject(
                    "Could not retain workspace access: " +
                    error.localizedDescription
                )
            }

            clearPending()
            return
        }

        if kind == "backupBase" {
            guard let companyId = pendingCompanyId else {
                call.reject("Missing backup company id")
                clearPending()
                return
            }

            do {
                try saveBookmark(
                    for: selectedURL,
                    key: backupBookmarkKey(companyId: companyId)
                )

                call.resolve([
                    "selected": true,
                    "ok": true,
                    "name": selectedURL.lastPathComponent
                ])
            } catch {
                call.reject(
                    "Could not retain backup-file access: " +
                    error.localizedDescription
                )
            }

            clearPending()
            return
        }

        if kind == "backupDated" {
            call.resolve([
                "ok": true,
                "name": selectedURL.lastPathComponent
            ])

            clearPending()
            return
        }

        call.reject("Unknown document-picker operation")
        clearPending()
    }

    public func documentPickerWasCancelled(
        _ controller: UIDocumentPickerViewController
    ) {
        pendingCall?.reject("cancelled")
        clearPending()
    }

    // MARK: - Coordinated writes

    private func writeText(
        _ text: String,
        to url: URL,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let didAccess =
                url.startAccessingSecurityScopedResource()

            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            guard let data = text.data(using: .utf8) else {
                completion(
                    .failure(
                        NSError(
                            domain: "WorkspaceFile",
                            code: 3,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Could not encode text"
                            ]
                        )
                    )
                )
                return
            }

            var coordinationError: NSError?
            var writeError: Error?

            let coordinator = NSFileCoordinator()

            coordinator.coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    try data.write(
                        to: coordinatedURL,
                        options: .atomic
                    )
                } catch {
                    writeError = error
                }
            }

            if let coordinationError {
                completion(.failure(coordinationError))
                return
            }

            if let writeError {
                completion(.failure(writeError))
                return
            }

            completion(.success(()))
        }
    }

    // MARK: - Bookmarks and validation

    private func backupBookmarkKey(companyId: String) -> String {
        "FU_BACKUP_FILE_BOOKMARK_\(companyId)"
    }

    private func normalizedCompanyId(_ value: String?) -> String? {
        let result = String(value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return result.isEmpty ? nil : result
    }

    private func safeJSONFilename(
        _ value: String?,
        fallback: String
    ) -> String {
        let raw = String(value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidate = raw.isEmpty ? fallback : raw
        let basename = URL(fileURLWithPath: candidate).lastPathComponent

        let cleaned = basename
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")

        if cleaned.lowercased().hasSuffix(".json") {
            return cleaned
        }

        return cleaned + ".json"
    }

    private func saveBookmark(
        for url: URL,
        key: String
    ) throws {
        let data = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        UserDefaults.standard.set(data, forKey: key)
    }

    private func resolveBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.data(
            forKey: key
        ) else {
            return nil
        }

        var stale = false

        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }

        if stale {
            try? saveBookmark(for: url, key: key)
        }

        return url
    }

    private func clearPending() {
        if let tempURL = pendingTempURL {
            try? FileManager.default.removeItem(
                at: tempURL.deletingLastPathComponent()
            )
        }

        pendingCall = nil
        pendingKind = nil
        pendingCompanyId = nil
        pendingTempURL = nil
    }
}
