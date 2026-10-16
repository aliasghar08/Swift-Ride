/// Platform-dispatching location service.
///
/// - iOS + Android → location_service_io.dart  (native MethodChannel)
/// - Web           → location_service_web.dart (navigator.geolocation)
/// - Other         → location_service_stub.dart (reports no fix)
///
/// The compiler picks one at build time. Nothing else in this file.
library;

export 'location_models.dart';

export 'location_service_stub.dart'
    if (dart.library.io) 'location_service_io.dart'
    if (dart.library.js_interop) 'location_service_web.dart'
    if (dart.library.html) 'location_service_web.dart';