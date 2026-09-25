import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // google_maps_flutter's Maps SDK for iOS key, read from Info.plist's
    // GMSApiKey, which Xcode fills from MAPS_API_KEY in the untracked
    // ios/Flutter/Maps.xcconfig (see mobile/README.md) — never committed.
    // Without it, a placeholder is used and map tiles stay blank.
    let configuredKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String ?? ""
    let hasKey = !configuredKey.isEmpty && !configuredKey.hasPrefix("$(")
    GMSServices.provideAPIKey(hasKey ? configuredKey : "YOUR_MAPS_API_KEY_HERE")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
