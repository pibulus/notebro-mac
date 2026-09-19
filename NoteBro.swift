import Cocoa
import SwiftUI
import UniformTypeIdentifiers

// MARK: - NoteBro Card Model
struct NoteCard: Identifiable, Codable, Equatable {
    var id: String
    var content: String
    var color: String // "yellow", "mint", "lavender", "peach", "sky"
    var isPinned: Bool?
    var createdAt: Date
    var updatedAt: Date

    var pinned: Bool {
        get { isPinned ?? false }
        set { isPinned = newValue }
    }

    var hashtags: [String] {
        let pattern = "#([a-zA-Z0-9_-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsString.length))
        var tags = [String]()
        for m in matches {
            if m.numberOfRanges > 1 {
                let tag = "#" + nsString.substring(with: m.range(at: 1)).lowercased()
                if !tags.contains(tag) {
                    tags.append(tag)
                }
            }
        }
        return tags
    }

    static func defaultCard() -> NoteCard {
        NoteCard(
            id: "card_\(UUID().uuidString.prefix(8))",
            content: """
yo! welcome to NoteBro for Mac 📝

• cursor is already blinking — just start typing
• ⌘← and ⌘→ (or buttons above) flick between index cards
• tap any pastel highlighter to color-code this card
• use #hashtags like #ideas or #todo for instant filtering
• ⌘N pulls a fresh card from the stack
• ⌥Space brings NoteBro up from anywhere
• close it or hit Esc — it's already saved

in a world of Word, be Notepad. zero friction.
""",
            color: "yellow",
            isPinned: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Pastel Palette
enum NotePastel {
    static let yellow = Color(red: 0.996, green: 0.941, blue: 0.541) // #FEF08A
    static let mint = Color(red: 0.655, green: 0.953, blue: 0.816)   // #A7F3D0
    static let lavender = Color(red: 0.914, green: 0.835, blue: 1.0) // #E9D5FF
    static let peach = Color(red: 0.996, green: 0.843, blue: 0.667)  // #FED7AA
    static let sky = Color(red: 0.729, green: 0.902, blue: 0.992)    // #BAE6FD

    static let paper = Color(red: 1.0, green: 0.98, blue: 0.941)     // #FFFAF0
    static let cardBg = Color.white
    static let ink = Color(red: 0.118, green: 0.09, blue: 0.078)     // #1E1714
    static let inkSoft = Color(red: 0.384, green: 0.345, blue: 0.329)// #625854
    static let inkMuted = Color(red: 0.608, green: 0.561, blue: 0.533)// #9B8F88

    static func colorFor(_ name: String) -> Color {
        switch name {
        case "yellow": return yellow
        case "mint": return mint
        case "lavender": return lavender
        case "peach": return peach
        case "sky": return sky
        default: return yellow
        }
    }

    static let allKeys = ["yellow", "mint", "lavender", "peach", "sky"]
}

// MARK: - Persistence Store
class NoteBroStore: ObservableObject {
    @Published var cards: [NoteCard] = []
    @Published var activeIndex: Int = 0

    private let fileManager = FileManager.default
    private var saveDebounceTimer: Timer?

    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let noteBroDir = appSupport.appendingPathComponent("NoteBro", isDirectory: true)
        if !fileManager.fileExists(atPath: noteBroDir.path) {
            try? fileManager.createDirectory(at: noteBroDir, withIntermediateDirectories: true)
        }
        return noteBroDir
    }

    private var storageFile: URL {
        storageDirectory.appendingPathComponent("notes.json")
    }

    init() {
        loadNotes()
    }

    func loadNotes() {
        do {
            if fileManager.fileExists(atPath: storageFile.path) {
                let data = try Data(contentsOf: storageFile)
                let decoder = JSONDecoder()
                let loaded = try decoder.decode([NoteCard].self, from: data)
                if !loaded.isEmpty {
                    self.cards = loaded
                    self.activeIndex = 0
                    return
                }
            }
        } catch {
            print("NoteBro: error loading notes, starting fresh: \(error)")
        }

        // Fallback default note
        self.cards = [NoteCard.defaultCard()]
        self.activeIndex = 0
        saveNotesImmediately()
    }

    func saveNotes() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.saveNotesImmediately()
        }
    }

    func saveNotesImmediately() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cards)
            try data.write(to: storageFile, options: .atomic)
        } catch {
            print("NoteBro: error saving notes: \(error)")
        }
    }

    @Published var selectedTag: String? = nil

    var allTags: [String] {
        let tagsSet = Set(cards.flatMap { $0.hashtags })
        return Array(tagsSet).sorted()
    }

    var activeCardIndices: [Int] {
        if let tag = selectedTag {
            return cards.enumerated().compactMap { idx, c in c.hashtags.contains(tag) ? idx : nil }
        }
        return Array(0..<cards.count)
    }

    var currentFilteredIndex: Int {
        let indices = activeCardIndices
        return indices.firstIndex(of: activeIndex) ?? 0
    }

    func togglePinCurrentCard() {
        guard activeIndex >= 0, activeIndex < cards.count else { return }
        cards[activeIndex].pinned.toggle()
        // If pinned, reorder so pinned cards bubble to front
        cards.sort { (a, b) -> Bool in
            if a.pinned != b.pinned {
                return a.pinned && !b.pinned
            }
            return a.updatedAt > b.updatedAt
        }
        activeIndex = 0
        saveNotesImmediately()
        NSSound(named: "Tink")?.play()
    }

    func toggleChecklist() {
        guard activeIndex >= 0, activeIndex < cards.count else { return }
        let current = cards[activeIndex].content
        if current.isEmpty {
            cards[activeIndex].content = "- [ ] "
        } else if current.hasSuffix("\n") {
            cards[activeIndex].content += "- [ ] "
        } else {
            cards[activeIndex].content += "\n- [ ] "
        }
        cards[activeIndex].updatedAt = Date()
        saveNotes()
        NSSound(named: "Pop")?.play()
    }

    var currentCard: NoteCard? {
        guard !cards.isEmpty, activeIndex >= 0, activeIndex < cards.count else { return nil }
        return cards[activeIndex]
    }

    func updateCurrentCard(content: String) {
        guard activeIndex >= 0, activeIndex < cards.count else { return }
        cards[activeIndex].content = content
        cards[activeIndex].updatedAt = Date()
        saveNotes()
    }

    func setCurrentCardColor(_ colorName: String) {
        guard activeIndex >= 0, activeIndex < cards.count else { return }
        cards[activeIndex].color = colorName
        cards[activeIndex].updatedAt = Date()
        saveNotesImmediately()
    }

    func addCard() {
        let newCard = NoteCard(
            id: "card_\(UUID().uuidString.prefix(8))",
            content: "",
            color: NotePastel.allKeys.randomElement() ?? "yellow",
            isPinned: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        cards.append(newCard)
        selectedTag = nil
        activeIndex = cards.count - 1
        saveNotesImmediately()
        NSSound(named: "Pop")?.play()
    }

    func deleteCurrentCard() {
        guard cards.count > 1 else { return }
        cards.remove(at: activeIndex)
        if activeIndex >= cards.count {
            activeIndex = cards.count - 1
        }
        saveNotesImmediately()
        NSSound(named: "Basso")?.play()
    }

    func nextCard() {
        let indices = activeCardIndices
        guard !indices.isEmpty else { return }
        if let currentPos = indices.firstIndex(of: activeIndex), currentPos < indices.count - 1 {
            activeIndex = indices[currentPos + 1]
            NSSound(named: "Tink")?.play()
        }
    }

    func prevCard() {
        let indices = activeCardIndices
        guard !indices.isEmpty else { return }
        if let currentPos = indices.firstIndex(of: activeIndex), currentPos > 0 {
            activeIndex = indices[currentPos - 1]
            NSSound(named: "Tink")?.play()
        }
    }

    func exportAllToMarkdown() -> URL? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let md = cards.enumerated().map { (index, card) in
            """
            ---
            Card \(index + 1) of \(cards.count) | Color: \(card.color) | \(formatter.string(from: card.updatedAt))
            ---

            \(card.content)
            """
        }.joined(separator: "\n\n")

        let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let exportURL = desktop.appendingPathComponent("NoteBro-Export.md")
        do {
            try md.write(to: exportURL, atomically: true, encoding: .utf8)
            return exportURL
        } catch {
            print("NoteBro: export error: \(error)")
            return nil
        }
    }

    func openNotesFolder() {
        NSWorkspace.shared.open(storageDirectory)
    }
}

// MARK: - Auto-focusing NSTextView Wrapper
struct FocusableTextView: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FocusableTextView
        var isUpdating = false

        init(_ parent: FocusableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onCommit()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular)
        textView.textColor = NSColor(red: 0.118, green: 0.09, blue: 0.078, alpha: 1.0)
        textView.insertionPointColor = NSColor(red: 0.118, green: 0.09, blue: 0.078, alpha: 1.0)
        textView.isRichText = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 4)

        // Set sizing
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        // Auto focus cursor immediately
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            let len = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: len, length: 0))
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            context.coordinator.isUpdating = true
            let selectedRange = textView.selectedRange()
            textView.string = text
            let safeLocation = min(selectedRange.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
            context.coordinator.isUpdating = false
        }

        // Keep cursor focused when view refreshes
        DispatchQueue.main.async {
            if textView.window?.firstResponder != textView {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }
}

// MARK: - SwiftUI Main Card View
struct NoteBroCardView: View {
    @ObservedObject var store: NoteBroStore
    @State private var copiedToast = false
    @State private var exportToast: String? = nil

    private var activeCard: NoteCard {
        store.currentCard ?? NoteCard.defaultCard()
    }

    private var wordsCount: Int {
        activeCard.content.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var cardAccentColor: Color {
        NotePastel.colorFor(activeCard.color)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Deck Navigation + Pastels + Actions
            HStack(spacing: 8) {
                // Card Nav Arrows & Indicator
                HStack(spacing: 4) {
                    Button(action: { store.prevCard() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(NotePastel.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.activeIndex == 0)
                    .opacity(store.activeIndex == 0 ? 0.35 : 1.0)
                    .keyboardShortcut("[", modifiers: [.command])

                    Text("\(store.currentFilteredIndex + 1)/\(max(store.activeCardIndices.count, 1))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(NotePastel.yellow.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(NotePastel.ink, lineWidth: 1.5))

                    Button(action: { store.nextCard() }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 22, height: 22)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(NotePastel.ink, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.currentFilteredIndex >= store.activeCardIndices.count - 1)
                    .opacity(store.currentFilteredIndex >= store.activeCardIndices.count - 1 ? 0.35 : 1.0)
                    .keyboardShortcut("]", modifiers: [.command])
                }

                Spacer()

                // Pastel Marker Pills
                HStack(spacing: 6) {
                    ForEach(NotePastel.allKeys, id: \.self) { key in
                        Button(action: {
                            store.setCurrentCardColor(key)
                        }) {
                            Circle()
                                .fill(NotePastel.colorFor(key))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .stroke(NotePastel.ink, lineWidth: activeCard.color == key ? 2 : 1)
                                )
                                .scaleEffect(activeCard.color == key ? 1.2 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // New Card Button
                Button(action: { store.addCard() }) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                        Text("New")
                    }
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(NotePastel.mint)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(NotePastel.ink, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: [.command])
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, store.allTags.isEmpty ? 8 : 4)
            .background(NotePastel.paper)

            // Hashtag Pills Bar (if tags exist)
            if !store.allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        Button(action: { store.selectedTag = nil }) {
                            Text("All (\(store.cards.count))")
                                .font(.system(size: 10, weight: store.selectedTag == nil ? .bold : .medium, design: .monospaced))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(store.selectedTag == nil ? NotePastel.yellow : Color.white)
                                .foregroundColor(NotePastel.ink)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(NotePastel.ink, lineWidth: 1.2))
                        }
                        .buttonStyle(.plain)

                        ForEach(store.allTags, id: \.self) { tag in
                            Button(action: {
                                if store.selectedTag == tag {
                                    store.selectedTag = nil
                                } else {
                                    store.selectedTag = tag
                                    if let firstMatch = store.activeCardIndices.first {
                                        store.activeIndex = firstMatch
                                    }
                                }
                            }) {
                                Text(tag)
                                    .font(.system(size: 10, weight: store.selectedTag == tag ? .bold : .medium, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2.5)
                                    .background(store.selectedTag == tag ? NotePastel.mint : Color.white)
                                    .foregroundColor(NotePastel.ink)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(NotePastel.ink, lineWidth: 1.2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
                }
                .background(NotePastel.paper)
            }

            // Index Card Border Accent Bar
            Rectangle()
                .fill(cardAccentColor)
                .frame(height: 5)

            // Editor Area (Focused immediately)
            ZStack(alignment: .bottomTrailing) {
                FocusableTextView(
                    text: Binding(
                        get: { store.currentCard?.content ?? "" },
                        set: { store.updateCurrentCard(content: $0) }
                    ),
                    onCommit: {
                        store.saveNotes()
                    }
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(NotePastel.cardBg)

                // Copied / Exported Notification Toast
                if copiedToast || exportToast != nil {
                    Text(copiedToast ? "✓ Copied to clipboard" : (exportToast ?? ""))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(NotePastel.yellow)
                        .foregroundColor(NotePastel.ink)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(NotePastel.ink, lineWidth: 1.5))
                        .padding(12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(height: 330)

            // Footer / Metadata / Bro Tools
            HStack(spacing: 8) {
                // Word count
                Text("\(wordsCount) \(wordsCount == 1 ? "word" : "words")")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(NotePastel.inkMuted)

                // Pin Card Toggle Button
                Button(action: { store.togglePinCurrentCard() }) {
                    HStack(spacing: 3) {
                        Image(systemName: activeCard.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 10))
                        if activeCard.pinned {
                            Text("Pinned")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(activeCard.pinned ? NotePastel.yellow : Color.white)
                    .foregroundColor(NotePastel.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(NotePastel.ink, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .help(activeCard.pinned ? "Unpin card" : "Pin card to front")

                // Insert Checklist Button
                Button(action: { store.toggleChecklist() }) {
                    Text("☑︎ Todo")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white)
                        .foregroundColor(NotePastel.inkSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(NotePastel.ink, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .help("Insert - [ ] checklist item")

                Spacer()

                // Copy active card
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(activeCard.content, forType: .string)
                    withAnimation { copiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { copiedToast = false }
                    }
                }) {
                    Text("Copy")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(NotePastel.ink, lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: [.command, .shift])

                // Delete card (if > 1)
                if store.cards.count > 1 {
                    Button(action: { store.deleteCurrentCard() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(NotePastel.inkMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Delete this card (⌘⌫)")
                    .keyboardShortcut(.delete, modifiers: [.command])
                }

                // More Menu
                Menu {
                    Button("Export All to Markdown… (⌘E)") {
                        if let url = store.exportAllToMarkdown() {
                            withAnimation { exportToast = "Saved to Desktop!" }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                withAnimation { exportToast = nil }
                            }
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                    .keyboardShortcut("e", modifiers: [.command])

                    Button("Open Notes Folder") {
                        store.openNotesFolder()
                    }

                    Divider()

                    Button("NoteBro Web (notebro.app)") {
                        if let url = URL(string: "https://notebro.app") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                    Button("Quit NoteBro (⌘Q)") {
                        store.saveNotesImmediately()
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: [.command])
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundColor(NotePastel.inkSoft)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(NotePastel.paper)
            .overlay(
                Rectangle()
                    .frame(height: 1.5)
                    .foregroundColor(NotePastel.ink.opacity(0.15)),
                alignment: .top
            )
        }
        .frame(width: 420)
        .background(NotePastel.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(NotePastel.ink, lineWidth: 2)
        )
    }
}

// MARK: - App Delegate & Menu Bar Wiring
@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var store = NoteBroStore()
    private var globalHotkeyMonitors: [Any] = []

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. Menu Bar Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            configureStatusIcon(button: button)
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }

        // 2. Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 410, height: 430)
        popover.behavior = .transient
        popover.animates = true

        let contentView = NoteBroCardView(store: store)
        popover.contentViewController = NSHostingController(rootView: contentView)

        // 3. Global Hotkey (Option + Space)
        setupGlobalShortcut()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        store.saveNotesImmediately()
    }

    private func configureStatusIcon(button: NSStatusBarButton) {
        if let image = NSImage(named: "bro-menubar") {
            let icon = image.copy() as! NSImage
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = true
            button.image = icon
            return
        }

        // Draw crisp index card / memo icon as fallback
        let size = NSSize(width: 18, height: 18)
        let icon = NSImage(size: size, flipped: false) { rect in
            let cardRect = NSRect(x: 2, y: 1.5, width: 14, height: 15)
            let path = NSBezierPath(roundedRect: cardRect, xRadius: 3, yRadius: 3)
            NSColor.labelColor.setStroke()
            path.lineWidth = 1.4
            path.stroke()

            // Header line
            let hLine = NSBezierPath()
            hLine.move(to: NSPoint(x: 4.5, y: 11.5))
            hLine.line(to: NSPoint(x: 13.5, y: 11.5))
            hLine.lineWidth = 1.2
            hLine.stroke()

            // Note line 1
            let line1 = NSBezierPath()
            line1.move(to: NSPoint(x: 4.5, y: 7.5))
            line1.line(to: NSPoint(x: 11.5, y: 7.5))
            line1.lineWidth = 1.1
            line1.stroke()

            // Note line 2
            let line2 = NSBezierPath()
            line2.move(to: NSPoint(x: 4.5, y: 4.5))
            line2.line(to: NSPoint(x: 9.5, y: 4.5))
            line2.lineWidth = 1.1
            line2.stroke()

            return true
        }
        icon.isTemplate = true
        button.image = icon
    }

    @objc func statusItemClicked(_ sender: Any?) {
        togglePopover()
    }

    func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            store.saveNotesImmediately()
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// Global Option + Space shortcut listener
    private func setupGlobalShortcut() {
        // Global monitor (when NoteBro is inactive)
        let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Option (524288 / .option) + Space (keyCode 49)
            if event.keyCode == 49 && event.modifierFlags.contains(.option) {
                DispatchQueue.main.async {
                    self?.togglePopover()
                }
            }
        }
        if let g = global { globalHotkeyMonitors.append(g) }

        // Local monitor (when NoteBro popover is key)
        let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Esc closes popover
            if event.keyCode == 53 {
                self?.store.saveNotesImmediately()
                self?.popover.performClose(nil)
                return nil
            }
            // Option + Space toggles
            if event.keyCode == 49 && event.modifierFlags.contains(.option) {
                self?.togglePopover()
                return nil
            }
            return event
        }
        globalHotkeyMonitors.append(local as Any)
    }
}
