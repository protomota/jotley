import WidgetKit
import SwiftUI

@main
struct JotleyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickRecordWidget()
        RecordingLiveActivity()
    }
}
