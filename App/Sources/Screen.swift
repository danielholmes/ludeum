import LudeumCore

/// A screen the main window's sidebar can select, shown in the middle column.
enum Screen: Hashable, Codable {
    case library
    /// Library shortcuts: the Library scoped to Finished or Childhood, like a Platform.
    case finished
    case childhood
    case whatToPlayNext
    case topRated
    case yearInReview
    /// Searching IGDB to add Games.
    case igdb
    case list(id: Int64, name: String)
    case platform(id: Int64, name: String)
    /// A pinned franchise or series: the Library filtered to it.
    case pinned(Pin)
    case reviewQueue

    var title: String {
        switch self {
        case .library: "Library"
        case .finished: "Finished"
        case .childhood: "Childhood"
        case .whatToPlayNext: "What to play next"
        case .topRated: "Top-rated"
        case .yearInReview: "Year in review"
        case .igdb: "IGDB"
        case .list(_, let name): name
        case .platform(_, let name): name
        case .pinned(let pin): pin.name
        case .reviewQueue: "Review queue"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "books.vertical"
        case .finished: "flag.checkered"
        case .childhood: "teddybear"
        case .whatToPlayNext: "play.circle"
        case .topRated: "star"
        case .yearInReview: "calendar"
        case .igdb: "magnifyingglass"
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
        }
    }

    /// The filter a Library shortcut opens with.
    var shortcutFilter: LibraryFilter? {
        switch self {
        case .finished: LibraryFilter(outcome: .finished)
        case .childhood: LibraryFilter(childhood: true)
        default: nil
        }
    }

    static let journal: [Screen] = [
        .library, .finished, .childhood, .whatToPlayNext, .topRated, .yearInReview, .igdb,
    ]
}
