import 'package:meta/meta.dart';

/// Class that represents the chat config. Can be used for setting custom names
/// for rooms and users paths. Call [FirebaseChatCore.instance.setConfig]
/// before doing anything else with [FirebaseChatCore.instance] if you want to
/// change the default collection names. When using custom names don't forget
/// to update your security rules and indexes.
@immutable
class FirebaseChatCoreConfig {
  const FirebaseChatCoreConfig(
    this.firebaseAppName,
    this.roomsPathName,
    this.usersPathName,
  );

  /// Property to set custom firebase app name.
  final String? firebaseAppName;

  /// Property to set rooms path name.
  final String roomsPathName;

  /// Property to set users path name.
  final String usersPathName;
}
