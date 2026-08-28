import 'package:flutter/foundation.dart';

/// Desktop builds are assumed to have a mouse; phone and watch builds do not
/// — there is no runtime signal on Android/iOS worth asking, since a
/// Bluetooth mouse paired to a phone is not a case this app supports.
bool probeHasPointer() => switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
  _ => false,
};
