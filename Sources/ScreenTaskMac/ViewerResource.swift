// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum ViewerResource {
    static var url: URL {
        if let bundleURL = Bundle.main.url(forResource: "ScreenTaskMac_ScreenTaskMac", withExtension: "bundle"),
           let bundle = Bundle(url: bundleURL),
           let url = bundle.url(forResource: "index", withExtension: "html", subdirectory: "Resources") { return url }
        precondition(Bundle.main.bundleURL.pathExtension != "app", "Missing bundled viewer resource")
        return Bundle.module.url(forResource: "index", withExtension: "html", subdirectory: "Resources")!
    }
}
