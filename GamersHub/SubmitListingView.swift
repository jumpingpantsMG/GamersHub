import SwiftUI
import Supabase

/// Creates a listing, or edits one when `editing` is set.
struct SubmitListingView: View {
    let store: ListingsStore
    let editing: Listing?
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var blurb: String
    @State private var urlText: String
    @State private var imageText: String
    @State private var category: String
    @State private var age: AgeRating
    @State private var sending = false
    @State private var error: String?

    init(store: ListingsStore, editing: Listing? = nil) {
        self.store = store
        self.editing = editing
        _title = State(initialValue: editing?.title ?? "")
        _blurb = State(initialValue: editing?.description ?? "")
        _urlText = State(initialValue: editing?.url ?? "")
        _imageText = State(initialValue: editing?.imageURL ?? "")
        _category = State(initialValue: editing?.category ?? ListingCategory.all[0])
        _age = State(initialValue: AgeRating(rawValue: editing?.ageRating ?? 4) ?? .everyone)
    }

    private func httpsURL(_ text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let u = URL(string: t), u.scheme == "https", u.host != nil else { return nil }
        return u
    }

    private var normalizedURL: URL? { httpsURL(urlText) }
    private var normalizedImageURL: URL? { httpsURL(imageText) }

    private var isValid: Bool {
        (3...60).contains(title.count)
        && (10...300).contains(blurb.count)
        && normalizedURL != nil
        && (imageText.isEmpty || (normalizedImageURL != nil && imageText.count <= 500))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your site") {
                    TextField("Title (3-60 characters)", text: $title)
                    TextField("Short description (10-300 characters)", text: $blurb, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("https://yoursite.com", text: $urlText)
                    if !urlText.isEmpty && normalizedURL == nil {
                        Text("Must be a full https:// link.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("Cover image (optional)") {
                    TextField("https://example.com/cover.jpg", text: $imageText)
                    if !imageText.isEmpty && normalizedImageURL == nil {
                        Text("Must be a full https:// link to an image.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                    if let u = normalizedImageURL {
                        AsyncImage(url: u) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                Label("Couldn't load that image", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            default:
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    Text("Use a direct https link to a JPG or PNG. Wide images (about 2:1) look best. Clear the field to remove the image.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Details") {
                    Picker("Category", selection: $category) {
                        ForEach(ListingCategory.all, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Age rating", selection: $age) {
                        ForEach(AgeRating.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    if editing == nil {
                        Text("Listing is free. Sponsored slots (1-30 days) are in My listings.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Choose your age rating honestly and only use images you have the right to use. Viewers can report listings, and misrated or harmful sites get removed.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "Advertise" : "Edit listing")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Submit" : "Save") { Task { await save() } }
                        .disabled(!isValid || sending)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }

    private func save() async {
        guard let url = normalizedURL else { return }
        sending = true
        error = nil
        defer { sending = false }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBlurb = blurb.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let editing {
                try await store.update(editing.id, with: ListingEdit(
                    title: cleanTitle,
                    description: cleanBlurb,
                    url: url.absoluteString,
                    imageURL: normalizedImageURL?.absoluteString,
                    category: category,
                    ageRating: age.rawValue
                ))
            } else {
                try await store.submit(NewListing(
                    title: cleanTitle,
                    description: cleanBlurb,
                    url: url.absoluteString,
                    imageURL: normalizedImageURL?.absoluteString,
                    category: category,
                    ageRating: age.rawValue
                ))
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
