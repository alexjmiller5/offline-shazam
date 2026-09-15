import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RecordingWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            HStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.isStale ? "Capture ended" : "Listening for a song")
                        .font(.headline)
                    if !context.isStale {
                        ProgressView(timerInterval: context.state.startedAt...context.state.deadline, countsDown: false)
                            .tint(.purple)
                            .labelsHidden()
                            .accessibilityLabel("Recording progress")
                    }
                }
                if !context.isStale { cancelButton(context.attributes.recordingID) }
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.white)
            .foregroundStyle(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.isStale ? "Capture ended" : "Listening", systemImage: "waveform")
                        .font(.headline)
                        .foregroundStyle(.purple)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale { cancelButton(context.attributes.recordingID) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.isStale {
                        ProgressView(timerInterval: context.state.startedAt...context.state.deadline, countsDown: false)
                            .tint(.purple)
                            .accessibilityLabel("Recording progress")
                    }
                }
            } compactLeading: {
                Image(systemName: "waveform").foregroundStyle(.purple)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...context.state.deadline, countsDown: true)
                    .monospacedDigit()
                    .frame(width: 36)
                    .accessibilityLabel("Recording time remaining")
            } minimal: {
                Image(systemName: "waveform").foregroundStyle(.purple)
            }
            .keylineTint(.purple)
        }
    }

    private func cancelButton(_ id: UUID) -> some View {
        Button(intent: CancelCaptureIntent(recordingID: id)) {
            Label("Cancel", systemImage: "xmark")
                .font(.subheadline.bold())
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .accessibilityLabel("Cancel and discard capture")
    }
}
