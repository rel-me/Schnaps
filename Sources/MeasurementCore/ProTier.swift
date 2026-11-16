import Foundation

public enum ProTier: String, Codable, CaseIterable, Sendable, Identifiable {
    case sip, pour, reserve
    public var id: Self { self }
    public var name: String {
        switch self { case .sip: "Sip"; case .pour: "Pour"; case .reserve: "Reserve" }
    }
    public var price: Int {
        switch self { case .sip: 5; case .pour: 10; case .reserve: 50 }
    }
    public var rank: Int {
        switch self { case .sip: 1; case .pour: 2; case .reserve: 3 }
    }
    public var keepsake: String {
        switch self { case .sip: "Lucky Cork"; case .pour: "Little Bottle"; case .reserve: "Golden Decanter" }
    }
}
