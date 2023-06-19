import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

import 'firebase_chat_core_config.dart';
import 'util.dart';

/// Provides access to Firebase chat data. Singleton, use
/// FirebaseChatCore.instance to aceess methods.
class FirebaseChatCore {
  FirebaseChatCore._privateConstructor() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      firebaseUser = user;
    });
  }

  /// Config to set custom names for rooms and users paths. Also
  /// see [FirebaseChatCoreConfig].
  FirebaseChatCoreConfig config = const FirebaseChatCoreConfig(
    null,
    'rooms',
    'users',
  );

  /// Current logged in user in Firebase. Does not update automatically.
  /// Use [FirebaseAuth.authStateChanges] to listen to the state changes.
  User? firebaseUser = FirebaseAuth.instance.currentUser;

  /// Singleton instance.
  static final FirebaseChatCore instance = FirebaseChatCore._privateConstructor();

  /// Gets proper [FirebaseDatabase] instance.
  DatabaseReference getFirebaseDatabase() => FirebaseDatabase.instance.ref();

  /// Sets custom config to change default names for rooms
  /// and users paths. Also see [FirebaseChatCoreConfig].
  void setConfig(FirebaseChatCoreConfig firebaseChatCoreConfig) {
    config = firebaseChatCoreConfig;
  }

  /// Creates a chat group room with [users]. Creator is automatically
  /// added to the group. [name] is required and will be used as
  /// a group name. Add an optional [imageUrl] that will be a group avatar
  /// and [metadata] for any additional custom data.
  Future<types.Room> createGroupRoom({
    types.Role creatorRole = types.Role.admin,
    String? imageUrl,
    Map<String, dynamic>? metadata,
    required String name,
    required List<types.User> users,
  }) async {
    if (firebaseUser == null) return Future.error('User does not exist');

    final currentUser = await fetchUser(
      getFirebaseDatabase(),
      firebaseUser!.uid,
      config.usersPathName,
      role: creatorRole.toShortString(),
    );

    final roomUsers = [types.User.fromJson(currentUser)] + users;

    final roomRef = getFirebaseDatabase().child(config.roomsPathName).push();

    await roomRef.set({
      'createdAt': ServerValue.timestamp,
      'imageUrl': imageUrl,
      'metadata': metadata,
      'name': name,
      'type': types.RoomType.group.toShortString(),
      'updatedAt': ServerValue.timestamp,
      'userIds': roomUsers.map((u) => u.id).toList(),
      'userRoles': roomUsers.fold<Map<String, String?>>(
        {},
        (previousValue, user) => {
          ...previousValue,
          user.id: user.role?.toShortString(),
        },
      ),
    });

    return types.Room(
      id: roomRef.key!,
      imageUrl: imageUrl,
      metadata: metadata,
      name: name,
      type: types.RoomType.group,
      users: roomUsers,
    );
  }

  /// Creates a direct chat for 2 people. Add [metadata] for any additional
  /// custom data.
  Future<types.Room> createRoom(
    types.User otherUser, {
    Map<String, dynamic>? metadata,
  }) async {
    final fu = firebaseUser;

    if (fu == null) return Future.error('User does not exist');

    // Sort two user ids array to always have the same array for both users,
    // this will make it easy to find the room if exist and make one read only.
    final userIds = [fu.uid, otherUser.id]..sort();

    // Check if room already exist.
    // Get the rooms that the user is in.
    final userRoomsRef = getFirebaseDatabase().child('${config.usersPathName}/${fu.uid}/rooms');
    final userRoomsRefEvent = await userRoomsRef.once();
    if (userRoomsRefEvent.snapshot.value != null) {
      final userRoomsSnapshot = userRoomsRefEvent.snapshot as Map<String, dynamic>;
      // Loop through all of the rooms that the user is in.
      for (var roomId in userRoomsSnapshot.keys) {
        // Get the room.
        final roomRef = await getFirebaseDatabase().child('${config.roomsPathName}/$roomId').once();

        if (roomRef.snapshot.value != null) {
          final roomSnapshot = roomRef.snapshot as Map<String, dynamic>;

          final room = Map<String, dynamic>.from(roomSnapshot);
          final roomType = room['type'];
          final usersInRoom = List<String>.from(room['userIds']);
          if (roomType == types.RoomType.direct.toShortString() && usersInRoom.toSet().containsAll(userIds)) {
            return types.Room.fromJson(roomSnapshot);
          }
        }
      }
    }

    final currentUser = await fetchUser(
      getFirebaseDatabase(),
      fu.uid,
      config.usersPathName,
    );

    final users = [types.User.fromJson(currentUser), otherUser];

    // Create new room with sorted user ids array.
    final roomRef = getFirebaseDatabase().child(config.roomsPathName).push();
    await roomRef.set({
      'createdAt': ServerValue.timestamp,
      'imageUrl': null,
      'metadata': metadata,
      'name': null,
      'type': types.RoomType.direct.toShortString(),
      'updatedAt': ServerValue.timestamp,
      'userIds': userIds,
      'userRoles': null,
    });

    // Add the new room to the current user's rooms.
    await userRoomsRef.child(roomRef.key!).set(true);

    return types.Room(
      id: roomRef.key!,
      metadata: metadata,
      type: types.RoomType.direct,
      users: users,
    );
  }

  /// Creates [types.User] in Firebase to store name and avatar used on
  /// rooms list.
  Future<void> createUserInDatabase(types.User user) async {
    await getFirebaseDatabase().child('${config.usersPathName}/${user.id}').set({
      'createdAt': ServerValue.timestamp,
      'firstName': user.firstName,
      'imageUrl': user.imageUrl,
      'lastName': user.lastName,
      'lastSeen': ServerValue.timestamp,
      'metadata': user.metadata,
      'role': user.role?.toShortString(),
      'updatedAt': ServerValue.timestamp,
    });
  }

  /// Removes message.
  Future<void> deleteMessage(String roomId, String messageId) async {
    await getFirebaseDatabase().child('${config.roomsPathName}/$roomId/messages/$messageId').remove();
  }

  /// Removes room.
  Future<void> deleteRoom(String roomId) async {
    await getFirebaseDatabase().child('${config.roomsPathName}/$roomId').remove();
  }

  /// Removes [types.User] from `users` path in Firebase Realtime DB.
  Future<void> deleteUserFromRealtimeDB(String userId) async {
    await getFirebaseDatabase().child('${config.usersPathName}/$userId').remove();
  }

  /// Returns a stream of messages from Firebase for a given room.
  Stream<List<types.Message>> messages(
    types.Room room, {
    int? limit,
  }) =>
      getFirebaseDatabase()
          .child('${config.roomsPathName}/${room.id}/messages')
          .orderByChild('createdAt')
          .limitToFirst(limit ?? 100) // Limit the number of messages to fetch at once. Default is 100.
          .onValue
          .map(
        (event) {
          if (event.snapshot.value == null) {
            return <types.Message>[];
          }

          final dataMap = event.snapshot.value as Map<String, dynamic>;
          final dataList = dataMap.values.map((v) => Map<String, dynamic>.from(v as Map)).toList();
          dataList.sort((a, b) => b['createdAt'].compareTo(a['createdAt'])); // Sort by 'createdAt' in descending order.

          return dataList.map((data) {
            final author = room.users.firstWhere(
              (u) => u.id == data['authorId'],
              orElse: () => types.User(id: data['authorId'] as String),
            );

            data['author'] = author.toJson();

            return types.Message.fromJson(data);
          }).toList();
        },
      );

  /// Returns a stream of changes in a room from Firebase.
  Stream<types.Room> room(String roomId) {
    final fu = firebaseUser;

    if (fu == null) return const Stream.empty();

    return getFirebaseDatabase().child('${config.roomsPathName}/$roomId').onValue.map((event) async {
          final roomData = Map<String, dynamic>.from(event.snapshot.value);
          return types.Room.fromJson(roomData);
        } as types.Room Function(DatabaseEvent event));
  }

  /// Returns a stream of rooms from Firebase. Only rooms where current
  /// logged in user exist are returned. [orderByUpdatedAt] is used in case
  /// you want to have last modified rooms on top, there are a couple
  /// of things you will need to do though:
  /// 1) Make sure `updatedAt` exists on all rooms
  /// 2) Write a Cloud Function which will update `updatedAt` of the room
  /// when the room changes or new messages come in.
  Stream<List<types.Room>> rooms({bool orderByUpdatedAt = false}) {
    final fu = firebaseUser;

    if (fu == null) return const Stream.empty();

    return getFirebaseDatabase().child(config.roomsPathName).onValue.map(
      (event) {
        if (event.snapshot.value == null) {
          return <types.Room>[];
        }

        final roomsMap = Map<String, dynamic>.from(event.snapshot.value as Map<String, dynamic>);
        final roomsList = roomsMap.values.map((v) => Map<String, dynamic>.from(v)).toList();
        final filteredRooms = <Map<String, dynamic>>[];

        for (var room in roomsList) {
          final List<dynamic> userIds = room['userIds'] ?? [];
          if (userIds.contains(fu.uid)) {
            filteredRooms.add(room);
          }
        }

        if (orderByUpdatedAt) {
          filteredRooms.sort((a, b) => b['updatedAt'].compareTo(a['updatedAt']));
        }

        return filteredRooms.map((roomData) => types.Room.fromJson(roomData)).toList();
      },
    );
  }

  /// Sends a message to Firebase Realtime DB. Accepts any partial message and a
  /// room ID. If arbitraty data is provided in the [partialMessage]
  /// does nothing.
  void sendMessage(dynamic partialMessage, String roomId) async {
    if (firebaseUser == null) return;

    types.Message? message;

    if (partialMessage is types.PartialCustom) {
      message = types.CustomMessage.fromPartial(
        author: types.User(id: firebaseUser!.uid),
        id: '',
        partialCustom: partialMessage,
      );
    } else if (partialMessage is types.PartialFile) {
      message = types.FileMessage.fromPartial(
        author: types.User(id: firebaseUser!.uid),
        id: '',
        partialFile: partialMessage,
      );
    } else if (partialMessage is types.PartialImage) {
      message = types.ImageMessage.fromPartial(
        author: types.User(id: firebaseUser!.uid),
        id: '',
        partialImage: partialMessage,
      );
    } else if (partialMessage is types.PartialText) {
      message = types.TextMessage.fromPartial(
        author: types.User(id: firebaseUser!.uid),
        id: '',
        partialText: partialMessage,
      );
    }

    if (message != null) {
      final messageMap = message.toJson();
      messageMap.removeWhere((key, value) => key == 'author' || key == 'id');
      messageMap['authorId'] = firebaseUser!.uid;
      messageMap['createdAt'] = ServerValue.timestamp;
      messageMap['updatedAt'] = ServerValue.timestamp;

      final messageRef = getFirebaseDatabase().child('${config.roomsPathName}/$roomId/messages').push();
      await messageRef.set(messageMap);

      await getFirebaseDatabase().child('${config.roomsPathName}/$roomId').update({'updatedAt': ServerValue.timestamp});
    }
  }

  /// Updates a message in Firebase Realtime DB. Accepts any message and a
  /// room ID. Message will probably be taken from the [messages] stream.
  void updateMessage(types.Message message, String roomId) async {
    if (firebaseUser == null) return;
    if (message.author.id != firebaseUser!.uid) return;

    final messageMap = message.toJson();
    messageMap.removeWhere(
      (key, value) => key == 'author' || key == 'createdAt' || key == 'id',
    );
    messageMap['authorId'] = message.author.id;
    messageMap['updatedAt'] = ServerValue.timestamp;

    await getFirebaseDatabase().child('${config.roomsPathName}/$roomId/messages/${message.id}').update(messageMap);
  }

  /// Updates a room in Firebase Realtime DB. Accepts any room.
  /// Room will probably be taken from the [rooms] stream.
  void updateRoom(types.Room room) async {
    if (firebaseUser == null) return;

    final roomMap = room.toJson();
    roomMap.removeWhere((key, value) => key == 'createdAt' || key == 'id' || key == 'lastMessages' || key == 'users');

    if (room.type == types.RoomType.direct) {
      roomMap['imageUrl'] = null;
      roomMap['name'] = null;
    }

    roomMap['lastMessages'] = room.lastMessages?.map((m) {
      final messageMap = m.toJson();

      messageMap
          .removeWhere((key, value) => key == 'author' || key == 'createdAt' || key == 'id' || key == 'updatedAt');

      messageMap['authorId'] = m.author.id;

      return messageMap;
    }).toList();
    roomMap['updatedAt'] = ServerValue.timestamp;
    roomMap['userIds'] = room.users.map((u) => u.id).toList();

    await getFirebaseDatabase().child('${config.roomsPathName}/${room.id}').update(roomMap);
  }

  /// Returns a stream of all users from Firebase.
  Stream<List<types.User>> users() {
    if (firebaseUser == null) return const Stream.empty();

    final usersRef = getFirebaseDatabase().child(config.usersPathName);
    return usersRef.onValue.map((event) {
      final dataMap = Map<String, dynamic>.from(event.snapshot.value as Map<String, dynamic>);
      final users = <types.User>[];
      dataMap.forEach((key, value) {
        if (firebaseUser!.uid == key) return;

        final data = Map<String, dynamic>.from(value);

        data['createdAt'] = data['createdAt']?.millisecondsSinceEpoch;
        data['id'] = key;
        data['lastSeen'] = data['lastSeen']?.millisecondsSinceEpoch;
        data['updatedAt'] = data['updatedAt']?.millisecondsSinceEpoch;

        users.add(types.User.fromJson(data));
      });

      return users;
    });
  }
}
