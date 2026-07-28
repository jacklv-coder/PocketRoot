#if canImport(SwiftUI) && canImport(UIKit)
import PocketRootCore
import SwiftUI
import UIKit

@available(iOS 18.0, *)
public struct PocketRootFileBrowserView: View {
    @StateObject private var model: PocketRootFileBrowserModel

    public init(
        system: PocketRootSystem,
        initialPath: String = "/root"
    ) {
        let browser = PocketRootFileBrowser(executor: system)
        _model = StateObject(
            wrappedValue: PocketRootFileBrowserModel(
                browser: browser,
                path: initialPath
            )
        )
    }

    private init(browser: PocketRootFileBrowser, path: String) {
        _model = StateObject(
            wrappedValue: PocketRootFileBrowserModel(
                browser: browser,
                path: path
            )
        )
    }

    public var body: some View {
        List {
            if model.isLoading, model.entries.isEmpty {
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
            ForEach(model.entries) { entry in
                NavigationLink {
                    if entry.kind == .directory {
                        PocketRootFileBrowserView(
                            browser: model.browser,
                            path: entry.path
                        )
                    } else {
                        PocketRootFilePreviewView(
                            browser: model.browser,
                            entry: entry
                        )
                    }
                } label: {
                    PocketRootFileEntryRow(entry: entry)
                }
                .disabled(entry.kind == .other)
            }
        }
        .navigationTitle(model.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.reload()
        }
        .task {
            await model.loadIfNeeded()
        }
    }
}

@available(iOS 18.0, *)
public final class PocketRootFileBrowserViewController:
    UIHostingController<AnyView>
{
    public init(
        system: PocketRootSystem,
        initialPath: String = "/root"
    ) {
        super.init(
            rootView: AnyView(
                NavigationStack {
                    PocketRootFileBrowserView(
                        system: system,
                        initialPath: initialPath
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

    @Published private(set) var entries: [PocketRootFileEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private var didLoad = false

    var displayName: String {
        path == "/" ? "/" : String(path.split(separator: "/").last ?? "/")
    }

    init(browser: PocketRootFileBrowser, path: String) {
        self.browser = browser
        self.path = path
    }

    func loadIfNeeded() async {
        guard !didLoad else {
            return
        }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            didLoad = true
        }
        do {
            entries = try await browser.listDirectory(at: path)
        } catch {
            entries = []
            errorMessage = error.localizedDescription
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
