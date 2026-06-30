import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC_xeD9iE3tm9nxoA6R4nWmIb2ANucrlHI',
    appId: '1:408478040204:web:a7f9910156128041257ba9',
    messagingSenderId: '408478040204',
    projectId: 'uppibrazil',
    authDomain: 'uppibrazil.firebaseapp.com',
    storageBucket: 'uppibrazil.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC_xeD9iE3tm9nxoA6R4nWmIb2ANucrlHI',
    appId: '1:408478040204:android:c6a585eb17846549257ba9',
    messagingSenderId: '408478040204',
    projectId: 'uppibrazil',
    storageBucket: 'uppibrazil.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDYibag1bUBfALQeX311NheZ5uiEzy3sE8',
    appId: '1:408478040204:ios:736d0497036b223e257ba9',
    messagingSenderId: '408478040204',
    projectId: 'uppibrazil',
    storageBucket: 'uppibrazil.firebasestorage.app',
    iosBundleId: 'online.uppi.rider',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDYibag1bUBfALQeX311NheZ5uiEzy3sE8',
    appId: '1:408478040204:ios:736d0497036b223e257ba9',
    messagingSenderId: '408478040204',
    projectId: 'uppibrazil',
    storageBucket: 'uppibrazil.firebasestorage.app',
    iosBundleId: 'online.uppi.rider',
  );
}
