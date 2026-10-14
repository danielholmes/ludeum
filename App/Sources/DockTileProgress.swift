import AppKit
import LudeumCore
import Observation

/// While Background tasks are queued or running, the Dock icon shows a bar of how far they've got across all of them,
/// and a badge of how many are queued or running. Once none are, the plain icon is back. Watched from launch, not from
/// a window, as the window can be closed while they run.
@MainActor enum DockTileProgress {
    /// Shows the tasks as they are now, then again each time that changes: observation tracking fires once, so each
    /// change watches afresh.
    static func watch(_ tasks: BackgroundTasks) {
        let shown = withObservationTracking {
            Shown(progress: tasks.overallProgress, active: tasks.activeCount)
        } onChange: {
            Task { @MainActor in watch(tasks) }
        }
        show(shown)
    }

    private struct Shown: Equatable {
        let progress: Double?
        let active: Int
    }

    /// What the icon shows now, so a change it wouldn't show (a queued task's title) doesn't redraw it. The plain icon to
    /// start with: watching starts while the app is still launching, before NSApp exists, and nothing's queued then.
    private static var last = Shown(progress: nil, active: 0)

    private static func show(_ shown: Shown) {
        guard shown != last else { return }
        last = shown
        let tile = NSApp.dockTile
        if let progress = shown.progress {
            let view = tile.contentView as? IconWithBar ?? IconWithBar(frame: NSRect(origin: .zero, size: tile.size))
            view.progress = progress
            tile.contentView = view
        } else {
            tile.contentView = nil
        }
        tile.badgeLabel = shown.active > 0 ? "\(shown.active)" : nil
        tile.display()
    }
}

/// The app icon with a progress bar across its foot, as Chrome shows a download's.
private final class IconWithBar: NSView {
    var progress = 0.0

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage.draw(in: bounds)
        let track = NSRect(x: bounds.width * 0.1, y: bounds.height * 0.08, width: bounds.width * 0.8, height: bounds.height * 0.1)
        let radius = track.height / 2
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let inset = track.insetBy(dx: track.height * 0.15, dy: track.height * 0.15)
        var filled = inset
        // Never narrower than it is tall, so at 0% it's a dot rather than nothing.
        filled.size.width = max(inset.height, inset.width * min(max(progress, 0), 1))
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: inset.height / 2, yRadius: inset.height / 2).fill()
    }
}
