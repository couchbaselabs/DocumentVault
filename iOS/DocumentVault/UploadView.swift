import SwiftUI
import UniformTypeIdentifiers
import PhotosUI

struct UploadView: View {
    @EnvironmentObject var dbManager: DatabaseManager
    @EnvironmentObject var authManager: AuthenticationManager

    @State private var showFilePicker    = false
    @State private var showCamera        = false
    @State private var showPhotoLibrary  = false
    @State private var showFolderPicker  = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessing      = false
    @State private var lastUploaded: VaultDocument?
    @State private var wasRestored: Bool = false
    @State private var restoredFromDate: Date? = nil
    @State private var wasBlobRepaired: Bool = false
    @State private var errorMessage: String?
    @State private var selectedFolder: Folder? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text("Add Documents")
                    .font(.largeTitle.bold())

                Text("Upload from your device, snap a photo, or scan a document.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // Folder destination picker
                Button { showFolderPicker = true } label: {
                    HStack {
                        Image(systemName: selectedFolder == nil ? "tray" : (selectedFolder?.icon ?? "folder.fill"))
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Destination").font(.caption).foregroundColor(.secondary)
                            Text(selectedFolder?.name ?? "Root (no folder)").font(.body)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                VStack(spacing: 16) {
                    uploadButton(
                        title: "Choose File",
                        subtitle: "PDF, Word, Excel, CSV, images…",
                        icon: "folder",
                        color: .blue
                    ) { showFilePicker = true }

                    uploadButton(
                        title: "Scan Document",
                        subtitle: "Camera OCR → auto-indexed",
                        icon: "doc.viewfinder",
                        color: .indigo
                    ) { showCamera = true }

                    uploadButton(
                        title: "Photo Library",
                        subtitle: "Select an image to ingest",
                        icon: "photo.on.rectangle",
                        color: .purple
                    ) { showPhotoLibrary = true }
                }
                .padding(.horizontal)

                if isProcessing {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Processing…").font(.caption).foregroundColor(.secondary)
                    }
                }

                if let doc = lastUploaded {
                    HStack(spacing: 8) {
                        Image(systemName: bannerIcon)
                            .foregroundColor(bannerColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(doc.name).font(.caption.weight(.medium)).lineLimit(1)
                            Text(bannerSubtitle).font(.caption2).foregroundColor(bannerColor)
                        }
                    }
                    .padding()
                    .background(bannerColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                if let err = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle").foregroundColor(.red)
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                }

                Spacer()
            }
            .navigationTitle("Upload")
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: allowedTypes,
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result: result)
            }
            .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhoto)
            .onChange(of: selectedPhoto) { _, item in
                Task { await handlePhotoSelection(item) }
            }
            .sheet(isPresented: $showCamera) {
                CameraCapturePipelineView { image in
                    Task { await handleCameraCapture(image) }
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                UploadFolderPickerSheet(dbManager: dbManager, selected: $selectedFolder)
            }
        }
    }

    // MARK: - Button Builder

    private func uploadButton(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(color.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon).font(.title2).foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    // MARK: - Handlers

    private func handleFileImport(result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        // Start scope before the Task so the file is accessible during the async copy.
        // stopAccessingSecurityScopedResource is called inside the Task via defer,
        // AFTER the pipeline has finished reading the file — not when this function returns.
        guard url.startAccessingSecurityScopedResource() else { return }
        guard let user = authManager.currentUser else {
            url.stopAccessingSecurityScopedResource()
            return
        }
        isProcessing = true
        errorMessage = nil
        Task {
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let result = try await DocumentProcessingPipeline.shared.ingest(
                    fileURL: url,
                    ownerId: user.email,
                    tenantId: user.tenantId,
                    folderId: selectedFolder?.id,
                    db: dbManager
                )
                await MainActor.run { applyResult(result) }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isProcessing = false }
            }
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await handleCameraCapture(image)
    }

    private func handleCameraCapture(_ image: UIImage) async {
        guard let user = authManager.currentUser else { return }
        isProcessing = true
        errorMessage = nil
        do {
            let result = try await DocumentProcessingPipeline.shared.ingest(
                image: image,
                ownerId: user.email,
                tenantId: user.tenantId,
                folderId: selectedFolder?.id,
                db: dbManager
            )
            await MainActor.run { applyResult(result) }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription; isProcessing = false }
        }
    }

    private func applyResult(_ result: IngestResult) {
        switch result {
        case .created(let doc):
            lastUploaded = doc
            wasRestored = false
            restoredFromDate = nil
            wasBlobRepaired = false
        case .restored(let doc, let deletedAt):
            lastUploaded = doc
            wasRestored = true
            restoredFromDate = deletedAt
            wasBlobRepaired = false
        case .blobAttached(let doc):
            lastUploaded = doc
            wasRestored = false
            restoredFromDate = nil
            wasBlobRepaired = true
        }
        isProcessing = false
    }

    private var bannerIcon: String {
        if wasBlobRepaired { return "paperclip.circle.fill" }
        if wasRestored     { return "arrow.uturn.backward.circle.fill" }
        return "checkmark.circle.fill"
    }

    private var bannerColor: Color {
        if wasBlobRepaired { return .teal }
        if wasRestored     { return .orange }
        return .green
    }

    private var bannerSubtitle: String {
        if wasBlobRepaired { return "Content attached · indexing in background" }
        if wasRestored {
            return restoredFromDate.map {
                "Previously deleted \($0.formatted(date: .abbreviated, time: .omitted)) · history intact"
            } ?? "Previously deleted · history intact"
        }
        return "Uploaded · indexing in background"
    }

    private var allowedTypes: [UTType] {
        [.pdf, .plainText, .commaSeparatedText, .spreadsheet,
         .presentation, .image, .jpeg, .png, .heic,
         .audio, .mp3, .mpeg4Audio,
         .video, .mpeg4Movie, .quickTimeMovie,
         UTType(filenameExtension: "docx") ?? .data,
         UTType(filenameExtension: "xlsx") ?? .data,
         UTType(filenameExtension: "csv")  ?? .commaSeparatedText,
         UTType(filenameExtension: "wav")  ?? .audio,
         UTType(filenameExtension: "m4a")  ?? .mpeg4Audio,
         UTType(filenameExtension: "mov")  ?? .quickTimeMovie]
    }
}

// MARK: - Upload Folder Picker Sheet

struct UploadFolderPickerSheet: View {
    let dbManager: DatabaseManager
    @Binding var selected: Folder?
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [Folder] = []

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selected = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "tray").foregroundColor(.accentColor)
                        Text("Root (no folder)")
                        Spacer()
                        if selected == nil {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                }
                .foregroundColor(.primary)

                ForEach(folders) { folder in
                    Button {
                        selected = folder
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: folder.icon ?? "folder.fill").foregroundColor(.accentColor)
                            Text(folder.name)
                            Spacer()
                            if selected?.id == folder.id {
                                Image(systemName: "checkmark").foregroundColor(.accentColor)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .navigationTitle("Choose Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                folders = (try? dbManager.fetchFolders()) ?? []
            }
        }
    }
}

// MARK: - Camera Capture View

struct CameraCapturePipelineView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            if let img = info[.originalImage] as? UIImage { onCapture(img) }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
