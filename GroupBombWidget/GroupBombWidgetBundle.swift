import SwiftUI
import WidgetKit

/// Widget extension entry point. Add future widgets to this bundle as separate Widget values.
@main
struct GroupBombWidgetBundle: WidgetBundle {
    var body: some Widget {
        GroupProgressWidget()
    }
}
