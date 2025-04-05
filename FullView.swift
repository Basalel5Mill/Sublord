// SublordFCPExtension/MainView.swift

import Foundation
import AppKit
import ProExtensionHost
import SwiftUI
import UniformTypeIdentifiers // Required for UTType
import SRTParser // <--- IMPORT THE LIBRARY

// MARK: - Download Delegate
class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    var model: String
    var progressHandler: ((Double) -> Void)?
    var completionHandler: (() -> Void)?
    var cancelAction: (() -> Void)?
    var downloadTaskRef: URLSessionDownloadTask?
    
    init(model: String, progressHandler: ((Double) -> Void)? = nil, completionHandler: (() -> Void)? = nil) {
        self.model = model
        self.progressHandler = progressHandler
        self.completionHandler = completionHandler
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.progressHandler?(progress) }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        guard let appSupportURL = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            print("Failed access App Support")
            DispatchQueue.main.async { self.completionHandler?() }
            return
        }
        let sublordDirURL = appSupportURL.appendingPathComponent("Sublord")
        do {
            try fm.createDirectory(at: sublordDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Failed create dir: \(error)")
            DispatchQueue.main.async { self.completionHandler?() }
            return
        }
        let destURL = sublordDirURL.appendingPathComponent("ggml-\(model.lowercased()).bin")
        do {
            if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
            try fm.moveItem(at: location, to: destURL)
            print("Downloaded: \(destURL.path)")
            DispatchQueue.main.async { self.completionHandler?() }
        } catch {
            print("Failed move file: \(error)")
            try? fm.removeItem(at: location)
            DispatchQueue.main.async { self.completionHandler?() }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            if (error as NSError).code != NSURLErrorCancelled {
                print("Download fail: \(error)")
            } else {
                print("Download cancelled.")
            }
            DispatchQueue.main.async { self.completionHandler?() }
        }
    }
    
    func cancelDownload() { downloadTaskRef?.cancel() }
}

// MARK: - MainView Struct
struct MainView: View {
    // MARK: State Variables
    @State private var fileURL: URL?
    @State private var fileName: String = ""
    @State private var fps: String = "23.98" // Default to 23.98 based on later examples
    @State private var selectedLanguage = "English"
    @State private var selectedModel = "Base"
    @State private var resolution: CGSize = CGSize(width: 1920, height: 1080)
    @State private var wordsPerLine = "One line" // Default to "One line"
    @State private var isProcessing: Bool = false
    @State private var progress: Double = 0.0
    @State private var progressPercentage: Int = 0
    @State private var totalBatch: Int = 0
    @State private var currentBatch: Int = 0
    @State private var processingStartTime: Date? = nil
    @State private var remainingTime: String = "--:--"
    @State private var status: String = "Ready"
    @State private var outputCaptions: String = ""
    @State private var projectName: String = ""
    @State private var outputFCPXMLFilePath: String = ""
    @State private var outputSRTFilePath: String = ""
    @State private var currentTempDir: String? = nil
    @State private var progressTimer: Timer? = nil
    @State private var isDownloading: Bool = false
    @State private var downloadProgress: Double = 0.0
    @State private var showAlert: Bool = false
    @State private var downloadDelegate: DownloadDelegate?
    @State private var availableMotionTemplates: [String] = []
    @State private var selectedMotionTemplate: String = ""
    @State private var motionTemplateTextParam: String = "Text" // Keep default as "Text"
    // Restored UI State
    @State private var textWidth: Double = 1.0
    @State private var textSize: Double = 60 // Default to 60 based on XML
    @State private var selectedColor: Color = .white
    @State private var selectedFont = "Helvetica Neue" // Default to Helvetica Neue
    @State private var showColorPicker = false
    @State private var sizeValue: Double = 0.5 // Corresponds roughly to 60pt if range is 18-132
    // State for Progress Tracking
    @State private var currentSegmentIndex: Int = 0
    @State private var currentSegmentDuration: Double = 0.0
    @State private var currentSegmentProgress: Double = 0.0
    @State private var lastProgressUpdate: Date = Date()
    @State private var logBuffer: String = ""
    @State private var logUpdateTimer: Timer? = nil
    // New State for Time-Based Progress Estimation
    @State private var segmentStartTime: Date? = nil
    @State private var lastTimestampProgress: Double = 0.0
    
    private let motionTemplateManager = MotionTemplateManager()

    // Constants
    let languages = ["Arabic", "Azerbaijani", "Armenian", "Albanian", "Afrikaans", "Amharic", "Assamese", "Bulgarian", "Bengali", "Breton", "Basque", "Bosnian", "Belarusian", "Bashkir", "Chinese Simplified", "Chinese Traditional", "Catalan", "Czech", "Croatian", "Dutch", "Danish", "English", "Estonian", "French", "Finnish", "Faroese", "German", "Greek", "Galician", "Georgian", "Gujarati", "Hindi", "Hebrew", "Hungarian", "Haitian Creole", "Hawaiian", "Hausa", "Italian", "Indonesian", "Icelandic", "Japanese", "Javanese", "Korean", "Kannada", "Kazakh", "Khmer", "Lithuanian", "Latin", "Latvian", "Lao", "Luxembourgish", "Lingala", "Malay", "Maori", "Malayalam", "Macedonian", "Mongolian", "Marathi", "Maltese", "Myanmar", "Malagasy", "Norwegian", "Nepali", "Nynorsk", "Occitan", "Portuguese", "Polish", "Persian", "Punjabi", "Pashto", "Russian", "Romanian", "Spanish", "Swedish", "Slovak", "Serbian", "Slovenian", "Swahili", "Sinhala", "Shona", "Somali", "Sindhi", "Sanskrit", "Sundanese", "Turkish", "Tamil", "Thai", "Telugu", "Tajik", "Turkmen", "Tibetan", "Tagalog", "Tatar", "Ukrainian", "Urdu", "Uzbek", "Vietnamese", "Welsh", "Yoruba", "Yiddish"]
    let models = ["Large", "Medium", "Small", "Base", "Tiny"]
    let wordsPerLineOptions = ["One line", "Two lines", "Three lines"]
    let fpsOptions = ["23.98", "24", "25", "29.97", "30", "50", "59.94", "60"]
    let fonts = ["Helvetica Neue", "Arial", "Times New Roman", "Courier New", "Georgia", "Verdana", "Impact", "Comic Sans MS"]

    // MARK: Body
    var body: some View {
        HStack(spacing: 0) {
            configurationPanel()
                .frame(width: 430)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).edgesIgnoringSafeArea(.all))
                .onAppear(perform: loadMotionTemplates)

            if isProcessing {
                processingPanel()
            } else {
                previewPanel()
            }
        }
        .frame(minWidth: 600, minHeight: 338)
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text("Downloading \(selectedModel) Model"),
                message: Text(String(format: "Progress: %.0f%%", downloadProgress * 100)),
                primaryButton: .destructive(Text("Cancel")) {
                    self.downloadDelegate?.cancelDownload()
                },
                secondaryButton: .default(Text("OK"))
            )
        }
    }

    // MARK: Configuration Panel View Builder
    @ViewBuilder func configurationPanel() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Language & Word Per Line Dropdowns
            HStack {
                configDropdown(label: "Language", selection: $selectedLanguage, options: languages)
                Spacer()
                configDropdown(label: "Word Per Line", selection: $wordsPerLine, options: wordsPerLineOptions)
            }.padding(.top, 20)

            // Font & Color Picker
            HStack {
                configDropdown(label: "Font", selection: $selectedFont, options: fonts)
                Spacer()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Color").foregroundColor(.secondary).font(.caption).frame(width: 188, alignment: .leading)
                    HStack {
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Color.secondary, lineWidth: 0.5))
                            .onTapGesture { showColorPicker.toggle() }
                            .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
                                ColorPicker("Select a color", selection: $selectedColor, supportsOpacity: false).padding()
                            }
                        Spacer()
                    }.frame(width: 188, height: 30)
                }
            }.padding(.top, 15)

            // Model & FPS Dropdowns
            HStack {
                configDropdown(label: "Model", selection: $selectedModel, options: models)
                Spacer()
                configDropdown(label: "FPS", selection: $fps, options: fpsOptions)
            }.padding(.top, 15)

            // Motion Title Template Dropdown
            VStack(alignment: .leading, spacing: 8) {
                Text("Motion Title Template").foregroundColor(.secondary).font(.caption)
                Menu {
                    ForEach(availableMotionTemplates, id: \.self) { name in
                        Button(name) { selectedMotionTemplate = name }
                    }
                } label: {
                    styledDropdownLabel(text: selectedMotionTemplate.isEmpty ? "Select Template" : selectedMotionTemplate)
                }
                .frame(maxWidth: .infinity)
            }.padding(.top, 15)

            // Resolution Fields
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution").foregroundColor(.secondary).font(.caption)
                HStack {
                    let formatter: NumberFormatter = {
                        let fmt = NumberFormatter()
                        fmt.numberStyle = .decimal
                        fmt.minimum = 0
                        fmt.maximum = 8192
                        return fmt
                    }()
                    TextField("Width", value: $resolution.width, formatter: formatter)
                        .textFieldStyle(PlainTextFieldStyle()).padding(6).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(5).frame(width: 80)
                    Text("×").foregroundColor(.secondary)
                    TextField("Height", value: $resolution.height, formatter: formatter)
                        .textFieldStyle(PlainTextFieldStyle()).padding(6).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(5).frame(width: 80)
                }
            }.padding(.top, 15)

            // Size Slider
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Size").foregroundColor(.secondary).font(.caption)
                        Spacer()
                        Text("\(Int(textSize))pt").foregroundColor(.secondary).font(.caption)
                    }
                    Slider(value: $sizeValue, in: 0...1) { _ in
                        textSize = round(18 + (sizeValue * 114))
                    }
                    .frame(width: 188)
                }
                Spacer()
                Spacer().frame(width: 188)
            }.padding(.top, 15)

            // Text Width Slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Text Width").foregroundColor(.secondary).font(.caption)
                    Spacer()
                    Text("\(Int(textWidth * 100))%").foregroundColor(.secondary).font(.caption)
                }
                Slider(value: $textWidth, in: 0.1...1.0)
                    .frame(maxWidth: .infinity)
            }.padding(.top, 15)

            // File Drop Zone
            fileDropZone().padding(.top, 15)

            // Action Buttons (Download/Create)
            HStack {
                if isDownloading {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 10)
                        .padding(.trailing)
                } else {
                    Spacer()
                }

                Button(action: checkModelAndProcess) {
                    Text("Create")
                        .foregroundColor(.white)
                        .frame(width: 80, height: 30)
                        .background(Color.accentColor)
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(fileURL == nil || fps.isEmpty || isProcessing || isDownloading || selectedMotionTemplate.isEmpty)
            }
            .frame(height: 30)
            .padding(.top, 15)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    // MARK: File Drop Zone View Builder
    @ViewBuilder func fileDropZone() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                .frame(height: 80)

            VStack(spacing: 5) {
                Image(systemName: "music.note.list")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
                Text(fileName.isEmpty ? "Drop MP3 file here or click to browse" : fileName)
                    .font(.callout)
                    .foregroundColor(fileName.isEmpty ? .secondary : .primary)
                    .padding(.horizontal, 5)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            browseForFile()
        }
        .onDrop(of: [UTType.mp3], isTargeted: nil) { providers, _ in
            handleDrop(providers: providers)
        }
    }

    // MARK: Preview Panel View Builder
    @ViewBuilder func previewPanel() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project: \(projectName.isEmpty ? "No file selected" : projectName)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Status: \(status)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ZStack {
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(maxWidth: .infinity, maxHeight: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                    )

                if fileURL != nil && !isProcessing {
                    VStack {
                        Spacer()
                        Text("configure")
                            .font(.custom(selectedFont, size: CGFloat(textSize * 0.5)))
                            .foregroundColor(selectedColor)
                            .padding()
                            .frame(width: textWidth * 300)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if !isProcessing {
                    Text("Select audio & template.")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(minHeight: 200)

            HStack {
                actionButton(label: "SRT", systemImage: "square.and.arrow.down", color: .orange) {
                    downloadFile(filePath: outputSRTFilePath)
                }
                .disabled(outputSRTFilePath.isEmpty)

                actionButton(label: "FCPXML", systemImage: "square.and.arrow.down", color: .blue) {
                    downloadFile(filePath: outputFCPXMLFilePath)
                }
                .disabled(outputFCPXMLFilePath.isEmpty)

                Spacer()

                actionButton(label: "Add to Timeline", systemImage: "f.cursive.circle", color: .accentColor) {
                    backtofcpx(fcpxml_path_to_import: outputFCPXMLFilePath)
                }
                .disabled(outputFCPXMLFilePath.isEmpty)
            }

            Spacer()

            VStack(spacing: 5) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .frame(height: 5)
                Text(status == "Done" ? "Completed" : "Ready")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Processing Panel View Builder
    @ViewBuilder func processingPanel() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Project: \(projectName)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Status: \(status)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView {
                ScrollViewReader { proxy in
                    Text(outputCaptions.isEmpty ? "Starting..." : outputCaptions)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("logBottom")
                        .onChange(of: outputCaptions) {
                            DispatchQueue.main.async {
                                proxy.scrollTo("logBottom", anchor: .bottom)
                            }
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
            )

            HStack {
                actionButton(label: "SRT", systemImage: "square.and.arrow.down", color: .orange) {}
                    .disabled(true)
                actionButton(label: "FCPXML", systemImage: "square.and.arrow.down", color: .blue) {}
                    .disabled(true)
                Spacer()
                actionButton(label: "Add to Timeline", systemImage: "f.cursive.circle", color: .accentColor) {}
                    .disabled(true)
            }

            VStack(spacing: 5) {
                ProgressView(value: progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .frame(height: 5)
                Text("\(progressPercentage)% completed - \(remainingTime) remaining")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Helper View Builders
    @ViewBuilder func configDropdown(label: String, selection: Binding<String>, options: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).foregroundColor(.secondary).font(.caption)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) { selection.wrappedValue = option }
                }
            } label: {
                styledDropdownLabel(text: selection.wrappedValue)
            }.frame(width: 188)
        }
    }
    
    @ViewBuilder func styledDropdownLabel(text: String) -> some View {
        HStack {
            Text(text).foregroundColor(.primary).lineLimit(1).truncationMode(.tail)
            Spacer()
            Image(systemName: "chevron.up.chevron.down").foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(5)
    }
    
    @ViewBuilder func actionButton(label: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(label)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: File Handling Logic
    func browseForFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.mp3]
        if panel.runModal() == .OK, let url = panel.urls.first {
            self.updateSelectedFile(url: url)
        }
    }
    
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let p = providers.first else { return false }
        guard p.hasItemConformingToTypeIdentifier(UTType.mp3.identifier) else {
            DispatchQueue.main.async { self.status = "Invalid drop: MP3 only." }
            return false
        }
        p.loadItem(forTypeIdentifier: UTType.mp3.identifier, options: nil) { (item, err) in
            DispatchQueue.main.async {
                guard err == nil else {
                    print("Err loadItem: \(err!)")
                    self.status = "Err reading drop."
                    return
                }
                var url: URL? = nil
                var stop: Bool = false
                if let d = item as? Data, let u = URL(dataRepresentation: d, relativeTo: nil) {
                    if u.pathExtension.lowercased() == "mp3" { url = u }
                } else if let d = item as? Data {
                    var stale: Bool = false
                    if let bu = try? URL(resolvingBookmarkData: d, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
                        if bu.startAccessingSecurityScopedResource() {
                            stop = true
                            if bu.pathExtension.lowercased() == "mp3" { url = bu }
                            if stale { print("Warn: Stale bookmark.") }
                        } else {
                            print("Err: No scope access.")
                        }
                    }
                }
                if let final = url {
                    self.updateSelectedFile(url: final)
                } else {
                    self.invalidDropAlert()
                }
                if stop, let final = url {
                    final.stopAccessingSecurityScopedResource()
                }
            }
        }
        return true
    }
    
    func updateSelectedFile(url: URL) {
        self.fileURL = url
        self.fileName = url.lastPathComponent
        self.projectName = url.deletingPathExtension().lastPathComponent
        self.status = "File selected: \(self.fileName)"
        self.outputSRTFilePath = ""
        self.outputFCPXMLFilePath = ""
        self.progress = 0.0
        self.progressPercentage = 0
        self.currentTempDir = nil
        print("Updated file: \(url.path)")
        let maxPreviewWidth = 300.0 * textWidth
        let estimatedCharsPerLine = 40.0
        let estimatedLines = Double(fileName.count) / estimatedCharsPerLine
        let estimatedFontSize = maxPreviewWidth / (estimatedCharsPerLine * 0.75) / estimatedLines
        self.textSize = min(max(18, estimatedFontSize), 130)
        self.sizeValue = Double((textSize - 18) / 114)
    }
    
    func invalidDropAlert() {
        let alert = NSAlert()
        alert.messageText = "Invalid Type"
        alert.informativeText = "Drop MP3."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
        self.status = "Invalid drop."
        self.fileURL = nil
        self.fileName = ""
        self.projectName = ""
    }
    
    func loadMotionTemplates() {
        availableMotionTemplates = motionTemplateManager.discoverTemplates()
        print("Templates: \(availableMotionTemplates)")
        if !selectedMotionTemplate.isEmpty && !availableMotionTemplates.contains(selectedMotionTemplate) {
            selectedMotionTemplate = ""
        }
    }

    // MARK: Processing Logic
    func resetStateForProcessing() {
        self.isProcessing = true
        self.status = "Preparing..."
        self.outputCaptions = ""
        self.logBuffer = ""
        self.progress = 0.0
        self.progressPercentage = 0
        self.totalBatch = 0
        self.currentBatch = 0
        self.remainingTime = "--:--"
        self.outputSRTFilePath = ""
        self.outputFCPXMLFilePath = ""
        self.processingStartTime = Date()
        self.currentSegmentIndex = 0
        self.currentSegmentDuration = 0.0
        self.currentSegmentProgress = 0.0
        self.lastTimestampProgress = 0.0
        self.segmentStartTime = nil
        self.lastProgressUpdate = Date()
    }
    
    func checkModelAndProcess() {
        let fm = FileManager.default
        guard let appSup = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            self.status = "Err: App Support"
            return
        }
        let subDir = appSup.appendingPathComponent("Sublord")
        let modelPath = subDir.appendingPathComponent("ggml-\(selectedModel.lowercased()).bin").path
        if !fm.fileExists(atPath: modelPath) {
            self.status = "Downloading \(selectedModel)..."
            download_model(model: selectedModel) { success in
                DispatchQueue.main.async {
                    if success {
                        self.status = "Downloaded. Processing..."
                        self.whisper_auto_captions()
                    } else {
                        self.status = "Err: Download fail/cancel."
                    }
                }
            }
        } else {
            self.status = "Model found. Processing..."
            whisper_auto_captions()
        }
    }

    func whisper_auto_captions() {
        // Input Validation
        guard let currentFileURL = fileURL else { self.status = "Error: No audio file."; return }
        guard let fpsValue = Float(fps), fpsValue > 0 else { self.status = "Error: Invalid FPS."; return }
        guard !selectedMotionTemplate.isEmpty else { self.status = "Error: Select Motion template."; return }

        // Setup real-time progress update timer
        startProgressUpdateTimer()
        startLogUpdateTimer()

        // Cleanup & State Reset
        if let prevDir = currentTempDir { cleanupTempDirectory(tempDir: prevDir); self.currentTempDir = nil }
        resetStateForProcessing()

        // Get Template Ref ID
        guard let templateRefID = self.motionTemplateManager.getTemplateRefID(templateName: selectedMotionTemplate) else {
            DispatchQueue.main.async { self.status = "Error: Cannot find ref ID. Check MotionTemplateManager."; self.isProcessing = false }
            return
        }
        print("Using Template Ref ID: \(templateRefID)")

        // Handle Security Scope & Captured Variables
        let accessingScopedResource = currentFileURL.startAccessingSecurityScopedResource()
        let filePathString = currentFileURL.path
        let capturedProjectName = self.projectName
        let capturedSelectedModel = self.selectedModel
        let capturedSelectedLanguage = self.selectedLanguage
        let capturedMotionTemplate = self.selectedMotionTemplate
        let capturedParamName = self.motionTemplateTextParam
        let capturedWordsPerLine = self.wordsPerLine
        let capturedSelectedFont = self.selectedFont
        let capturedTextSize = self.textSize
        let capturedTextWidth = self.textWidth
        let capturedSelectedColor = self.selectedColor.toHexString()

        // Use explicit DispatchWorkItem syntax
        let workItem = DispatchWorkItem {
            // Background Code Starts Here
            defer {
                if accessingScopedResource {
                    currentFileURL.stopAccessingSecurityScopedResource()
                    print("Stopped scope access.")
                }
            }

            // Create Temp Directory
            let tempDir = NSTemporaryDirectory() + UUID().uuidString + "/"
            do {
                try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true, attributes: nil)
                print("Created temp: \(tempDir)")
                DispatchQueue.main.async { self.currentTempDir = tempDir }
            } catch {
                print("Error temp dir: \(error)")
                DispatchQueue.main.async { self.status = "Error: Temp dir fail."; self.isProcessing = false }
                return
            }

            // Steps 1 & 2: Convert/Split WAV
            DispatchQueue.main.async { self.status = "Converting..." }
            let wavFilePath = mp3_to_wav(filePathString: filePathString, projectName: capturedProjectName, tempFolder: tempDir) // Fixed: Changed formData to tempDir
            guard !wavFilePath.isEmpty else {
                DispatchQueue.main.async { self.status = "Error: WAV convert fail."; self.isProcessing = false }
                self.cleanupTempDirectory(tempDir: tempDir)
                DispatchQueue.main.async { self.currentTempDir = nil }
                return
            }

            DispatchQueue.main.async { self.status = "Splitting..." }
            let wavSegments = split_wav(inputFilePath: wavFilePath)
            guard !wavSegments.isEmpty else {
                DispatchQueue.main.async { self.status = "Error: WAV split fail."; self.isProcessing = false }
                self.cleanupTempDirectory(tempDir: tempDir)
                DispatchQueue.main.async { self.currentTempDir = nil }
                return
            }
            DispatchQueue.main.async { self.totalBatch = wavSegments.count; self.currentBatch = 0; self.status = "Transcribing..." }

            // Step 3: Process Segments with Whisper
            var srtFiles: [String] = []
            var processingErrorOccurred = false
            for (index, segment) in wavSegments.enumerated() {
                if processingErrorOccurred { break }
                let (segmentPath, segmentDuration) = segment
                DispatchQueue.main.async {
                    self.currentSegmentIndex = index
                    self.currentSegmentDuration = segmentDuration
                    self.currentSegmentProgress = 0.0
                    self.lastTimestampProgress = 0.0
                    self.segmentStartTime = Date() // Record the start time of the segment
                    self.currentBatch = index + 1
                    self.status = "Proc seg \(index + 1)/\(wavSegments.count)..."
                }

                var srtPathOut: String?
                let sem = DispatchSemaphore(value: 0)
                whisper_cpp(
                    selectedModel: capturedSelectedModel,
                    selectedLanguage: capturedSelectedLanguage,
                    outputWavFilePath: segmentPath,
                    logHandler: { log in
                        // Buffer the log
                        self.logBuffer += log
                        // Parse timestamps on a background queue
                        DispatchQueue.global(qos: .userInteractive).async {
                            self.parseTimestamps(from: log)
                        }
                    },
                    completion: { result in
                        srtPathOut = result
                        sem.signal()
                        DispatchQueue.main.async {
                            self.currentSegmentProgress = 1.0
                            self.lastTimestampProgress = 1.0
                            self.segmentStartTime = nil // Clear the start time
                        }
                    }
                )

                let waitResult = sem.wait(timeout: .now() + 1800)
                if waitResult == .timedOut {
                    print("Timeout processing segment \(index + 1)")
                    DispatchQueue.main.async { self.status = "Error: Timeout processing segment \(index + 1)." }
                    processingErrorOccurred = true
                    try? FileManager.default.removeItem(atPath: segmentPath)
                    continue
                }

                if let path = srtPathOut, !path.isEmpty, FileManager.default.fileExists(atPath: path) {
                    if let content = try? String(contentsOfFile: path), !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        srtFiles.append(path)
                        try? FileManager.default.removeItem(atPath: segmentPath)
                    } else {
                        print("Warning: Empty or unreadable SRT generated for segment \(index + 1). Skipping.")
                        try? FileManager.default.removeItem(atPath: path)
                        try? FileManager.default.removeItem(atPath: segmentPath)
                    }
                } else {
                    print("Error: Whisper failed for segment \(index + 1). No SRT file generated or found.")
                    DispatchQueue.main.async { self.status = "Error: Failed segment \(index + 1)." }
                    processingErrorOccurred = true
                    try? FileManager.default.removeItem(atPath: segmentPath)
                    continue
                }
            }

            if processingErrorOccurred {
                DispatchQueue.main.async {
                    if !self.status.contains("Error:") { self.status = "Error: Transcription failed." }
                    self.isProcessing = false
                    self.stopProgressUpdateTimer()
                    self.stopLogUpdateTimer()
                }
                return
            }
            guard !srtFiles.isEmpty else {
                DispatchQueue.main.async { self.status = "Error: No subtitles generated."; self.isProcessing = false }
                return
            }

            // Merge SRT Files
            DispatchQueue.main.async { self.status = "Merging..." }
            let mergedSrtPathTemp = merge_srt(srt_files: srtFiles)
            guard !mergedSrtPathTemp.isEmpty else {
                DispatchQueue.main.async { self.status = "Error: SRT merge fail."; self.isProcessing = false }
                return
            }
            print("Merged SRT: \(mergedSrtPathTemp)")

            // Step 4: Parse Merged SRT
            DispatchQueue.main.async { self.status = "Parsing..." }
            var parsedSubtitles: [ParsedSubtitle] = []
            print("Parsing SRT path: \(mergedSrtPathTemp)")
            guard FileManager.default.fileExists(atPath: mergedSrtPathTemp) else {
                print("ERROR: Merged SRT missing!")
                DispatchQueue.main.async { self.status = "Error: Merged SRT missing."; self.isProcessing = false }
                return
            }
            do {
                let srtContent = try String(contentsOf: URL(fileURLWithPath: mergedSrtPathTemp), encoding: .utf8)
                print("Read SRT. Size: \(srtContent.count).")
                if srtContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("WARN: SRT empty!")
                    parsedSubtitles = []
                    print("Parsing skipped.")
                } else {
                    let parser = SRTParser()
                    let srtData = try parser.parse(srtContent)
                    parsedSubtitles = srtData.cues.map { (cue: SRT.Cue) in
                        let startTime = cue.metadata.timing.start
                        let endTime = cue.metadata.timing.end
                        let startSecondsTotal = Double(startTime.hours * 3600 + startTime.minutes * 60 + startTime.seconds) + Double(startTime.milliseconds) / 1000.0
                        let endSecondsTotal = Double(endTime.hours * 3600 + endTime.minutes * 60 + endTime.seconds) + Double(endTime.milliseconds) / 1000.0
                        let plainText = self.extractPlainText(from: cue.text.components)
                        return ParsedSubtitle(index: cue.counter, startTimeSeconds: startSecondsTotal, endTimeSeconds: endSecondsTotal, text: plainText)
                    }
                    print("Swift-srt-parser finished parsing.")
                }
                print("Mapped \(parsedSubtitles.count) original subtitles.")
                if parsedSubtitles.isEmpty && !srtContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    print("ERROR: Parser ret 0.")
                    throw NSError(domain: "SRTParse", code: 1, userInfo: [NSLocalizedDescriptionKey: "Parser rejected format?"])
                }
            } catch let parsingError {
                print("Error SRT parse: \(parsingError)\nDetails: \(parsingError.localizedDescription)")
                DispatchQueue.main.async { self.status = "Error: Failed parsing."; self.isProcessing = false }
                return
            }

            // Split Subtitles Based on UI Setting
            let wordsPerLineValue: Int
            switch capturedWordsPerLine {
            case "One line": wordsPerLineValue = 1
            case "Two lines": wordsPerLineValue = 2
            case "Three lines": wordsPerLineValue = 3
            default: wordsPerLineValue = 0
            }

            if wordsPerLineValue > 0 && !parsedSubtitles.isEmpty {
                DispatchQueue.main.async { self.status = "Splitting text..." }
                parsedSubtitles = self.splitSubtitles(parsedSubtitles, wordsPerLine: wordsPerLineValue)
            } else if wordsPerLineValue == 0 {
                print("Word Per Line setting is not 1, 2, or 3. Skipping text split.")
            }

            // Step 5: Generate FCPXML
            DispatchQueue.main.async { self.status = "Generating FCPXML..." }
            guard let fpsValue = Float(self.fps), fpsValue > 0 else {
                DispatchQueue.main.async { self.status = "Error: Invalid FPS for FCPXML."; self.isProcessing = false }
                return
            }
            print("--- Checking Parsed Subtitle Timings ---")
            for i in 0..<min(5, parsedSubtitles.count) {
                let sub = parsedSubtitles[i]
                print("Sub \(i): Start = \(sub.startTimeSeconds)s, End = \(sub.endTimeSeconds)s, Text = \(sub.text)")
            }

            let fcpxmlPathTemp = generateMotionFcpXml(
                parsedSubtitles: parsedSubtitles,
                fps: fpsValue,
                projectName: capturedProjectName,
                templateNameComponents: capturedMotionTemplate,
                templateRefID: templateRefID,
                fontName: capturedSelectedFont,
                fontSize: capturedTextSize,
                textWidth: capturedTextWidth,
                textColor: capturedSelectedColor
            )
            guard let finalFcpxmlPath = fcpxmlPathTemp, !finalFcpxmlPath.isEmpty else {
                DispatchQueue.main.async { self.status = "Error: FCPXML gen fail."; self.isProcessing = false }
                return
            }
            print("FCPXML: \(finalFcpxmlPath)")

            // Finalize UI State
            DispatchQueue.main.async {
                self.outputSRTFilePath = mergedSrtPathTemp
                self.outputFCPXMLFilePath = finalFcpxmlPath
                self.status = "Done"
                self.progress = 1.0
                self.progressPercentage = 100
                self.remainingTime = "00:00"
                self.isProcessing = false
                self.stopProgressUpdateTimer()
                self.stopLogUpdateTimer()
                print("Processing finished.")
            }
        }

        DispatchQueue.global(qos: .userInitiated).async(execute: workItem)
    }
    // MARK: Helper Functions

    // Parse Timestamps from Whisper Logs
    func parseTimestamps(from log: String) {
        guard let lastLine = log.split(separator: "\n").last else { return }
        if let range = lastLine.range(of: #"^\[\d{2}:\d{2}:\d{2}\.\d{3} -->"#, options: .regularExpression) {
            let timestampStr = String(lastLine[range].dropFirst().dropLast(5)) // e.g., "00:05:43.760"
            let components = timestampStr.split(separator: ":")
            if components.count == 3,
               let h = Double(components[0]),
               let m = Double(components[1]),
               let s = Double(components[2]) {
                let timestampSeconds = h * 3600 + m * 60 + s
                if self.currentSegmentDuration > 0 {
                    let newProgress = min(timestampSeconds / self.currentSegmentDuration, 1.0)
                    self.lastTimestampProgress = newProgress
                }
            }
        }
    }

    // Extract Plain Text from SRT StyledText Components
    func extractPlainText(from components: [SRT.StyledText.Component]?) -> String {
        guard let components = components else { return "" }
        var result = ""
        for component in components {
            switch component {
            case .plain(let text):
                result += text
            case .bold(let children):
                result += extractPlainText(from: children)
            case .italic(let children):
                result += extractPlainText(from: children)
            case .underline(let children):
                result += extractPlainText(from: children)
            default:
                print("Ignoring unhandled SRT text component type: \(component)")
            }
        }
        return result
    }

    // Split Subtitles Based on Words Per Line
    func splitSubtitles(_ subtitles: [ParsedSubtitle], wordsPerLine: Int) -> [ParsedSubtitle] {
        guard wordsPerLine > 0 else { return subtitles }
        var newSubtitles: [ParsedSubtitle] = []
        var globalIndex = 0
        for originalSub in subtitles {
            let words = originalSub.text.split { $0.isWhitespace }.map { String($0) }.filter { !$0.isEmpty }
            guard !words.isEmpty else { continue }
            let originalDuration = max(0.01, originalSub.endTimeSeconds - originalSub.startTimeSeconds)
            let totalWords = words.count
            for i in stride(from: 0, to: totalWords, by: wordsPerLine) {
                let chunkEndIndex = min(i + wordsPerLine, totalWords)
                let wordChunk = words[i..<chunkEndIndex].joined(separator: " ")
                let startWordIndex = i
                let endWordIndex = chunkEndIndex
                let newStartTime = originalSub.startTimeSeconds + (Double(startWordIndex) / Double(totalWords)) * originalDuration
                let newEndTime = originalSub.startTimeSeconds + (Double(endWordIndex) / Double(totalWords)) * originalDuration
                let safeEndTime = max(newStartTime + 0.05, newEndTime)
                let newSub = ParsedSubtitle(
                    index: globalIndex,
                    startTimeSeconds: newStartTime,
                    endTimeSeconds: safeEndTime,
                    text: wordChunk
                )
                newSubtitles.append(newSub)
                globalIndex += 1
            }
        }
        print("Split \(subtitles.count) original subtitles into \(newSubtitles.count) subtitles (\(wordsPerLine) words/line).")
        return newSubtitles
    }

    // MARK: Progress Update Timer Functions
    func startProgressUpdateTimer() {
        stopProgressUpdateTimer()
        self.progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            guard self.isProcessing else { return }
            DispatchQueue.main.async {
                let totalCount = Double(self.totalBatch)
                if totalCount > 0 {
                    let completedSegments = Double(self.currentSegmentIndex)
                    // Use the latest timestamp progress if available
                    var currentProgress = self.lastTimestampProgress
                    // Fallback to time-based estimation if segmentStartTime is available
                    if let startTime = self.segmentStartTime, self.currentSegmentDuration > 0 {
                        let elapsed = Date().timeIntervalSince(startTime)
                        // Estimate progress based on elapsed time, assuming linear processing
                        // Adjust the speed factor (1.5) based on observed transcription speed
                        let estimatedProgress = min(elapsed / (self.currentSegmentDuration * 1.5), 1.0)
                        // Use the maximum of timestamp-based and time-based progress
                        currentProgress = max(self.lastTimestampProgress, estimatedProgress)
                    }
                    self.currentSegmentProgress = currentProgress
                    let overallProgress = (completedSegments + currentProgress) / totalCount
                    self.progress = min(overallProgress, 1.0)
                    self.progressPercentage = Int(self.progress * 100)
                    if let startTime = self.processingStartTime, overallProgress > 0.01 {
                        let elapsed = Date().timeIntervalSince(startTime)
                        let estimatedTotal = elapsed / overallProgress
                        let remaining = max(0, estimatedTotal - elapsed)
                        let minutes = Int(remaining) / 60
                        let seconds = Int(remaining) % 60
                        self.remainingTime = String(format: "%02d:%02d", minutes, seconds)
                    }
                }
            }
        }
        RunLoop.current.add(self.progressTimer!, forMode: .common)
    }
    
    func stopProgressUpdateTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
    
    func startLogUpdateTimer() {
        stopLogUpdateTimer()
        self.logUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            guard self.isProcessing else { return }
            DispatchQueue.main.async {
                if !self.logBuffer.isEmpty {
                    self.outputCaptions += self.logBuffer
                    self.logBuffer = ""
                }
            }
        }
        RunLoop.current.add(self.logUpdateTimer!, forMode: .common)
    }
    
    func stopLogUpdateTimer() {
        logUpdateTimer?.invalidate()
        logUpdateTimer = nil
    }
    
    func cleanupTempDirectory(tempDir: String) {
        DispatchQueue.global(qos: .background).async {
            do {
                if FileManager.default.fileExists(atPath: tempDir) {
                    try FileManager.default.removeItem(atPath: tempDir)
                    print("Cleaned temp: \(tempDir)")
                }
            } catch {
                print("Warn: Failed temp cleanup \(tempDir): \(error)")
            }
        }
    }
    
    func download_model(model: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(model.lowercased()).bin") else {
            completion(false)
            return
        }
        let fm = FileManager.default
        guard let appSup = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
            completion(false)
            return
        }
        let subDir = appSup.appendingPathComponent("Sublord")
        do {
            try fm.createDirectory(at: subDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            completion(false)
            return
        }
        let dest = subDir.appendingPathComponent("ggml-\(model.lowercased()).bin")
        DispatchQueue.main.async {
            self.isDownloading = true
            self.downloadProgress = 0.0
            self.showAlert = true
        }
        let del = DownloadDelegate(
            model: model,
            progressHandler: { p in
                DispatchQueue.main.async {
                    if self.isDownloading { self.downloadProgress = p }
                }
            },
            completionHandler: {
                DispatchQueue.main.async {
                    if self.isDownloading {
                        self.isDownloading = false
                        self.showAlert = false
                        let success = fm.fileExists(atPath: dest.path)
                        completion(success)
                        self.downloadDelegate = nil
                    } else {
                        let successful = fm.fileExists(atPath: dest.path)
                        completion(successful)
                        self.downloadDelegate = nil
                    }
                }
            }
        )
        self.downloadDelegate = del
        let sess = URLSession(configuration: .default, delegate: del, delegateQueue: OperationQueue())
        let task = sess.downloadTask(with: url)
        del.downloadTaskRef = task
        task.resume()
    }
    
    func downloadFile(filePath: String) {
        guard !filePath.isEmpty, FileManager.default.fileExists(atPath: filePath) else { return }
        guard let dls = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let url = URL(fileURLWithPath: filePath)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 1
        var dest = dls.appendingPathComponent("\(base).\(ext)")
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = dls.appendingPathComponent("\(base)_\(counter).\(ext)")
            counter += 1
        }
        do {
            try FileManager.default.copyItem(at: url, to: dest)
            let alert = NSAlert()
            alert.messageText = "Download Complete"
            alert.informativeText = "File '\(dest.lastPathComponent)' saved."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Show")
            if alert.runModal() == .alertSecondButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([dest])
            }
        } catch {
            print("Error downloading file: \(error)")
        }
    }
    
    func backtofcpx(fcpxml_path_to_import: String, importToTimeline: Bool = false) {
        guard !fcpxml_path_to_import.isEmpty, FileManager.default.fileExists(atPath: fcpxml_path_to_import) else { return }
        let tempDirClean = self.currentTempDir
        let url = URL(fileURLWithPath: fcpxml_path_to_import)
        let ws = NSWorkspace.shared
        let id = "com.apple.FinalCut"
        guard let appURL = ws.urlForApplication(withBundleIdentifier: id) else { return }
        let conf = NSWorkspace.OpenConfiguration()
        conf.activates = true
        DispatchQueue.main.async { self.status = "Sending..." }
        ws.open([url], withApplicationAt: appURL, configuration: conf) { app, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error opening: \(error)")
                    self.status = "Error sending"
                } else {
                    print("Sent OK.")
                    self.status = "Import Sent"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.status = "Ready" }
                    if let tempDir = tempDirClean {
                        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5) {
                            self.cleanupTempDirectory(tempDir: tempDir)
                            DispatchQueue.main.async {
                                if self.currentTempDir == tempDir { self.currentTempDir = nil }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views/Extensions
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}

extension Color {
    func toHexString() -> String {
        let nsColor = NSColor(self)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02lX%02lX%02lX", lround(Double(r * 255)), lround(Double(g * 255)), lround(Double(b * 255)))
    }
}

// MARK: - Previews
struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView().frame(width: 850, height: 600)
    }
}
