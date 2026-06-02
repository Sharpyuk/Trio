
import Foundation

struct ShapeModel: Identifiable {
    var type: String
    var percent: Decimal
    var id = UUID()
}

struct ChartData: Identifiable {
    var date: Date
    var iob: Double
    var zt: Double
    var cob: Double
    var uam: Double
    var id = UUID()
}

struct ProteinFatActivityPoint: Identifiable, Equatable {
    var date: Date
    var fatActivity: Double
    var proteinActivity: Double
    var id = UUID()

    var combinedActivity: Double {
        fatActivity + proteinActivity
    }
}
