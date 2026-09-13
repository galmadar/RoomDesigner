import SwiftUI

/// What a picture being made says while it is being made, and what it says when
/// it doesn't arrive. Never a spinner with nothing behind it.
@MainActor
enum PictureJobWording {
    static func line(for job: PhotoDesignRun) -> String {
        switch job.stage {
        case .preparing: return "Drawing the room…"
        case .uploading(let done, let total): return "Sending the pictures… \(done) of \(total)"
        // How long it has been going: the only honest thing to say while waiting.
        case .designing(let since): return "Designing… \(max(0, Int(Date.now.timeIntervalSince(since))))s"
        case .downloading: return "Fetching the picture…"
        default: return "Making a picture…"
        }
    }
}

/// The placeholder that stands where a picture will be, in the room's grid.
struct MakingPictureTile: View {
    @ObservedObject var job: PhotoDesignRun

    @Environment(\.roomAccent) private var accent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Paper.tint)
            if let failure = job.failure {
                PictureJobFailure(job: job, message: failure, compact: true)
            } else {
                PictureJobProgress(job: job, compact: true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(job.failure ?? PictureJobWording.line(for: job))
    }
}

/// The same placeholder at the top of a room, where its newest picture goes.
struct MakingPictureHero: View {
    @ObservedObject var job: PhotoDesignRun

    var body: some View {
        ZStack {
            Paper.tint
            if let failure = job.failure {
                PictureJobFailure(job: job, message: failure, compact: false)
            } else {
                PictureJobProgress(job: job, compact: false)
            }
        }
        .frame(height: 430)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(job.failure ?? PictureJobWording.line(for: job))
    }
}

/// A room's card in the list, saying something is cooking inside without opening it.
struct MakingPictureBadge: View {
    @ObservedObject var job: PhotoDesignRun

    @Environment(\.roomAccent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            if job.failure == nil {
                ProgressView().controlSize(.mini).tint(accent)
                Text("Making a picture…")
            } else {
                Circle().fill(Paper.destructive).frame(width: 7, height: 7)
                Text("A picture didn't make it")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundStyle(job.failure == nil ? Paper.secondaryInk : Paper.destructive)
        .accessibilityElement(children: .combine)
    }
}

// MARK: -

private struct PictureJobProgress: View {
    @ObservedObject var job: PhotoDesignRun
    let compact: Bool

    @Environment(\.roomAccent) private var accent
    /// Redrawn every second so the count of seconds is not a lie.
    @State private var tick = Date.now

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: compact ? 8 : 12) {
            ProgressView()
                .controlSize(compact ? .regular : .large)
                .tint(accent)
            Text("Making a picture")
                .font(.system(size: compact ? 14 : 18, weight: .semibold))
                .foregroundStyle(Paper.ink)
            Text(PictureJobWording.line(for: job))
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
            Text(job.prompt)
                .font(.system(size: compact ? 12 : 14))
                .foregroundStyle(Paper.mutedInk)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 2 : 3)
        }
        .padding(compact ? 12 : 28)
        .id(tick)
        .onReceive(clock) { tick = $0 }
    }
}

private struct PictureJobFailure: View {
    @ObservedObject var job: PhotoDesignRun
    let message: String
    let compact: Bool

    @ObservedObject private var jobs = PictureJobs.shared

    var body: some View {
        VStack(spacing: compact ? 6 : 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: compact ? 18 : 28, weight: .light))
                .foregroundStyle(Paper.destructive)
            Text("This picture didn't make it")
                .font(.system(size: compact ? 13 : 18, weight: .semibold))
                .foregroundStyle(Paper.ink)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.system(size: compact ? 11 : 14))
                .foregroundStyle(Paper.secondaryInk)
                .multilineTextAlignment(.center)
                .lineLimit(compact ? 4 : 6)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if job.canRetry {
                    Button("Try again") { jobs.retry(job) }
                        .buttonStyle(QuietButtonStyle(height: 44))
                }
                Button(job.canRetry ? "Hide" : "OK") { jobs.dismiss(job) }
                    .buttonStyle(QuietButtonStyle(height: 44))
            }
            .frame(maxWidth: compact ? .infinity : 320)
        }
        .padding(compact ? 10 : 28)
    }
}
