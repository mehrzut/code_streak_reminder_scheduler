import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart';
import 'package:starter_template/core/response_model.dart';

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
  final trigger = context.req.headers['x-appwrite-trigger'] ?? '';
  context.log('trigger: $trigger');

  if (context.req.method == 'POST' &&
      context.req.body != null &&
      context.req.path == "/setRemindersForNewSession") {
    return await handleRemindersOnNewSession(context, users, messaging);
  } else if (trigger == 'schedule') {
    return await _scheduleUsersDailyReminders(context, users, messaging);
  }
}

Future<dynamic> _scheduleUsersDailyReminders(
    context, Users users, Messaging messaging) async {
  try {
    context.log('load all users');
    final UserList userList = await users.list();
    context.log('fetched users!');
    context.log('users: ${jsonEncode(userList.users.map(
          (e) => e.toMap(),
        ).toList())}');
    for (User user in userList.users) {
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
        final userPushTargets = user.targets
            .where((element) => element.providerType == "push")
            .toList();
        context.log('user push targets: ${jsonEncode(userPushTargets.map(
              (e) => e.toMap(),
            ).toList())}');
        try {
          final result = await messaging.createPush(
            messageId: messageId,
            title: 'Time to Code! 🚀',
            body:
                "Hey there! 🌟 It's 9 PM—have you coded or contributed to your GitHub today? Even a small commit can make a big difference. Keep the streak alive and let your ideas shine! 💻✨",
            scheduledAt: next9PMUtc
                .subtract(Duration(
                    minutes:
                        30)) // the 30-min subtraction is due to a bug on appwrite which delays the notification by 30 minutes
                .toIso8601String(),
            targets: userPushTargets
                .map(
                  (e) => e.$id,
                )
                .toList(),
          );
          context.log('scheduled push notification!: $result');
        } catch (e) {
          context.log(e.toString());
        }
      }
    }
    return context.res.text('Task completed!');
  } catch (e) {
    context.log(e.toString());
    return context.res.text(e.toString());
  }
}

// message id containing user id and date (only year, month, day)
String _generateMessageId(User user, DateTime next9PMUtc) =>
    '${user.$id}-${next9PMUtc.year}-${next9PMUtc.month}-${next9PMUtc.day}';

dynamic handleRemindersOnNewSession(
    context, Users users, Messaging messaging) async {
  final userId = context.req.bodyJson['userId'];
  if (userId == null || userId.isEmpty) {
    return context.res.text('userId is empty', 400);
  }
  late User user;
  try {
    user = await users.get(userId: userId);
  } on Exception catch (e) {
    return context.res.text(e.toString(), 400);
  }
  final result = await setRemindersForUser(context, user, messaging);
  return result.when(
    success: (_) {
      return context.res.text('success', 200);
    },
    failed: (exception) {
      return context.res.text(exception.toString(), 400);
    },
  );
}

Future<ResponseModel> setRemindersForUser(
    context, User user, Messaging messaging) async {
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
    late Function(
        {required String messageId,
        required String title,
        required String body,
        List<String>? topics,
        List<String>? users,
        List<String>? targets,
        Map? data,
        String? action,
        String? image,
        String? icon,
        String? sound,
        String? color,
        String? tag,
        bool? draft,
        String? scheduledAt}) scheduler;
    try {
      context.log('check existing message');
      // update if message already scheduled
      await messaging.getMessage(messageId: messageId);
      // no error thrown means message exists
      scheduler = messaging.updatePush;
      context.log('found existing message');
    } catch (e) {
      // create if message not scheduled
      context.log('no existing message found');
      scheduler = messaging.createPush;
      context.log('should create new message');
      context.log(e.toString());
    }
    // Schedule push notification
    context.log('scheduling push notification');
    final userPushTargets = user.targets
        .where((element) => element.providerType == "push")
        .toList();
    context.log('user push targets: ${jsonEncode(userPushTargets.map(
          (e) => e.toMap(),
        ).toList())}');
    try {
      final result = await scheduler(
        messageId: messageId,
        title: 'Time to Code! 🚀',
        body:
            "Hey there! 🌟 It's 9 PM—have you coded or contributed to your GitHub today? Even a small commit can make a big difference. Keep the streak alive and let your ideas shine! 💻✨",
        scheduledAt: next9PMUtc
            .subtract(Duration(
                minutes:
                    30)) // the 30-min subtraction is due to a bug on appwrite which delays the notification by 30 minutes
            .toIso8601String(),
        targets: userPushTargets
            .map(
              (e) => e.$id,
            )
            .toList(),
      );
      context
          .log('scheduled push notification!: $messageId - ${result.toMap()}');
      return ResponseModel.success(null);
    } catch (e) {
      context.log(e.toString());
      return ResponseModel.failed(message: e.toString());
    }
  }
  return ResponseModel.failed(message: 'Timezone offset not found');
}
