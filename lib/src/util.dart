import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;

extension RoleToShortString on types.Role {
  String toShortString() => toString().split('.').last;
}

extension RoomTypeToShortString on types.RoomType {
  String toShortString() => toString().split('.').last;
}

Future<Map<String, dynamic>> fetchUser(
  DatabaseReference instance,
  String userId,
  String usersPathName, {
  String? role,
}) async {
  final dbEvent = await instance.child('$usersPathName/$userId').once();

  final data = Map<String, dynamic>.from(dbEvent.snapshot.value as Map);

  data['id'] = dbEvent.snapshot.key;
  data['role'] = role;

  return data;
}

Future<List<types.Room>> processRoomsData(
  List<Map<String, dynamic>> roomsData,
  User firebaseUser,
  DatabaseReference instance,
  String usersPathName,
) async {
  final futures = roomsData.map(
    (roomData) => processRoomData(
      roomData,
      firebaseUser,
      instance,
      usersPathName,
    ),
  );

  return await Future.wait(futures);
}

Future<types.Room> processRoomData(
  Map<String, dynamic> roomData,
  User firebaseUser,
  DatabaseReference instance,
  String usersPathName,
) async {
  roomData['createdAt'] = roomData['createdAt']?.millisecondsSinceEpoch;
  roomData['updatedAt'] = roomData['updatedAt']?.millisecondsSinceEpoch;

  var imageUrl = roomData['imageUrl'] as String?;
  var name = roomData['name'] as String?;
  final type = roomData['type'] as String;
  final userIds = roomData['userIds'] as List<dynamic>;
  final userRoles = roomData['userRoles'] as Map<String, dynamic>?;

  final users = await Future.wait(
    userIds.map(
      (userId) => fetchUser(
        instance,
        userId as String,
        usersPathName,
        role: userRoles?[userId] as String?,
      ),
    ),
  );

  if (type == types.RoomType.direct.toShortString()) {
    try {
      final otherUser = users.firstWhere(
        (u) => u['id'] != firebaseUser.uid,
      );

      imageUrl = otherUser['imageUrl'] as String?;
      name = '${otherUser['firstName'] ?? ''} ${otherUser['lastName'] ?? ''}'
          .trim();
    } catch (e) {
      // Do nothing if other user is not found, because he should be found.
      // Consider falling back to some default values.
    }
  }

  roomData['imageUrl'] = imageUrl;
  roomData['name'] = name;
  roomData['users'] = users;

  if (roomData['lastMessages'] != null) {
    final lastMessages = (roomData['lastMessages'] as List).map((lm) {
      final author = users.firstWhere(
        (u) => u['id'] == lm['authorId'],
        orElse: () => {'id': lm['authorId'] as String},
      );

      lm['author'] = author;
      lm['createdAt'] = lm['createdAt']?.millisecondsSinceEpoch;
      lm['id'] = lm['id'] ?? '';
      lm['updatedAt'] = lm['updatedAt']?.millisecondsSinceEpoch;

      return lm;
    }).toList();

    roomData['lastMessages'] = lastMessages;
  }

  return types.Room.fromJson(roomData);
}
