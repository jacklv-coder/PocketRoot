#if canImport(SwiftUI) && canImport(UIKit)
import PocketRootCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@available(iOS 18.0, *)
public struct PocketRootFileBrowserView: View {
    @StateObject private var model: PocketRootFileBrowserModel
    @State private var selectedEntry: PocketRootFileEntry?
    @State private var nameAction: PocketRootFileNameAction?
    @State private var proposedName = ""
    @State private var pendingDeletion: PocketRootFileEntry?
    @State private var operationErrorMessage: String?
    @State private var isImportingFile = false
    @State private var sharePayload: PocketRootSharePayload?
    private let allowsFileOperations: Bool
    private let onMutation: (@MainActor () async -> Void)?

    public init(
        system: PocketRootSystem,
        initialPath: String = "/root",
        allowsFileOperations: Bool = true
    ) {
        let browser = PocketRootFileBrowser(system: system)
        self.allowsFileOperations = allowsFileOperations
        onMutation = nil
        _model = StateObject(
            wrappedValue: PocketRootFileBrowserModel(
                browser: browser,
                path: initialPath,
                onMutation: nil
            )
        )
    }

    private init(
        browser: PocketRootFileBrowser,
        path: String,
        allowsFileOperations: Bool,
        onMutation: @escaping @MainActor () async -> Void
    ) {
        self.allowsFileOperations = allowsFileOperations
        self.onMutation = onMutation
        _model = StateObject(
            wrappedValue: PocketRootFileBrowserModel(
                browser: browser,
                path: path,
                onMutation: onMutation
            )
        )
    }

    public var body: some View {
        List {
            if model.isLoading, model.visibleRows.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
            if let errorMessage = model.errorMessage {
                ContentUnavailableView(
                    "Unable to Open Folder",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            }
            ForEach(model.visibleRows) { row in
                PocketRootFileTreeRowView(
                    row: row,
                    isExpanded: model.isExpanded(row.entry.path),
                    isLoading: model.isLoading(row.entry.path),
                    isEntryEnabled:
                        !model.isLoading
                            && !model.isMutating
                            && !model.hasPendingExpansionRequests,
                    isDisclosureEnabled:
                        !model.isLoading
                            && !model.isMutating
                            && (
                                !model.hasPendingExpansionRequests
                                    || model.isLoading(row.entry.path)
                            ),
                    allowsFileOperations:
                        allowsFileOperations && !model.isBusy,
                    expansionError: model.expansionError(row.entry.path),
                    toggleExpansion: {
                        model.toggleExpansion(for: row.entry)
                    },
                    openEntry: {
                        selectedEntry = row.entry
                    },
                    renameEntry: {
                        presentNameAction(.rename(row.entry))
                    },
                    deleteEntry: {
                        pendingDeletion = row.entry
                    },
                    exportEntry: {
                        Task {
                            await performOperation {
                                sharePayload = try await model.export(row.entry)
                            }
                        }
                    }
                )
            }
        }
        .accessibilityIdentifier("PocketRootFiles.list")
        .navigationTitle(model.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsFileOperations {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            presentNameAction(.createFile)
                        } label: {
                            Label("New File", systemImage: "doc.badge.plus")
                        }
                        Button {
                            presentNameAction(.createDirectory)
                        } label: {
                            Label("New Folder", systemImage: "folder.badge.plus")
                        }
                        Button {
                            isImportingFile = true
                        } label: {
                            Label("Import File", systemImage: "square.and.arrow.down")
                        }
                        .accessibilityIdentifier("PocketRootFiles.import")
                    } label: {
                        Label("File Actions", systemImage: "plus")
                    }
                    .disabled(model.isBusy)
                    .accessibilityIdentifier("PocketRootFiles.actions")
                }
            }
        }
        .refreshable {
            await model.reload()
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .failure(let error) = result,
               Self.isUserCancellation(error)
            {
                return
            }
            Task {
                await performOperation {
                    let url = try result.get().first
                        .unwrap(or: PocketRootFileTransferUIError.noSelectedFile)
                    let imported = try await Self.readImportFile(at: url)
                    try await model.importFile(
                        data: imported.data,
                        named: imported.name
                    )
                }
            }
        }
        .sheet(
            item: $sharePayload,
            onDismiss: {
                if let payload = sharePayload {
                    model.removeExport(payload)
                    sharePayload = nil
                }
            }
        ) { payload in
            PocketRootActivityView(
                url: payload.url,
                completion: {
                    model.removeExport(payload)
                    sharePayload = nil
                }
            )
        }
        .task {
            await model.loadIfNeeded()
        }
        .onDisappear {
            model.cancelPendingExpansionRequests()
        }
        .navigationDestination(item: $selectedEntry) { entry in
            if entry.kind == .directory {
                PocketRootFileBrowserView(
                    browser: model.browser,
                    path: entry.path,
                    allowsFileOperations: allowsFileOperations,
                    onMutation: {
                        await model.reload()
                        await onMutation?()
                    }
                )
            } else {
                PocketRootFilePreviewView(
                    browser: model.browser,
                    entry: entry
                )
            }
        }
        .overlay {
            if model.isMutating {
                ProgressView("Updating Files…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("PocketRootFiles.operationProgress")
            }
        }
        .alert(
            nameAction?.title ?? "Name",
            isPresented: isShowingNameAction
        ) {
            TextField("Name", text: $proposedName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(nameAction?.submitTitle ?? "Save") {
                submitNameAction()
            }
            .disabled(proposedName.isEmpty)
            Button("Cancel", role: .cancel) {
                nameAction = nil
            }
        } message: {
            Text(nameAction?.message ?? "")
        }
        .confirmationDialog(
            "Delete Item?",
            isPresented: isShowingDeleteConfirmation,
            presenting: pendingDeletion
        ) { entry in
            Button("Delete \(entry.name)", role: .destructive) {
                pendingDeletion = nil
                Task {
                    await performOperation {
                        try await model.delete(entry)
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { entry in
            if entry.kind == .directory {
                Text("The folder and all of its contents will be permanently deleted.")
            } else {
                Text("This item will be permanently deleted.")
            }
        }
        .alert(
            "File Operation Failed",
            isPresented: isShowingOperationError
        ) {
            Button("OK", role: .cancel) {
                operationErrorMessage = nil
            }
        } message: {
            Text(operationErrorMessage ?? "")
        }
    }

    private var isShowingNameAction: Binding<Bool> {
        Binding(
            get: { nameAction != nil },
            set: { isPresented in
                if !isPresented {
                    nameAction = nil
                }
            }
        )
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletion = nil
                }
            }
        )
    }

    private var isShowingOperationError: Binding<Bool> {
        Binding(
            get: { operationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    operationErrorMessage = nil
                }
            }
        )
    }

    private func presentNameAction(_ action: PocketRootFileNameAction) {
        nameAction = action
        proposedName = action.initialName
    }

    private func submitNameAction() {
        guard let action = nameAction else {
            return
        }
        let name = proposedName
        nameAction = nil
        Task {
            await performOperation {
                switch action {
                case .createFile:
                    try await model.createFile(named: name)
                case .createDirectory:
                    try await model.createDirectory(named: name)
                case .rename(let entry):
                    try await model.rename(entry, to: name)
                }
            }
        }
    }

    private func performOperation(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
        } catch {
            operationErrorMessage = error.localizedDescription
        }
    }

    private static func isUserCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain
            && error.code == NSUserCancelledError
    }

    private static func readImportFile(
        at url: URL
    ) async throws -> (name: String, data: Data) {
        try await Task.detached {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let values = try url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                throw PocketRootFileTransferUIError.notRegularFile
            }
            if let size = values.fileSize,
               size > PocketRootFileBrowser.maximumTransferBytes
            {
                throw PocketRootFileBrowserError.transferTooLarge(
                    maximumBytes: PocketRootFileBrowser.maximumTransferBytes
                )
            }
            let maximumBytes = PocketRootFileBrowser.maximumTransferBytes
            let maximumReadBytes = maximumBytes + 1
            let handle = try FileHandle(forReadingFrom: url)
            defer {
                try? handle.close()
            }
            var data = Data()
            data.reserveCapacity(maximumReadBytes)
            while data.count < maximumReadBytes {
                let nextCount = min(64 * 1_024, maximumReadBytes - data.count)
                guard let chunk = try handle.read(upToCount: nextCount),
                      !chunk.isEmpty
                else {
                    break
                }
                data.append(chunk)
            }
            guard data.count <= PocketRootFileBrowser.maximumTransferBytes else {
                throw PocketRootFileBrowserError.transferTooLarge(
                    maximumBytes: PocketRootFileBrowser.maximumTransferBytes
                )
            }
            return (url.lastPathComponent, data)
        }.value
    }
}

@available(iOS 18.0, *)
public final class PocketRootFileBrowserViewController:
    UIHostingController<AnyView>
{
    public init(
        system: PocketRootSystem,
        initialPath: String = "/root",
        allowsFileOperations: Bool = true
    ) {
        super.init(
            rootView: AnyView(
                NavigationStack {
                    PocketRootFileBrowserView(
                        system: system,
                        initialPath: initialPath,
                        allowsFileOperations: allowsFileOperations
                    )
                }
            )
        )
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("Use init(system:initialPath:) instead.")
    }
}

@available(iOS 18.0, *)
@MainActor
private final class PocketRootFileBrowserModel: ObservableObject {
    let browser: PocketRootFileBrowser
    let path: String

    @Published private var tree = PocketRootFileTreeState()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private var loadingDirectories: Set<String> = []
    @Published private var expansionErrors: [String: String] = [:]
    @Published private var isExporting = false
    private var didLoad = false
    private var requestGeneration: UInt64 = 0
    private var expansionRequestIDs: [String: UUID] = [:]
    private var expansionTasks: [String: Task<Void, Never>] = [:]
    private let onMutation: (@MainActor () async -> Void)?

    var visibleRows: [PocketRootFileTreeRow] {
        tree.visibleRows
    }

    var displayName: String {
        path == "/" ? "/" : String(path.split(separator: "/").last ?? "/")
    }

    var hasPendingExpansionRequests: Bool {
        !expansionRequestIDs.isEmpty
    }

    var isBusy: Bool {
        isLoading || isMutating || isExporting || hasPendingExpansionRequests
    }

    @Published private(set) var isMutating = false

    init(
        browser: PocketRootFileBrowser,
        path: String,
        onMutation: (@MainActor () async -> Void)?
    ) {
        self.browser = browser
        self.path = path
        self.onMutation = onMutation
    }

    func loadIfNeeded() async {
        guard !didLoad else {
            return
        }
        await reload()
    }

    func reload() async {
        cancelPendingExpansionRequests()
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil
        expansionErrors = [:]
        defer {
            if generation == requestGeneration {
                isLoading = false
                didLoad = true
            }
        }
        do {
            let entries = try await browser.listDirectory(at: path)
            try Task.checkCancellation()
            guard generation == requestGeneration else {
                return
            }
            var refreshedTree = tree.refreshSnapshot(rootEntries: entries)
            var refreshedExpansionErrors: [String: String] = [:]
            let expandedDirectories = refreshedTree.expandedDirectories
            for directoryPath in expandedDirectories.sorted(
                by: Self.shallowerPathFirst
            ) {
                guard refreshedTree.entry(at: directoryPath)?.kind
                    == .directory
                else {
                    refreshedTree.collapse(directoryPath)
                    continue
                }
                do {
                    let children = try await browser.listDirectory(
                        at: directoryPath
                    )
                    try Task.checkCancellation()
                    guard generation == requestGeneration else {
                        return
                    }
                    refreshedTree.replaceChildren(
                        children,
                        of: directoryPath
                    )
                } catch is CancellationError {
                    return
                } catch {
                    guard generation == requestGeneration else {
                        return
                    }
                    refreshedExpansionErrors[directoryPath] =
                        error.localizedDescription
                }
            }
            guard generation == requestGeneration else {
                return
            }
            tree = refreshedTree
            expansionErrors = refreshedExpansionErrors
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration else {
                return
            }
            tree.replaceRootEntries([])
            errorMessage = error.localizedDescription
        }
    }

    func toggleExpansion(for entry: PocketRootFileEntry) {
        guard entry.kind == .directory else {
            return
        }
        if tree.isExpanded(entry.path) {
            tree.collapse(entry.path)
            cancelExpansionRequests(atOrBelow: entry.path)
            return
        }

        tree.expand(entry.path)
        expansionErrors[entry.path] = nil
        guard !tree.hasLoadedChildren(of: entry.path),
              expansionRequestIDs[entry.path] == nil
        else {
            return
        }

        let directoryPath = entry.path
        let requestID = UUID()
        let generation = requestGeneration
        expansionRequestIDs[directoryPath] = requestID
        loadingDirectories.insert(directoryPath)

        let task = Task { @MainActor [weak self, browser] in
            do {
                let children = try await browser.listDirectory(
                    at: directoryPath
                )
                try Task.checkCancellation()
                self?.finishExpansionRequest(
                    at: directoryPath,
                    requestID: requestID,
                    generation: generation,
                    result: .success(children)
                )
            } catch is CancellationError {
                self?.finishExpansionRequest(
                    at: directoryPath,
                    requestID: requestID,
                    generation: generation,
                    result: nil
                )
            } catch {
                self?.finishExpansionRequest(
                    at: directoryPath,
                    requestID: requestID,
                    generation: generation,
                    result: .failure(error)
                )
            }
        }
        expansionTasks[directoryPath] = task
        if expansionRequestIDs[directoryPath] != requestID {
            expansionTasks[directoryPath] = nil
        }
    }

    func cancelPendingExpansionRequests() {
        requestGeneration &+= 1
        let directoryPaths = Array(expansionRequestIDs.keys)
        let tasks = expansionTasks.values
        expansionRequestIDs = [:]
        expansionTasks = [:]
        loadingDirectories = []
        isLoading = false
        tree.collapse(directoriesAt: directoryPaths)
        for task in tasks {
            task.cancel()
        }
    }

    func isExpanded(_ path: String) -> Bool {
        tree.isExpanded(path)
    }

    func isLoading(_ path: String) -> Bool {
        loadingDirectories.contains(path)
    }

    func expansionError(_ path: String) -> String? {
        expansionErrors[path]
    }

    func createFile(named name: String) async throws {
        try await performMutation {
            _ = try await browser.createFile(named: name, in: path)
        }
    }

    func createDirectory(named name: String) async throws {
        try await performMutation {
            _ = try await browser.createDirectory(named: name, in: path)
        }
    }

    func delete(_ entry: PocketRootFileEntry) async throws {
        try await performMutation {
            try await browser.deleteItem(
                at: entry.path,
                recursively: entry.kind == .directory
            )
        }
    }

    func rename(
        _ entry: PocketRootFileEntry,
        to name: String
    ) async throws {
        try await performMutation {
            _ = try await browser.renameItem(at: entry.path, to: name)
        }
    }

    func importFile(data: Data, named name: String) async throws {
        try await performMutation {
            _ = try await browser.importFile(data: data, named: name, in: path)
        }
    }

    func export(_ entry: PocketRootFileEntry) async throws -> PocketRootSharePayload {
        guard entry.kind == .file else {
            throw PocketRootFileTransferUIError.notRegularFile
        }
        guard !isExporting else {
            throw PocketRootFileTransferUIError.operationInProgress
        }
        isExporting = true
        defer {
            isExporting = false
        }
        let exported = try await browser.exportFile(at: entry.path)
        return try await Task.detached {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "PocketRootExport-\(UUID().uuidString)",
                    isDirectory: true
                )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false
            )
            let url = directory.appendingPathComponent(
                exported.suggestedFilename,
                isDirectory: false
            )
            do {
                try exported.data.write(to: url, options: .atomic)
                return PocketRootSharePayload(url: url, directoryURL: directory)
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }.value
    }

    func removeExport(_ payload: PocketRootSharePayload) {
        let directoryURL = payload.directoryURL
        Task.detached {
            try? FileManager.default.removeItem(at: directoryURL)
        }
    }

    private func performMutation(
        _ operation: () async throws -> Void
    ) async throws {
        guard !isMutating else {
            return
        }
        cancelPendingExpansionRequests()
        isMutating = true
        defer {
            isMutating = false
        }
        let result: Result<Void, Error>
        do {
            try await operation()
            result = .success(())
        } catch {
            result = .failure(error)
        }
        await reload()
        await onMutation?()
        try result.get()
    }

    private func finishExpansionRequest(
        at directoryPath: String,
        requestID: UUID,
        generation: UInt64,
        result: Result<[PocketRootFileEntry], Error>?
    ) {
        guard expansionRequestIDs[directoryPath] == requestID else {
            return
        }
        expansionRequestIDs[directoryPath] = nil
        expansionTasks[directoryPath] = nil
        loadingDirectories.remove(directoryPath)

        guard generation == requestGeneration,
              tree.isExpanded(directoryPath),
              let result
        else {
            return
        }
        switch result {
        case .success(let children):
            tree.replaceChildren(children, of: directoryPath)
        case .failure(let error):
            expansionErrors[directoryPath] = error.localizedDescription
        }
    }

    private func cancelExpansionRequests(atOrBelow directoryPath: String) {
        let prefix = directoryPath + "/"
        let paths = expansionRequestIDs.keys.filter {
            $0 == directoryPath || $0.hasPrefix(prefix)
        }
        tree.collapse(directoriesAt: paths)
        for path in paths {
            expansionRequestIDs[path] = nil
            loadingDirectories.remove(path)
            expansionTasks.removeValue(forKey: path)?.cancel()
        }
    }

    private static func shallowerPathFirst(
        _ lhs: String,
        _ rhs: String
    ) -> Bool {
        let lhsDepth = lhs.split(separator: "/").count
        let rhsDepth = rhs.split(separator: "/").count
        if lhsDepth == rhsDepth {
            return lhs < rhs
        }
        return lhsDepth < rhsDepth
    }
}

@available(iOS 18.0, *)
private struct PocketRootFileTreeRowView: View {
    let row: PocketRootFileTreeRow
    let isExpanded: Bool
    let isLoading: Bool
    let isEntryEnabled: Bool
    let isDisclosureEnabled: Bool
    let allowsFileOperations: Bool
    let expansionError: String?
    let toggleExpansion: () -> Void
    let openEntry: () -> Void
    let renameEntry: () -> Void
    let deleteEntry: () -> Void
    let exportEntry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                disclosureControl
                Button(action: openEntry) {
                    PocketRootFileEntryRow(entry: row.entry)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(
                    !row.entry.kind.allowsOpening || !isEntryEnabled
                )
                .accessibilityIdentifier(
                    "PocketRootFiles.entry.\(row.entry.path)"
                )
            }
            .padding(.leading, CGFloat(row.depth) * 22)

            if let expansionError, isExpanded {
                Label(
                    expansionError,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.leading, CGFloat(row.depth + 1) * 22 + 32)
                .accessibilityIdentifier(
                    "PocketRootFiles.error.\(row.entry.path)"
                )
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if row.entry.kind == .file {
                Button(action: exportEntry) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(.green)
            }
            if allowsFileOperations {
                Button(role: .destructive, action: deleteEntry) {
                    Label("Delete", systemImage: "trash")
                }
                Button(action: renameEntry) {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
        .contextMenu {
            if row.entry.kind == .file {
                Button(action: exportEntry) {
                    Label("Share / Export", systemImage: "square.and.arrow.up")
                }
            }
            if allowsFileOperations {
                Button(action: renameEntry) {
                    Label("Rename", systemImage: "pencil")
                }
                Button(role: .destructive, action: deleteEntry) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var disclosureControl: some View {
        if row.entry.kind == .directory {
            Button(action: toggleExpansion) {
                Group {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(
                            systemName: isExpanded
                                ? "chevron.down"
                                : "chevron.right"
                        )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }
                .frame(width: 28, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isDisclosureEnabled)
            .accessibilityLabel(
                isExpanded ? "Collapse \(row.entry.name)" : "Expand \(row.entry.name)"
            )
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier(
                "PocketRootFiles.disclosure.\(row.entry.path)"
            )
        } else {
            Color.clear
                .frame(width: 28, height: 34)
                .accessibilityHidden(true)
        }
    }
}

@available(iOS 18.0, *)
private struct PocketRootSharePayload: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let directoryURL: URL
}

@available(iOS 18.0, *)
private struct PocketRootActivityView: UIViewControllerRepresentable {
    let url: URL
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion()
        }
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {}
}

private enum PocketRootFileTransferUIError: LocalizedError {
    case noSelectedFile
    case notRegularFile
    case operationInProgress

    var errorDescription: String? {
        switch self {
        case .noSelectedFile:
            "No file was selected."
        case .notRegularFile:
            "Only regular files can be transferred."
        case .operationInProgress:
            "Another file export is already in progress."
        }
    }
}

private extension Optional {
    func unwrap(or error: @autoclosure () -> Error) throws -> Wrapped {
        guard let self else {
            throw error()
        }
        return self
    }
}

@available(iOS 18.0, *)
private enum PocketRootFileNameAction {
    case createFile
    case createDirectory
    case rename(PocketRootFileEntry)

    var title: String {
        switch self {
        case .createFile: "New File"
        case .createDirectory: "New Folder"
        case .rename: "Rename"
        }
    }

    var submitTitle: String {
        switch self {
        case .createFile, .createDirectory: "Create"
        case .rename: "Rename"
        }
    }

    var message: String {
        switch self {
        case .createFile: "Enter a name for the new empty file."
        case .createDirectory: "Enter a name for the new folder."
        case .rename: "Enter a new name. Existing items will not be replaced."
        }
    }

    var initialName: String {
        switch self {
        case .createFile, .createDirectory: ""
        case .rename(let entry): entry.name
        }
    }
}

@available(iOS 18.0, *)
private struct PocketRootFileEntryRow: View {
    let entry: PocketRootFileEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(entry.kind == .directory ? .blue : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .lineLimit(1)
                if entry.kind == .file {
                    Text(entry.size.formatted(.byteCount(style: .file)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var iconName: String {
        switch entry.kind {
        case .directory: "folder"
        case .file: "doc"
        case .symbolicLink: "link"
        case .other: "questionmark.square.dashed"
        }
    }
}

@available(iOS 18.0, *)
private struct PocketRootFilePreviewView: View {
    let browser: PocketRootFileBrowser
    let entry: PocketRootFileEntry

    @State private var preview: PocketRootFilePreview?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let preview {
                if let text = preview.text {
                    ScrollView([.horizontal, .vertical]) {
                        Text(text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("PocketRootFiles.preview")
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding()
                    }
                    .safeAreaInset(edge: .bottom) {
                        if preview.isTruncated {
                            Text("Preview truncated")
                                .font(.caption)
                                .padding(8)
                                .frame(maxWidth: .infinity)
                                .background(.thinMaterial)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Binary File",
                        systemImage: "doc.badge.ellipsis",
                        description: Text(
                            "\(preview.data.count.formatted()) preview bytes"
                        )
                    )
                }
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Preview File",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                preview = try await browser.previewFile(at: entry.path)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
#endif
