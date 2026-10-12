import SwiftData
import SwiftUI

struct NotesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(VoiceAssistant.self) private var assistant
    @Query(sort: \Note.updatedAt, order: .reverse) private var notes: [Note]

    @State private var searchText = ""
    @State private var newNote: Note?

    var body: some View {
        NavigationStack {
            List {
                if !pinned.isEmpty {
                    Section("Pinned") {
                        ForEach(pinned) { note in noteRow(note) }
                    }
                }
                Section(pinned.isEmpty ? "" : "Notes") {
                    ForEach(unpinned) { note in noteRow(note) }
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaPadding(.bottom, 90)
            .searchable(text: $searchText, prompt: "Search notes")
            .overlay {
                if notes.isEmpty {
                    ContentUnavailableView {
                        Label("No notes yet", systemImage: "note.text")
                    } description: {
                        Text("Tap the compose button or say “\(assistant.wakePhraseDisplay), take a note…”.")
                    } actions: {
                        Button("New note") { createNote() }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { createNote() } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("New note")
                }
            }
            .sheet(item: $newNote) { note in
                NavigationStack {
                    NoteEditorView(note: note, showsDoneButton: true)
                }
            }
        }
    }

    private var filtered: [Note] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    private var pinned: [Note] { filtered.filter(\.isPinned) }
    private var unpinned: [Note] { filtered.filter { !$0.isPinned } }

    private func noteRow(_ note: Note) -> some View {
        NavigationLink {
            NoteEditorView(note: note)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(note.displayTitle)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if note.createdByVoice {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(Formatters.compact(note.updatedAt, allDay: true))
                        .foregroundStyle(.secondary)
                    Text(note.preview)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .font(.subheadline)
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelContext.delete(note)
                try? modelContext.save()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                note.isPinned.toggle()
                try? modelContext.save()
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }

    private func createNote() {
        let note = Note(title: "", body: "")
        modelContext.insert(note)
        newNote = note
    }
}

struct NoteEditorView: View {
    @Bindable var note: Note
    var showsDoneButton = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?

    private enum Field { case title, body }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $note.title)
                .font(.title2.weight(.bold))
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .body }
            Text("Edited \(Formatters.compact(note.updatedAt))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            TextEditor(text: $note.body)
                .font(.body)
                .focused($focusedField, equals: .body)
                .scrollContentBackground(.hidden)
                .overlay(alignment: .topLeading) {
                    if note.body.isEmpty {
                        Text("Start writing…")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    note.isPinned.toggle()
                } label: {
                    Image(systemName: note.isPinned ? "pin.fill" : "pin")
                }
                .accessibilityLabel(note.isPinned ? "Unpin" : "Pin")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onChange(of: note.title) { note.updatedAt = Date() }
        .onChange(of: note.body) { note.updatedAt = Date() }
        .onAppear {
            if note.title.isEmpty && note.body.isEmpty {
                focusedField = .title
            }
        }
        .onDisappear {
            if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                modelContext.delete(note)
            }
            try? modelContext.save()
        }
    }

    private var shareText: String {
        let title = note.title.trimmingCharacters(in: .whitespaces)
        return title.isEmpty ? note.body : "\(title)\n\n\(note.body)"
    }
}
