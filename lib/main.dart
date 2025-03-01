import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dart_appwrite/dart_appwrite.dart';
import 'package:dart_appwrite/models.dart';
import 'package:starter_template/core/extensions.dart';
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
          (e) => e.toMap().toString(),
        ).toList())}');
    for (User user in userList.users) {
      try {
        await setRemindersForUser(context, user, messaging);
      } catch (e) {
        context.log('error setting reminders for user ${user.$id}: $e');
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
  return context.res.text('success', 200); // TODO: for testing, remove this later and use the code below
  // final userId = context.req.bodyJson['userId'];
  // if (userId == null || userId.isEmpty) {
  //   return context.res.text('userId is empty', 400);
  // }
  // late User user;
  // try {
  //   user = await users.get(userId: userId);
  // } on Exception catch (e) {
  //   return context.res.text(e.toString(), 400);
  // }
  // final result = await setRemindersForUser(context, user, messaging);
  // return result.when(
  //   success: (_) {
  //     return context.res.text('success', 200);
  //   },
  //   failed: (exception) {
  //     return context.res.text(exception.toString(), 400);
  //   },
  // );
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
    final next9PMUtc = next9PM.subtract(offsetDuration);

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
      final content = dynamicNotifications.random;
      final result = await scheduler(
        messageId: messageId,
        title: content.$1,
        body: content.$2,
        scheduledAt: next9PMUtc.toIso8601String(),
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

List<(String, String)> dynamicNotifications = [
  (
    'Keep the Momentum Going! 🚀',
    "It's 9 PM! Remember, 'Programming isn't about what you know; it's about what you can figure out.' Keep pushing your code to GitHub! 💻"
  ),
  (
    'Your Code Can Change the World! 🌍',
    "Hey! 'You might not think that programmers are artists, but programming is an extremely creative profession.' Share your creativity on GitHub tonight! 🎨"
  ),
  (
    'Consistency is Key! 🔑',
    "9 PM check-in: 'First, solve the problem. Then, write the code.' Keep your GitHub updated with your latest solutions! 🛠️"
  ),
  (
    'Illuminate Your Path with Code! 💡',
    "Remember, 'Code is like humor. When you have to explain it, it’s bad.' Keep your GitHub shining with clear and concise commits! ✨"
  ),
  (
    'Build Your Legacy, One Commit at a Time! 🏗️',
    "It's 9 PM! 'Make it work, make it right, make it fast.' Ensure your progress is reflected on GitHub! 🚀"
  ),
  (
    'Your Future Self Will Thank You! 🙌',
    "Hey there! 'Clean code always looks like it was written by someone who cares.' Show you care by pushing your latest code to GitHub! 💻"
  ),
  (
    'Every Line of Code Counts! 📈',
    "9 PM reminder: 'Programming is the art of algorithm design and the craft of debugging errant code.' Share your art on GitHub tonight! 🎨"
  ),
  (
    'Stay Ahead, Stay Committed! 🏃‍♂️',
    "Remember, 'Any fool can write code that a computer can understand. Good programmers write code that humans can understand.' Keep your GitHub updated with human-friendly code! 🤖"
  ),
  (
    'Your Code is Your Signature! ✍️',
    "It's 9 PM! 'Experience is the name everyone gives to their mistakes.' Document your journey on GitHub with your latest commits! 📜"
  ),
  (
    'Innovate, Iterate, Inspire! 🌟',
    "Hey! 'Confusion is part of programming.' Embrace it and push your latest breakthroughs to GitHub! 🚀"
  ),
  (
    'Transform Ideas into Reality! 🛠️',
    "9 PM check-in: 'Everybody should learn to program a computer because it teaches you how to think.' Reflect your thoughts on GitHub tonight! 💡"
  ),
  (
    'Your Code Tells Your Story! 📖',
    "Remember, 'Most good programmers do programming not because they expect to get paid or get adulation by the public, but because it is fun to program.' Share your fun on GitHub! 🎉"
  ),
  (
    'Push Beyond Boundaries! 🚀',
    "It's 9 PM! 'When I wrote this code, only God and I understood what I did. Now only God knows.' Keep your GitHub updated with your latest mysteries! 🕵️‍♂️"
  ),
  (
    'Evolve Through Code! 🦋',
    "Hey there! 'I’m not a great programmer; I’m just a good programmer with great habits.' One of those habits? Regular GitHub commits! 🛠️"
  ),
  (
    'Your Code is a Work of Art! 🎨',
    "9 PM reminder: 'Programming is learned by writing programs.' Showcase your learning journey on GitHub tonight! 📚"
  ),
  (
    'Stay Driven, Stay Coding! 🏎️',
    "Remember, 'There is always one more bug to fix.' Keep squashing them and push your fixes to GitHub! 🐛"
  ),
  (
    'Your Efforts Make a Difference! 🌍',
    "It's 9 PM! 'Talk is cheap. Show me the code.' Let your GitHub reflect your hard work! 💪"
  ),
  (
    'Persevere and Code On! 🛤️',
    "Hey! 'Sometimes it pays to stay in bed on Monday, rather than spending the rest of the week debugging Monday’s code.' But tonight, let's push that code to GitHub! 🛌"
  ),
  (
    'Keep Building, Keep Sharing! 🏗️',
    "Remember, 'If debugging is the process of removing bugs, then programming must be the process of putting them in.' Embrace the process and update your GitHub! 🐞"
  ),
];
