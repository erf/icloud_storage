import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'icloud_storage_method_channel.dart';

abstract class IcloudStoragePlatform extends PlatformInterface {
  /// Constructs a IcloudStoragePlatform.
  IcloudStoragePlatform() : super(token: _token);

  static final Object _token = Object();

  static IcloudStoragePlatform _instance = MethodChannelIcloudStorage();

  /// The default instance of [IcloudStoragePlatform] to use.
  ///
  /// Defaults to [MethodChannelIcloudStorage].
  static IcloudStoragePlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [IcloudStoragePlatform] when
  /// they register themselves.
  static set instance(IcloudStoragePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
