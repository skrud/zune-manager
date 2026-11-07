import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZuneKit

/// The file pickers for Add… and Save to Mac….
enum Pickers {
    /// MP3 files and folders (folders are searched for MP3s).
    @MainActor static func chooseSongs() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = "Add to Zune"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.mp3, .folder]
        return panel.runModal() == .OK ? panel.urls : []
    }

    @MainActor static func chooseSaveFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Save to Mac"
        panel.prompt = "Save Here"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Presents the add flow's steps: the duplicates sheet, the delete-first warning, and errors.
struct AddFlowPresenter: ViewModifier {
    let flow: AddFlow

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isDuplicates) {
                if case .duplicates(let preparation)? = flow.step {
                    DuplicatesSheet(
                        preparation: preparation,
                        onContinue: { choices in Task { await flow.resolveDuplicates(preparation, choices: choices) } },
                        onCancel: { flow.cancel() })
                }
            }
            .alert("Delete the old copies first?", isPresented: isConfirm) {
                Button("Delete and Copy", role: .destructive) { Task { await flow.confirmDeleteFirst() } }
                Button("Cancel", role: .cancel) { flow.cancel() }
            } message: {
                if case .confirmDeleteFirst(_, _, let message)? = flow.step { Text(message) }
            }
            .alert("Can't add these songs", isPresented: isError) {
                Button("OK") { flow.cancel() }
            } message: {
                if case .error(let message)? = flow.step { Text(message) }
            }
    }

    private var isDuplicates: Binding<Bool> {
        presence { if case .duplicates? = $0 { true } else { false } }
    }

    private var isConfirm: Binding<Bool> {
        presence { if case .confirmDeleteFirst? = $0 { true } else { false } }
    }

    private var isError: Binding<Bool> {
        presence { if case .error? = $0 { true } else { false } }
    }

    /// Shown while the step matches; dismissing it (Escape, clicking away) cancels the flow.
    private func presence(_ matches: @escaping (AddFlow.Step?) -> Bool) -> Binding<Bool> {
        Binding(get: { matches(flow.step) }, set: { shown in if !shown, matches(flow.step) { flow.cancel() } })
    }
}
