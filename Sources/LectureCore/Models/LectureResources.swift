import Foundation
public enum LectureResources {
    public static var bundle: Bundle {
        if let resources = Bundle.main.resourceURL,
           let embedded = Bundle(url: resources.appendingPathComponent("LectureRecorder_LectureCore.bundle")) { return embedded }
        return Bundle.module
    }
}
