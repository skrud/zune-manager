import Foundation
import Observation

/// The steps between picking files and copying them: duplicates to decide on, a warning when
/// old copies must be deleted first, or why it can't go ahead.
@MainActor @Observable
public final class AddFlow {
    public enum Step: Equatable {
        case duplicates(AddPreparation)
        case confirmDeleteFirst(AddPreparation, AddPlan, message: String)
        case error(String)
    }

    public private(set) var step: Step?
    /// True while the picked files are being scanned and their tags read.
    public private(set) var isPreparing = false

    @ObservationIgnored private let store: ZuneStore

    public init(store: ZuneStore) {
        self.store = store
    }

    public func start(_ urls: [URL]) async {
        guard store.activity == nil, !isPreparing else { return }
        isPreparing = true
        let preparation = await store.prepareAdd(urls)
        isPreparing = false
        if preparation.duplicates.isEmpty {
            await proceed(preparation, choices: [:])
        } else {
            step = .duplicates(preparation)
        }
    }

    public func resolveDuplicates(_ preparation: AddPreparation, choices: [URL: DuplicateChoice]) async {
        await proceed(preparation, choices: choices)
    }

    public func confirmDeleteFirst() async {
        guard case .confirmDeleteFirst(let preparation, let plan, _)? = step else { return }
        step = nil
        await store.add(plan, preparation: preparation)
    }

    public func cancel() {
        step = nil
    }

    private func proceed(_ preparation: AddPreparation, choices: [URL: DuplicateChoice]) async {
        do {
            let plan = try store.planAdd(preparation, choices: choices)
            let replacing = plan.steps.filter { $0.replacing != nil }.count
            if plan.overwriteMode == .deleteThenUpload, replacing > 0 {
                step = .confirmDeleteFirst(preparation, plan, message: Self.deleteFirstMessage(replacing))
                return
            }
            step = nil
            await store.add(plan, preparation: preparation)
        } catch AddPlanError.notEnoughSpace(let needed, let available) {
            step = .error("Not enough space on your Zune: needs \(Self.bytes(needed)), \(Self.bytes(available)) free.")
        } catch {
            step = .error(error.localizedDescription)
        }
    }

    static func deleteFirstMessage(_ count: Int) -> String {
        "There isn't enough free space to copy the new versions first. Zune Manager will delete the existing copies of \(count) \(count == 1 ? "song" : "songs") before copying the new ones. If a copy fails, those songs will be missing from your Zune."
    }

    static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }
}
