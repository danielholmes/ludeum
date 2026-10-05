import JournalCore

/// A screen the main window's sidebar can select, shown in the middle column.
enum Screen: Hashable {
    case library
    case whatToPlayNext
    case topRated
    case yearInReview
    case list(id: Int64, name: String)
    case platform(id: Int64, name: String)
    /// A pinned franchise or series: the Library filtered to it.
    case pinned(Pin)
    case reviewQueue
    case importPage
    case syncPage

    var title: String {
        switch self {
        case .library: "Library"
        case .whatToPlayNext: "What to play next"
        case .topRated: "Top-rated"
        case .yearInReview: "Year in review"
        case .list(_, let name): name
        case .platform(_, let name): name
        case .pinned(let pin): pin.name
        case .reviewQueue: "Review queue"
        case .importPage: "Import"
        case .syncPage: "Sync"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .whatToPlayNext: "play.circle"
        case .topRated: "star"
        case .yearInReview: "calendar"
        case .list: "list.bullet"
        case .platform: "gamecontroller"
        case .pinned(let pin):
            switch pin.kind {
            case .franchise: "star.square.on.square"
            case .series: "square.stack"
            case .theme: "theatermasks"
            case .company: "building.2"
            }
        case .reviewQueue: "tray"
        case .importPage: "square.and.arrow.down"
        case .syncPage: "arrow.triangle.2.circlepath"
        }
    }

    static let journal: [Screen] = [.library, .whatToPlayNext, .topRated, .yearInReview]
}
