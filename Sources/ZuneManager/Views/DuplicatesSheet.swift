import SwiftUI
import ZuneKit

/// "These songs are already on your Zune": Overwrite or Skip for each, or for all at once.
struct DuplicatesSheet: View {
    let preparation: AddPreparation
    let onContinue: ([URL: DuplicateChoice]) -> Void
    let onCancel: () -> Void

    @State private var choices: [URL: DuplicateChoice] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(preparation.duplicates.count) \(preparation.duplicates.count == 1 ? "song is" : "songs are") already on your Zune")
                .font(.headline)
            Text("Overwrite replaces the copy on the Zune with the one you picked. Skip leaves it as it is.")
                .foregroundStyle(.secondary)

            List(preparation.duplicates) { duplicate in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(duplicate.incoming.title).lineLimit(1)
                        Text("\(duplicate.incoming.artist) — \(duplicate.incoming.album)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text("On the Zune: \(duplicate.existing.format.rawValue.uppercased()) · Adding: MP3")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: binding(for: duplicate.id)) {
                        Text("Skip").tag(DuplicateChoice.skip)
                        Text("Overwrite").tag(DuplicateChoice.overwrite)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .frame(minHeight: 200)

            HStack {
                Button("Skip All") { setAll(.skip) }
                Button("Overwrite All") { setAll(.overwrite) }
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Continue") { onContinue(choices) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }

    private func binding(for id: URL) -> Binding<DuplicateChoice> {
        Binding(get: { choices[id] ?? .skip }, set: { choices[id] = $0 })
    }

    private func setAll(_ choice: DuplicateChoice) {
        for duplicate in preparation.duplicates { choices[duplicate.id] = choice }
    }
}
