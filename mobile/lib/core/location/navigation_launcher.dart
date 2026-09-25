import 'package:url_launcher/url_launcher.dart';

import '../../models/coordinates.dart';

/// Turn-by-turn handoff to Google Maps via its HTTPS "directions" universal
/// link — the same URL on Android and iOS; it opens the Google Maps app when
/// installed, otherwise the browser. No Maps API key, geocoding or routing
/// happens in this app. Only real coordinates are ever sent: a caller with no
/// pin should hide its "Navigate" action rather than fall back to searching
/// address text.

/// Google Maps driving directions to [destination]. Coordinates are written
/// with Dart's `toStringAsFixed`, which always uses '.' as the decimal
/// separator regardless of device locale.
Uri googleMapsDirectionsUri(Coordinates destination) {
  final lat = destination.latitude.toStringAsFixed(6);
  final lng = destination.longitude.toStringAsFixed(6);
  return Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': '$lat,$lng',
    'travelmode': 'driving',
  });
}

/// Signature of url_launcher's `launchUrl`, injectable for tests.
typedef UrlLaunchFn = Future<bool> Function(Uri uri, {LaunchMode mode});

/// Opens external navigation to [destination]. Returns false (never throws)
/// when nothing could handle the link, so the caller can show an error.
/// Deliberately doesn't call canLaunchUrl — on Android 11+ that needs
/// `<queries>` declarations, while launching an https link doesn't.
Future<bool> launchDirections(Coordinates destination, {UrlLaunchFn launch = launchUrl}) async {
  try {
    return await launch(googleMapsDirectionsUri(destination), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
