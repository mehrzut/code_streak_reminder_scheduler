import 'dart:async';
import 'dart:io';
import 'package:dart_appwrite/dart_appwrite.dart';

// This Appwrite function will be executed every time your function is triggered
Future<dynamic> main(final context) async {
  // You can use the Appwrite SDK to interact with other services
  // For this example, we're using the Users service
  final client = Client()
      .setEndpoint(Platform.environment['APPWRITE_FUNCTION_API_ENDPOINT'] ?? '')
      .setProject(Platform.environment['APPWRITE_FUNCTION_PROJECT_ID'] ?? '')
      .setKey(context.req.headers['x-appwrite-key'] ?? '');
  final users = Users(client);
  Messaging messaging = Messaging(client);
  final userList = await users.list();
  for (var user in userList.users) {
    // Retrieve user's timezone offset
    final prefs = await users.getPrefs(userId: user.$id);
    final timezoneOffset = prefs.data['timezone'];

    if (timezoneOffset != null) {
      // Parse timezone offset
      final offset = int.parse(timezoneOffset.split(':')[0]);

      // Calculate next 9 PM in user's local time
      final now = DateTime.now().toUtc();
      final userTime = now.add(Duration(hours: offset));
      DateTime next9PM =
          DateTime(userTime.year, userTime.month, userTime.day, 21);
      if (userTime.isAfter(next9PM)) {
        next9PM = next9PM.add(Duration(days: 1));
      }

      // Convert next9PM to UTC
      final next9PMUtc = next9PM.subtract(Duration(hours: offset));

      // Schedule push notification
      await messaging.createPush(
        messageId: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Time to Code! 🚀',
        body:
            "Hey there! 🌟 It's 9 PM—have you coded or contributed to your GitHub today? Even a small commit can make a big difference. Keep the streak alive and let your ideas shine! 💻✨",
        scheduledAt: next9PMUtc.toIso8601String(),
        users: [user.$id],
      );
    }
  }
}
