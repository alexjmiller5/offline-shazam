import SwiftUI

struct ContentView: View {
    @Bindable var controller: CaptureController
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSettings = false
    @State private var error: String?
    private let blue = Color(red: 8 / 255, green: 123 / 255, blue: 193 / 255)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("Keep the song.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("Even without a connection.")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    .padding(.top, 24)

                    Button {
                        Task {
                            do { _ = try await controller.capture(); error = nil }
                            catch let captureError as CaptureError { error = captureError.localizedDescription }
                            catch { self.error = "Could not save this capture. Please try again." }
                        }
                    } label: {
                        VStack(spacing: 12) {
                            Image("Waveform").resizable().scaledToFit().frame(width: 76, height: 76)
                            Text(controller.isRecording ? "Listening…" : "Capture song")
                                .font(.title3.weight(.semibold))
                            Text(controller.isRecording ? "Recording a 15-second clip" : "Tap to listen for 15 seconds")
                                .font(.footnote)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 224)
                        .background(blue.gradient, in: RoundedRectangle(cornerRadius: 36))
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isRecording)
                    .accessibilityLabel("Capture song")
                    .accessibilityValue(controller.isRecording ? "Listening" : "Ready")

                    VStack(spacing: 8) {
                        if let error {
                            Text(error).foregroundStyle(.red)
                        } else if controller.isRecording {
                            Text("Listening to the music around you.")
                        } else if controller.isProcessing {
                            HStack(spacing: 8) { ProgressView(); Text("Identifying saved captures…") }
                        } else if let status = controller.status {
                            Text(status)
                        } else {
                            Text("Saved songs are handled automatically the next time you use the app online.")
                        }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 42)

                    if !controller.records.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack {
                                Text("Your captures").font(.title2.bold())
                                Spacer()
                                let pending = controller.records.filter { $0.state == .pending || $0.state == .matched }.count
                                if pending > 0 { Text("\(pending) pending").font(.caption).foregroundStyle(.secondary) }
                            }
                            ForEach(controller.records.reversed()) { record in
                                CaptureRow(record: record)
                                if record.id != controller.records.first?.id { Divider() }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 32)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Offline Shazam")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") { showingSettings = true }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView(controller: controller) }
            .task { controller.refresh(); await resumeAfterActivation() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await resumeAfterActivation() } }
            }
        }
        .tint(blue)
    }

    private func resumeAfterActivation() async {
        // Give a foreground capture intent time to start its microphone first.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        await controller.resume()
    }
}

private struct CaptureRow: View {
    let record: CaptureRecord
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(record.title ?? "Saved capture").font(.headline)
            if let artist = record.artist { Text(artist).foregroundStyle(.secondary) }
            HStack {
                Text(label).foregroundStyle(record.state == .delivered ? Color.green : Color.secondary)
                Spacer()
                Text(record.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            if let message = record.lastError { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    private var label: String {
        switch record.state {
        case .pending: return "Saved for identification"
        case .matched: return "Identified · waiting for Spotify"
        case .delivered: return "Added to Spotify"
        case .unmatched: return "Not identified"
        }
    }
}

private struct SettingsView: View {
    let controller: CaptureController
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint = ""
    @State private var token = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Capture URL", text: $endpoint)
                        .keyboardType(.URL).textContentType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Access token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Music Sync") } footer: {
                    Text("Use the capture URL and device access token issued by Music Sync. Your connection is stored securely on this iPhone.")
                }
                Section {
                    Button("Save connection") {
                        do {
                            let configuration = try DeliveryConfiguration(endpoint: endpoint, token: token)
                            try Runtime.connection.save(configuration)
                            message = "Connection saved."
                            Task {
                                do { try await controller.delivery.connectionChanged(); await controller.resume() }
                                catch { message = "Connection saved. Pending songs will retry on your next use." }
                            }
                        } catch { message = error.localizedDescription }
                    }
                    if let message { Text(message).font(.footnote) }
                }
                Section("Offline captures") {
                    Text("Capture anytime. Saved songs are identified when you next use the app online. Once identified, delivery can continue in the background.")
                    Text("Shazam identifies the music. Music Sync adds it to Spotify.")
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear {
                do {
                    if let saved = try Runtime.connection.load() {
                        endpoint = saved.endpoint.absoluteString
                        token = saved.token
                    }
                } catch { message = error.localizedDescription }
            }
        }
    }
}
