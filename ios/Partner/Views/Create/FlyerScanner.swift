import SwiftUI
import Vision
import AVFoundation
import ImageIO

struct FlyerScanResult: Identifiable {
    enum Reader: Equatable {
        /// Claude read the flyer image through the team's server (POST /api/flyers/read).
        case claude
        /// Apple's on-device text recognition plus simple rules (the fallback).
        case onDevice
    }

    let id = UUID()
    var title: String
    var date: Date?
    var endDate: Date? = nil
    var location: String
    var details: String
    var cost: String
    var category: ActivityCategory? = nil
    /// Fields the reader couldn't find or wasn't sure about: title, date, time, location, cost.
    var missing: [String] = []
    var isEventFlyer = true
    var reader: Reader = .onDevice
    /// Why Claude wasn't used, when the phone read the flyer itself.
    var fallbackReason: String? = nil
    var image: UIImage
}

enum FlyerScanner {
    /// Reads a flyer: Claude when the server can, otherwise on the phone.
    static func scan(_ data: Data, serverURL: URL?) async throws -> FlyerScanResult {
        let (image, lines, heading) = try await recognize(data)
        let onDevice = local(image: image, lines: lines, heading: heading)

        guard let serverURL else {
            guard var result = onDevice else { throw CocoaError(.fileReadUnknown) }
            result.fallbackReason = "Connect to your team's server in Profile → Server to read flyers with Claude."
            return result
        }
        do {
            let reading = try await ClaudeFlyerReader(baseURL: serverURL).read(image, ocrText: lines.joined(separator: "\n"))
            return reading.result(image: UIImage(cgImage: image))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // No text on the phone either: nothing to show.
            guard var result = onDevice else { throw error }
            result.fallbackReason = explain(error)
            return result
        }
    }

    /// Why Claude didn't read the flyer, in words a host understands.
    static func explain(_ error: Error) -> String {
        if let serverError = error as? EventServer.ServerError {
            let message = serverError.message.trimmingCharacters(in: .whitespacesAndNewlines)
            return (message.hasSuffix(".") ? message : message + ".") + " This flyer was read on your iPhone instead."
        }
        if error is URLError {
            return "Couldn't reach your team's server, so this flyer was read on your iPhone."
        }
        return "Something went wrong with Claude, so this flyer was read on your iPhone."
    }

    /// Decodes the image (upright, at most 2400 px) and runs Apple's text recognition.
    /// Returns the lines in reading order and the biggest plain-text line (usually the event name).
    static func recognize(_ data: Data) async throws -> (CGImage, [String], String?) {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2400
                  ] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image).perform([request])
            let observations = (request.results ?? []).sorted {
                if abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.02 {
                    return $0.boundingBox.midY > $1.boundingBox.midY
                }
                return $0.boundingBox.minX < $1.boundingBox.minX
            }
            let heading = observations
                .filter { observation in
                    guard let line = observation.topCandidates(1).first?.string else { return false }
                    return !line.contains("@") && !line.lowercased().contains("http")
                        && line.rangeOfCharacter(from: .letters) != nil
                }
                .max { $0.boundingBox.height < $1.boundingBox.height }?
                .topCandidates(1).first?.string
            return (image, observations.compactMap { $0.topCandidates(1).first?.string }, heading)
        }.value
    }

    /// The on-device reading, or nil when no text was found.
    static func local(image: CGImage, lines: [String], heading: String?) -> FlyerScanResult? {
        guard !lines.isEmpty else { return nil }
        let fields = parse(lines: lines)
        var missing: [String] = []
        if fields.date == nil { missing += ["date", "time"] }
        if fields.location.isEmpty { missing.append("location") }
        if fields.cost.isEmpty { missing.append("cost") }
        return FlyerScanResult(
            title: fields.title.isEmpty ? (heading ?? lines[0]) : fields.title,
            date: fields.date, location: fields.location, details: lines.joined(separator: "\n"),
            cost: fields.cost, missing: missing, reader: .onDevice, image: UIImage(cgImage: image)
        )
    }

    /// Kept separate from recognition so extraction can be checked with sample flyer text.
    static func parse(lines: [String]) -> (title: String, date: Date?, location: String, cost: String) {
        func labeled(_ labels: [String]) -> String? {
            for line in lines {
                for label in labels {
                    let prefix = label + ":"
                    if line.lowercased().hasPrefix(prefix) {
                        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            return nil
        }
        let text = lines.joined(separator: "\n")
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let dateText = [labeled(["date", "when"]), labeled(["time"])].compactMap { $0 }.joined(separator: " ")
        let input = dateText.isEmpty ? text : dateText
        let date = detector?.matches(in: input, range: NSRange(input.startIndex..., in: input))
            .compactMap(\.date).first
        var location = labeled(["location", "where", "venue"]) ?? ""
        if location.isEmpty,
           let addresses = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue),
           let match = addresses.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range, in: text) {
            location = String(text[range])
        }
        var cost = labeled(["cost", "price", "admission"]) ?? ""
        if cost.isEmpty {
            if text.range(of: #"\bfree\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                cost = "Free"
            } else if let range = text.range(of: #"\$\s*\d+(?:\.\d{2})?"#, options: .regularExpression) {
                cost = String(text[range])
            }
        }
        return (labeled(["event", "title"]) ?? "", date, location, cost)
    }
}

/// What the host confirmed on the review screen.
struct FlyerFields {
    var title: String
    var date: Date
    var endDate: Date?
    var location: String
    /// The map place picked in the review, if any. Without one, the Host form looks it up.
    var place: Place? = nil
    var details: String
    var cost: String
    var category: ActivityCategory?
    var cover: UIImage?
}

struct FlyerReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let result: FlyerScanResult
    let onApply: (FlyerFields) -> Void
    @State private var title: String
    @State private var date: Date
    @State private var location: String
    @State private var pickedPlace: Place?
    @State private var suggestions: [Place] = []
    @State private var details: String
    @State private var cost: String
    @State private var category: ActivityCategory?
    @State private var confirmedDate = false
    @State private var useCover = true

    init(result: FlyerScanResult, onApply: @escaping (FlyerFields) -> Void) {
        self.result = result
        self.onApply = onApply
        _title = State(initialValue: result.title)
        _date = State(initialValue: result.date ?? .now.addingTimeInterval(3600))
        _location = State(initialValue: result.location)
        _details = State(initialValue: result.details)
        _cost = State(initialValue: result.cost)
        _category = State(initialValue: result.category)
    }

    private func isMissing(_ field: String) -> Bool { result.missing.contains(field) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: result.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                    Label(result.reader == .claude ? "Read by Claude" : "Read on your iPhone",
                          systemImage: result.reader == .claude ? "sparkles" : "iphone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(result.reader == .claude ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.secondary))
                    if let reason = result.fallbackReason {
                        Label(reason, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .symbolRenderingMode(.multicolor)
                    }
                    if !result.isEventFlyer {
                        Label("This doesn't look like an event flyer. You can still fill in the details yourself.",
                              systemImage: "questionmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    Text("Check the details. Anything marked in orange wasn't on the flyer or wasn't clear, so fill it in before posting.")
                        .font(.subheadline)
                }
                Section {
                    TextField("Enter event name", text: $title)
                } header: {
                    reviewHeader("Event name", missing: isMissing("title"))
                }
                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("Choose…").tag(ActivityCategory?.none)
                        ForEach(ActivityCategory.allCases) { Label($0.title, systemImage: $0.symbol).tag(Optional($0)) }
                    }
                }
                Section {
                    if result.date == nil {
                        Text("No date was detected. Enter the event date and time.")
                            .foregroundStyle(.orange)
                    }
                    DatePicker("Starts", selection: $date, in: Date.now...)
                    if let end = result.endDate {
                        LabeledContent("Ends", value: end.formatted(date: .omitted, time: .shortened))
                    }
                    Toggle("I checked the date and time", isOn: $confirmedDate)
                } header: {
                    reviewHeader("Date and time", missing: isMissing("date") || isMissing("time"))
                }
                Section {
                    TextField("Search for the venue or address", text: $location)
                        .textContentType(.fullStreetAddress)
                        .onChange(of: location) {
                            if let pickedPlace, location != pickedPlace.name { self.pickedPlace = nil }
                        }
                    if let pickedPlace {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(pickedPlace.name).font(.subheadline.weight(.semibold))
                                if !pickedPlace.address.isEmpty {
                                    Text(pickedPlace.address).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.green)
                        }
                        .accessibilityLabel("Pinned on the map: \(pickedPlace.name)")
                    } else {
                        ForEach(suggestions.prefix(4)) { place in
                            Button {
                                pickedPlace = place
                                location = place.name
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).foregroundStyle(.primary)
                                    if !place.address.isEmpty {
                                        Text(place.address).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        Text("Pick a match to pin it on the map. If you skip this, we'll look it up for you.")
                            .font(.caption)
                    }
                } header: {
                    reviewHeader("Location", missing: isMissing("location"))
                }
                .task(id: location) {
                    // Same search as the Host form's place picker; waits for typing to pause.
                    guard pickedPlace == nil else { suggestions = []; return }
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    let found = await Place.search(location)
                    if !Task.isCancelled { suggestions = found }
                }
                Section("Description") {
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section {
                    TextField("Enter cost or Free", text: $cost)
                } header: {
                    reviewHeader("Cost", missing: isMissing("cost"))
                }
                Section {
                    Toggle("Use flyer as cover photo", isOn: $useCover)
                }
            }
            .navigationTitle("Review scanned flyer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply details") {
                        let end = result.endDate.map { date.addingTimeInterval($0.timeIntervalSince(result.date ?? date)) }
                        onApply(FlyerFields(title: title, date: date, endDate: end, location: location, place: pickedPlace,
                                            details: details, cost: cost, category: category,
                                            cover: useCover ? result.image : nil))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || !confirmedDate || date <= .now)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func reviewHeader(_ text: String, missing: Bool) -> some View {
        HStack(spacing: 6) {
            Text(text)
            if missing {
                Label("Check this", systemImage: "exclamationmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct FlyerCameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: FlyerCameraView
        init(parent: FlyerCameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
