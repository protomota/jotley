import SwiftUI

public enum DetailTab: Int, CaseIterable, Identifiable {
    case summary = 0
    case transcript = 2

    public var id: Int { self.rawValue }

    public var title: String {
        switch self {
        case .summary: return "Summary"
        case .transcript: return "Transcript"
        }
    }

}
