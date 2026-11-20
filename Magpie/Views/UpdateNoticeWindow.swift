import AppKit
import SwiftUI

@MainActor
enum UpdateNoticeWindow {
    static func make(
        notice: UpdateNotice,
        onOpen: @escaping (UpdateNotice.Action) -> Void
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = UpdateNoticeView(notice: notice) { [weak window] open in
            window?.close()
            if open { onOpen(notice.action) }
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.title = notice.title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private struct UpdateNoticeView: View {
    let notice: UpdateNotice
    let dismiss: (Bool) -> Void

    private var primaryTitle: String {
        switch notice.action {
        case .openMCPSettings: "Open MCP Settings"
        case .viewReleaseNotes: "View Release Notes"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text((try? AttributedString(markdown: notice.summary, options: .init(interpretedSyntax: .inlineOnly)))
                 ?? AttributedString(notice.summary))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()
                Button("Done") { dismiss(false) }
                    .keyboardShortcut(.cancelAction)
                Button(primaryTitle) { dismiss(true) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 430)
    }
}
