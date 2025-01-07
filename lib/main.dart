import 'dart:async';
import 'dart:io';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart';

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
        context.log('Original timezone offset: $timezoneOffset');
        final isOffsetNegative = timezoneOffset.startsWith('-');
        final pureOffsetDuration =
            timezoneOffset.replaceAll('-', '').split('.').first;
        context.log('Pure offset duration: $pureOffsetDuration');
        final offsetHour = int.parse(pureOffsetDuration.split(':')[0]);
        final offsetMin = int.parse(pureOffsetDuration.split(':')[1]);
        final offsetSec = int.parse(pureOffsetDuration.split(':')[2]);
        final offsetDuration = Duration(
          hours: offsetHour,
          minutes: offsetMin,
          seconds: offsetSec,
        );
        context.log('Offset duration: $offsetDuration');

        // Calculate next 9 PM in user's local time
        final now = DateTime.now().toUtc();
        context.log('Current UTC time: $now');
        final userTime = isOffsetNegative
            ? now.subtract(offsetDuration)
            : now.add(offsetDuration);
        context.log('Current user time: $userTime');
        DateTime next9PM =
            DateTime(userTime.year, userTime.month, userTime.day, 21);
        if (userTime.isAfter(next9PM)) {
          next9PM = next9PM.add(Duration(days: 1));
        }
        context.log('Next 9 PM user time: $next9PM');

        // Convert next9PM to UTC
        final next9PMUtc = next9PM.subtract(Duration(hours: offsetHour));

        final messageId = _generateMessageId(user, next9PMUtc);
        try {
          context.log('deleting existing message');
          // cancel if message already scheduled
          await messaging.delete(messageId: messageId);
          context.log('deleted existing message');
        } catch (e) {
          context.log(e.toString());
        }
        // Schedule push notification
        context.log('scheduling push notification');
        await messaging.createPush(
          messageId: messageId,
          title: 'Time to Code! 🚀',
          body:
              "Hey there! 🌟 It's 9 PM—have you coded or contributed to your GitHub today? Even a small commit can make a big difference. Keep the streak alive and let your ideas shine! 💻✨",
          scheduledAt: next9PMUtc
              .subtract(Duration(
                  minutes:
                      30)) // the 30-min subtraction is due to a bug on appwrite which delays the notification by 30 minutes
              .toIso8601String(),
          targets: user.targets
              .map(
                (e) => e.identifier,
              )
              .toList(),
        );
        context.log('scheduled push notification!');
      }
    }
    return context.res.text('Task completed!');
  } catch (e) {
    return context.res.text(e.toString());
  }
}

// message id containing user id and date (only year, month, day)
String _generateMessageId(User user, DateTime next9PMUtc) =>
    '${user.$id}-${next9PMUtc.year}-${next9PMUtc.month}-${next9PMUtc.day}';
