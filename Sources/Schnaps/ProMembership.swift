import Combine
import MeasurementCore

@MainActor
final class ProMembership: ObservableObject {
    @Published private(set) var tier: ProTier?
}
