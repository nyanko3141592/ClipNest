import SwiftUI

struct SnippetEditorView: View {
    @ObservedObject var dataStore: DataStore
    @State private var selectedID: UUID?
    @State private var editTitle = ""
    @State private var editContent = ""
    @State private var hasChanges = false
    @State private var isLoadingSnippet = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var renameTargetID: UUID?
    @State private var renameIsFolder = false
    @State private var showDeleteConfirm = false
    @State private var deleteTargetID: UUID?
    @State private var deleteIsFolder = false

    private var selectedSnippet: Snippet? { dataStore.findSnippet(id: selectedID) }
    private var selectedFolder: SnippetFolder? { dataStore.findFolder(id: selectedID) }

    /// Folder to add snippets/subfolders into. nil means root level.
    private var resolvedFolderID: UUID? {
        guard let id = selectedID else { return nil }
        if dataStore.findFolder(id: id) != nil { return id }
        return dataStore.findParentFolderID(ofSnippet: id)
    }

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .frame(minWidth: 700, minHeight: 450)
        .alert("Rename", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("OK") { performRename() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { performDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteIsFolder
                 ? "This folder and all its contents will be deleted."
                 : "This snippet will be deleted.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            if dataStore.rootFolders.isEmpty && dataStore.rootSnippets.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.badge.plus")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("Create a snippet or folder to get started")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(dataStore.rootFolders.sorted(by: { $0.order < $1.order })) { folder in
                        FolderBranch(
                            folder: folder,
                            selectedID: selectedID,
                            onSelectFolder: { id in selectFolder(id) },
                            onSelectSnippet: { snippet in selectSnippet(snippet) },
                            onAddSnippet: { folderID in addSnippetTo(folderID) },
                            onAddSubfolder: { folderID in
                                dataStore.addFolder(title: "New Folder", parentID: folderID)
                            },
                            onRename: { id, isFolder, title in
                                renameTargetID = id
                                renameIsFolder = isFolder
                                renameText = title
                                showRenameAlert = true
                            },
                            onDelete: { id, isFolder in
                                deleteTargetID = id
                                deleteIsFolder = isFolder
                                showDeleteConfirm = true
                            }
                        )
                    }
                    // Root-level snippets
                    ForEach(dataStore.rootSnippets.sorted(by: { $0.order < $1.order })) { snippet in
                        rootSnippetRow(snippet)
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack(spacing: 12) {
                Button(action: addRootFolder) {
                    Label("Folder", systemImage: "folder.badge.plus")
                }
                .help("New Folder")

                Button(action: addSubfolder) {
                    Label("Subfolder", systemImage: "folder.fill.badge.plus")
                }
                .help("New Subfolder")
                .disabled(resolvedFolderID == nil)

                Button(action: addSnippet) {
                    Label("Snippet", systemImage: "doc.badge.plus")
                }
                .help("New Snippet")

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 350)
    }

    private func rootSnippetRow(_ snippet: Snippet) -> some View {
        Label(snippet.title, systemImage: "doc.text")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { selectSnippet(snippet) }
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selectedID == snippet.id ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contextMenu {
                Button("Rename...") {
                    renameTargetID = snippet.id
                    renameIsFolder = false
                    renameText = snippet.title
                    showRenameAlert = true
                }
                Divider()
                Button("Delete", role: .destructive) {
                    deleteTargetID = snippet.id
                    deleteIsFolder = false
                    showDeleteConfirm = true
                }
            }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if selectedSnippet != nil {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        TextField("Title", text: $editTitle)
                            .textFieldStyle(.plain)
                            .font(.title3.bold())

                        Spacer()

                        if hasChanges {
                            Text("Unsaved")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    Divider()

                    TextEditor(text: $editContent)
                        .font(.system(.body, design: .monospaced))
                        .padding(4)

                    Divider()

                    HStack {
                        Text("\(editContent.count) chars")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Save") { saveCurrentSnippet() }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(!hasChanges)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .onChange(of: editTitle) { _ in
                    if !isLoadingSnippet { hasChanges = true }
                }
                .onChange(of: editContent) { _ in
                    if !isLoadingSnippet { hasChanges = true }
                }
            } else if selectedFolder != nil {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Add a snippet with + or right-click the folder")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 36))
                        .foregroundStyle(.quaternary)
                    Text("Select a snippet to edit")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Selection

    private func selectFolder(_ id: UUID) {
        autoSaveIfNeeded()
        selectedID = id
    }

    private func selectSnippet(_ snippet: Snippet) {
        autoSaveIfNeeded()
        isLoadingSnippet = true
        selectedID = snippet.id
        editTitle = snippet.title
        editContent = snippet.content
        hasChanges = false
        DispatchQueue.main.async { isLoadingSnippet = false }
    }

    // MARK: - Save

    private func saveCurrentSnippet() {
        guard let id = selectedID, selectedSnippet != nil else { return }
        dataStore.updateSnippet(id: id, title: editTitle, content: editContent)
        hasChanges = false
    }

    private func autoSaveIfNeeded() {
        if hasChanges, let id = selectedID, dataStore.findSnippet(id: id) != nil {
            dataStore.updateSnippet(id: id, title: editTitle, content: editContent)
            hasChanges = false
        }
    }

    // MARK: - Actions

    private func addRootFolder() {
        dataStore.addFolder(title: "New Folder")
    }

    private func addSubfolder() {
        guard let folderID = resolvedFolderID else { return }
        dataStore.addFolder(title: "New Folder", parentID: folderID)
    }

    private func addSnippet() {
        addSnippetTo(resolvedFolderID)
    }

    private func addSnippetTo(_ folderID: UUID?) {
        autoSaveIfNeeded()
        let id = dataStore.addSnippet(title: "New Snippet", content: "", folderID: folderID)
        isLoadingSnippet = true
        selectedID = id
        editTitle = "New Snippet"
        editContent = ""
        hasChanges = false
        DispatchQueue.main.async { isLoadingSnippet = false }
    }

    private func performRename() {
        guard let id = renameTargetID, !renameText.isEmpty else { return }
        if renameIsFolder {
            dataStore.renameFolder(id: id, title: renameText)
        } else {
            dataStore.renameSnippet(id: id, title: renameText)
            if selectedID == id { editTitle = renameText }
        }
    }

    private func performDelete() {
        guard let id = deleteTargetID else { return }
        if deleteIsFolder {
            dataStore.deleteFolder(id: id)
        } else {
            let folderID = dataStore.findParentFolderID(ofSnippet: id)
            dataStore.deleteSnippet(id: id, fromFolder: folderID)
        }
        if selectedID == id {
            selectedID = nil
            hasChanges = false
        }
    }
}

// MARK: - FolderBranch (recursive tree node)

private struct FolderBranch: View {
    let folder: SnippetFolder
    let selectedID: UUID?
    let onSelectFolder: (UUID) -> Void
    let onSelectSnippet: (Snippet) -> Void
    let onAddSnippet: (UUID) -> Void
    let onAddSubfolder: (UUID) -> Void
    let onRename: (UUID, Bool, String) -> Void
    let onDelete: (UUID, Bool) -> Void

    var body: some View {
        DisclosureGroup {
            ForEach(folder.subfolders.sorted(by: { $0.order < $1.order })) { subfolder in
                FolderBranch(
                    folder: subfolder,
                    selectedID: selectedID,
                    onSelectFolder: onSelectFolder,
                    onSelectSnippet: onSelectSnippet,
                    onAddSnippet: onAddSnippet,
                    onAddSubfolder: onAddSubfolder,
                    onRename: onRename,
                    onDelete: onDelete
                )
            }
            ForEach(folder.snippets.sorted(by: { $0.order < $1.order })) { snippet in
                snippetRow(snippet)
            }
        } label: {
            folderLabel
        }
    }

    private var folderLabel: some View {
        Label(folder.title, systemImage: selectedID == folder.id ? "folder.fill" : "folder")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .fontWeight(selectedID == folder.id ? .semibold : .regular)
            .onTapGesture { onSelectFolder(folder.id) }
            .contextMenu {
                Button("Add Snippet") { onAddSnippet(folder.id) }
                Button("Add Subfolder") { onAddSubfolder(folder.id) }
                Divider()
                Button("Rename...") { onRename(folder.id, true, folder.title) }
                Divider()
                Button("Delete", role: .destructive) { onDelete(folder.id, true) }
            }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        Label(snippet.title, systemImage: "doc.text")
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onSelectSnippet(snippet) }
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selectedID == snippet.id ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contextMenu {
                Button("Rename...") { onRename(snippet.id, false, snippet.title) }
                Divider()
                Button("Delete", role: .destructive) { onDelete(snippet.id, false) }
            }
    }
}
