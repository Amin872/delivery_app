import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // google_maps_flutter requires a Maps SDK for iOS key from the Google
    // Cloud Console (same project as orient-food-9c1e0, or any project with
    // the Maps SDK for iOS enabled). Replace the placeholder below — without
    // a real key, GoogleMap widgets fail to render map tiles.
    GMSServices.provideAPIKey("YOUR_MAPS_API_KEY_HERE")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
