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
  final messaging = Messaging(client);
  context.log('creating users instance');
  final userList = await users.list();
  context.log('fetched users!');

  try {
    for (var user in userList.users) {
      context.log('processing user ${user.name}');
      // Retrieve user's timezone offset
      final timezoneOffset = user.prefs.data['timezone'];

      if (timezoneOffset != null) {
        context.log('retrieved timezone offset: $timezoneOffset');
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
        context.log('scheduling push notification');

        /// TODO: add logic to cancel if push notification is already scheduled
        await messaging.createPush(
          // message id containing user id and date (only year, month, day)
          messageId:
              '${user.$id}-${next9PMUtc.year}-${next9PMUtc.month}-${next9PMUtc.day}',
          title: 'Time to Code! 🚀',
          body:
              "Hey there! 🌟 It's 9 PM—have you coded or contributed to your GitHub today? Even a small commit can make a big difference. Keep the streak alive and let your ideas shine! 💻✨",
          scheduledAt: next9PMUtc.toIso8601String(),
          users: [user.$id],
        );
        context.log('scheduled push notification!');
      }
    }
    return context.res.text('Task completed!');
  } catch (e) {
    return context.res.text(e.toString());
  }
}
