import SwiftUI
import Vision
import AVFoundation
import ImageIO

struct FlyerScanResult: Identifiable {
    let id = UUID()
    var title: String
    var date: Date?
    var location: String
    var details: String
    var cost: String
    var image: UIImage
}

enum FlyerScanner {
    static func scan(_ data: Data) async throws -> FlyerScanResult {
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
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            guard !lines.isEmpty else { throw CocoaError(.fileReadUnknown) }
            let text = lines.joined(separator: "\n")
            let fields = parse(lines: lines)
            let heading = observations
                .filter { observation in
                    guard let line = observation.topCandidates(1).first?.string else { return false }
                    return !line.contains("@") && !line.lowercased().contains("http")
                        && line.rangeOfCharacter(from: .letters) != nil
                }
                .max { $0.boundingBox.height < $1.boundingBox.height }?
                .topCandidates(1).first?.string
            return FlyerScanResult(
                title: fields.title.isEmpty ? (heading ?? lines[0]) : fields.title,
                date: fields.date, location: fields.location, details: text,
                cost: fields.cost, image: UIImage(cgImage: image)
            )
        }.value
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

struct FlyerReviewView: View {
    @Environment(\.dismiss) private var dismiss
    let result: FlyerScanResult
    let onApply: (String, Date, String, String, String, UIImage?) -> Void
    @State private var title: String
    @State private var date: Date
    @State private var location: String
    @State private var details: String
    @State private var cost: String
    @State private var confirmedDate = false
    @State private var useCover = true

    init(result: FlyerScanResult,
         onApply: @escaping (String, Date, String, String, String, UIImage?) -> Void) {
        self.result = result
        self.onApply = onApply
        _title = State(initialValue: result.title)
        _date = State(initialValue: result.date ?? .now.addingTimeInterval(3600))
        _location = State(initialValue: result.location)
        _details = State(initialValue: result.details)
        _cost = State(initialValue: result.cost)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Image(uiImage: result.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                    Text("Check the extracted details. Missing or unclear information needs your correction before posting.")
                        .font(.subheadline)
                }
                Section("Event name") {
                    TextField("Enter event name", text: $title)
                }
                Section("Date and time") {
                    if result.date == nil {
                        Text("No date was detected. Enter the event date and time.")
                            .foregroundStyle(.orange)
                    }
                    DatePicker("Starts", selection: $date, in: Date.now...)
                    Toggle("I checked the date and time", isOn: $confirmedDate)
                }
                Section("Location") {
                    TextField("Enter venue or address", text: $location)
                    Text("After applying, choose a map location to confirm the venue.")
                        .font(.caption)
                }
                Section("Description") {
                    TextField("Description", text: $details, axis: .vertical)
                        .lineLimit(4...10)
                }
                Section("Cost") {
                    TextField("Enter cost or Free", text: $cost)
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
                        onApply(title, date, location, details, cost, useCover ? result.image : nil)
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
