// (AI)
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:congress_app/services/api.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'daily_checkin_reminders';
  static const _channelName = 'Daily check-in reminders';
  static const _reminderTitle = 'A goal is due tomorrow';
  static const _reminderBody = 'Take a moment to plan your next step.';

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _initialization;
  int _nextNotificationId = DateTime.now().millisecondsSinceEpoch % 2147483647;

  Future<String?> getSupportGuidanceIfDangerous(
    Api api,
    Map<String, dynamic> processedResponse,
  ) async {
    final results = processedResponse['results'];
    if (results is! List) {
      throw const FormatException('Check-in response has no results list.');
    }

    var dangerous = false;
    for (final item in results) {
      if (item is! Map || item['classification'] is! Map) {
        throw const FormatException(
          'Check-in response has an invalid classification.',
        );
      }
      final classification = item['classification'] as Map;
      final isDangerous = classification['dangerous'];
      if (isDangerous is! bool) {
        throw const FormatException(
          'Check-in classification has no valid dangerous flag.',
        );
      }
      dangerous = dangerous || isDangerous;
    }

    if (!dangerous) return null;

    final guidanceResponse = processedResponse.containsKey('support_guidance')
        ? processedResponse
        : await api.getSupportPrompts();
    final guidance =
        guidanceResponse[processedResponse.containsKey('support_guidance')
            ? 'support_guidance'
            : 'guidance'];
    if (guidance is! String || guidance.trim().isEmpty) {
      throw const FormatException(
        'Support prompts returned no notification guidance.',
      );
    }

    return guidance.trim();
  }

  Future<bool> showSafetyNotification(String guidance) async {
    if (!_supportsSystemNotifications) return false;

    await _ensureInitialized();
    if (!await _requestPermission()) return false;

    await _plugin.show(
      id: _newNotificationId(),
      title: 'A moment for your safety',
      body: guidance,
      notificationDetails: _notificationDetails,
    );
    return true;
  }

  Future<void> showSafetyGuidanceDialog(
    BuildContext context,
    String guidance,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Support is available'),
        content: SingleChildScrollView(child: SelectableText(guidance)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Future<bool> scheduleGoalReminder({
    required int id,
    required DateTime dueDate,
  }) async {
    if (!_supportsSystemNotifications) {
      throw UnsupportedError(
        'Scheduled goal reminders are available on Android and iOS only.',
      );
    }

    final reminderDate = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day,
    ).subtract(const Duration(days: 1));
    final today = DateUtils.dateOnly(DateTime.now());
    if (reminderDate.isBefore(today)) return true;

    final scheduledLocalTime = DateTime(
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
      9,
    );

    await _ensureInitialized();
    if (!await _requestPermission()) return false;

    if (!scheduledLocalTime.isAfter(DateTime.now())) {
      await _plugin.show(
        id: id,
        title: _reminderTitle,
        body: _reminderBody,
        notificationDetails: _notificationDetails,
      );
      return true;
    }

    await _plugin.zonedSchedule(
      id: id,
      title: _reminderTitle,
      body: _reminderBody,
      scheduledDate: timezone.TZDateTime.from(
        scheduledLocalTime.toUtc(),
        timezone.local,
      ),
      notificationDetails: _notificationDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
    return true;
  }

  Future<void> cancelGoalReminder(int id) async {
    await _ensureInitialized();
    await _plugin.cancel(id: id);
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    timezone_data.initializeTimeZones();
    final initialized = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    if (initialized != true) {
      throw StateError('Could not initialize local notifications.');
    }
  }

  Future<bool> _requestPermission() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    throw UnsupportedError(
      'Notifications are currently supported on Android and iOS.',
    );
  }

  bool get _supportsSystemNotifications =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  NotificationDetails get _notificationDetails => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription:
          'Safety alerts and reminders for your daily check-in.',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  int _newNotificationId() {
    _nextNotificationId = (_nextNotificationId + 1) % 2147483647;
    return _nextNotificationId;
  }
}
