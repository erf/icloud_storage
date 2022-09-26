import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'icloud_storage_platform_interface.dart';

/// An implementation of [IcloudStoragePlatform] that uses method channels.
class MethodChannelIcloudStorage extends IcloudStoragePlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('icloud_storage');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
