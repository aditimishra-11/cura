// Generated file — do not edit manually
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web not supported');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
            'DefaultFirebaseOptions are not supported for this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCvyuh8NaeXaPtbHaUJ0psKfNom4ghWVqE',
    appId: '1:594980338208:android:20c08dd9ed628238481a45',
    messagingSenderId: '594980338208',
    projectId: 'cura-7942c',
    storageBucket: 'cura-7942c.firebasestorage.app',
  );
}
