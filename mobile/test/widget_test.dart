// (USER+AI)
import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:congress_app/pages/app_shell.dart';
import 'package:congress_app/pages/home_screen.dart';
import 'package:congress_app/pages/goals_screen.dart';
import 'package:congress_app/pages/progress_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:congress_app/main.dart';
import 'package:congress_app/pages/follow.dart';
import 'package:congress_app/pages/question_screen.dart';
import 'package:congress_app/services/api.dart';
import 'package:congress_app/services/notification.dart';

void main() {
  testWidgets('follow-up screen displays the supplied questions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FollowScreen(questions: ['What would help you reach your goal?']),
      ),
    );

    expect(find.text('What would help you reach your goal?'), findsOneWidget);
    expect(find.text('Enter your response below: '), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
  });

  testWidgets('app opens and primary navigation works', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MyApp());

    expect(find.text('Welcome!'), findsOneWidget);
    expect(find.text('Your daily check-in'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.flag_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Your goals'), findsOneWidget);
  });

  testWidgets('selecting a suggested goal adds it to the tracker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final notifications = _FakeNotificationService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsScreen(
            goals: const [MapEntry('Finish a project', 3)],
            notificationService: notifications,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish a project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add selected goals'));
    await tester.pumpAndSettle();

    expect(find.text('CURRENT GOAL'), findsOneWidget);
    expect(find.text('Finish a project'), findsOneWidget);
    expect(find.textContaining('3 days left'), findsOneWidget);
    expect(find.text('Choose suggested goals'), findsNothing);
  });

  testWidgets('an active suggested goal cannot be added again', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsScreen(
            goals: const [
              MapEntry('Finish a project', 3),
              MapEntry('Take a walk', 1),
              MapEntry('Take a walk', 2),
            ],
            notificationService: _FakeNotificationService(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Finish a project'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add selected goals'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose more suggested goals'));
    await tester.pumpAndSettle();

    expect(find.text('Finish a project'), findsOneWidget);
    expect(find.text('Take a walk'), findsOneWidget);
    expect(find.text('Suggested duration: 1 days'), findsOneWidget);
    expect(find.text('Suggested duration: 2 days'), findsNothing);
  });

  testWidgets('dangerous diagnostic response shows support guidance first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'local_checkin_user_id': 'test'});
    final notifications = _FakeNotificationService();
    final api = _dangerousCheckinApi();

    await tester.pumpWidget(
      MaterialApp(
        home: QuestionScreen(api: api, notificationService: notifications),
      ),
    );
    await tester.enterText(find.byType(TextField), 'I feel unsafe.');
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(notifications.safetyGuidance, ['Support guidance from Python.']);
    expect(find.text('What will you do for fun today?'), findsOneWidget);
  });

  testWidgets(
    'dangerous check-in shows guidance in-app if notifications are unavailable',
    (tester) async {
      SharedPreferences.setMockInitialValues({'local_checkin_user_id': 'test'});
      final notifications = _FakeNotificationService()
        ..canShowSystemNotification = false;

      await tester.pumpWidget(
        MaterialApp(
          home: QuestionScreen(
            api: _dangerousCheckinApi(),
            notificationService: notifications,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'I feel unsafe.');
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Support is available'), findsOneWidget);
      expect(find.text('Support guidance from Python.'), findsOneWidget);
      expect(find.text('What deserves your attention today?'), findsOneWidget);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('What will you do for fun today?'), findsOneWidget);
    },
  );

  testWidgets('dangerous follow-up response shows support guidance first', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'local_checkin_user_id': 'test'});
    final notifications = _FakeNotificationService();

    await tester.pumpWidget(
      MaterialApp(
        home: FollowScreen(
          questions: const ['Follow-up one', 'Follow-up two'],
          api: _dangerousCheckinApi(),
          notificationService: notifications,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'I feel unsafe.');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(notifications.safetyGuidance, ['Support guidance from Python.']);
    expect(find.text('Follow-up two'), findsOneWidget);
  });

  test('non-dangerous check-ins do not query support prompts', () async {
    final api = Api(
      baseUrl: 'https://example.test/',
      client: MockClient((_) async {
        throw StateError('Support prompts should not be requested.');
      }),
    );
    final notifications = NotificationService();

    expect(
      await notifications.getSupportGuidanceIfDangerous(api, {
        'results': [
          {
            'classification': {'dangerous': false},
          },
        ],
      }),
      isNull,
    );
  });

  test('support guidance is loaded for a dangerous response', () async {
    final api = Api(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        expect(
          request.url,
          Uri.parse('https://example.test/api/checkins/support'),
        );
        return http.Response(
          jsonEncode({'guidance': 'Support guidance from Python.'}),
          200,
        );
      }),
    );

    expect(
      await NotificationService().getSupportGuidanceIfDangerous(api, {
        'results': [
          {
            'classification': {'dangerous': true},
          },
        ],
      }),
      'Support guidance from Python.',
    );
  });

  test(
    'response-provided support guidance avoids a second API lookup',
    () async {
      final api = Api(
        baseUrl: 'https://example.test/',
        client: MockClient((_) async {
          throw StateError('Inline support guidance should be used.');
        }),
      );

      expect(
        await NotificationService().getSupportGuidanceIfDangerous(api, {
          'results': [
            {
              'classification': {'dangerous': true},
            },
          ],
          'support_guidance': 'Support guidance from this check-in.',
        }),
        'Support guidance from this check-in.',
      );
    },
  );

  testWidgets('adding a goal schedules a generic reminder for its due date', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final notifications = _FakeNotificationService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsScreen(
            goals: const [MapEntry('Take a walk', 3)],
            notificationService: notifications,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a walk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add selected goals'));
    await tester.pumpAndSettle();

    expect(notifications.scheduledGoals, hasLength(1));
    expect(
      notifications.scheduledGoals.single.dueDate,
      DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 3)),
    );
  });

  testWidgets('active goals are restored after the screen is recreated', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final notifications = _FakeNotificationService();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsScreen(
            goals: const [MapEntry('Plan a walk', 4)],
            notificationService: notifications,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan a walk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add selected goals'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoalsScreen(
            goals: const [],
            notificationService: notifications,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plan a walk'), findsOneWidget);
    expect(find.textContaining('4 days left'), findsOneWidget);
  });

  testWidgets(
    'goal tracker lets the user edit the goal and extend its due date',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final notifications = _FakeNotificationService();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GoalsScreen(
              goals: const [MapEntry('Finish a project', 3)],
              notificationService: notifications,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Finish a project'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add selected goals'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit goal or add days').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextFormField).at(0),
        'Edited project',
      );
      await tester.enterText(find.byType(TextFormField).at(1), '2');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Edited project'), findsOneWidget);
      expect(find.textContaining('5 days left'), findsOneWidget);
      expect(notifications.scheduledGoals, hasLength(2));
      expect(
        notifications.scheduledGoals.last.dueDate,
        DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 5)),
      );
      expect(notifications.cancelledGoalIds, [
        notifications.scheduledGoals.first.id,
      ]);
    },
  );

  testWidgets('progress screen charts loaded emotion and danger records', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'local_checkin_user_id': 'test-user',
    });
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final api = Api(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        expect(
          request.url,
          Uri.parse('https://example.test/api/progress/history'),
        );
        expect(request.headers['X-User-ID'], 'test-user');
        return http.Response(
          jsonEncode({
            'records': [
              {
                'timestamp': timestamp,
                'timezone_offset_minutes': 0,
                'emotions': ['hopeful', 'calm'],
                'danger_level': 'none',
              },
              {
                'timestamp': timestamp,
                'timezone_offset_minutes': 0,
                'emotions': ['hopeful'],
                'danger_level': 'concerning',
              },
            ],
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(MaterialApp(home: ProgressScreen(api: api)));
    await tester.pumpAndSettle();

    expect(find.text('Weekly progress report'), findsOneWidget);
    expect(find.text('Emotion labels'), findsOneWidget);
    expect(find.text('Danger classifications'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(find.text('Weekly emotion trends'), findsOneWidget);
    expect(find.text('hopeful'), findsWidgets);
    expect(find.text('calm'), findsWidgets);
    expect(find.text('concerning'), findsOneWidget);
  });

  testWidgets('visiting the progress tab reloads behind a loading indicator', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'local_checkin_user_id': 'test-user',
    });
    var requestCount = 0;
    final secondResponse = Completer<http.Response>();
    final api = Api(
      baseUrl: 'https://example.test/',
      client: MockClient((request) async {
        requestCount++;
        if (requestCount == 2) return secondResponse.future;
        return http.Response(
          jsonEncode({
            'records': [
              {
                'timestamp': DateTime.now().toUtc().toIso8601String(),
                'timezone_offset_minutes': 0,
                'emotions': ['visit-$requestCount'],
                'danger_level': 'none',
              },
            ],
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(MaterialApp(home: AppShell(progressApi: api)));
    await tester.pumpAndSettle();
    expect(requestCount, 1);

    await tester.tap(find.byIcon(Icons.insights_outlined));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    secondResponse.complete(
      http.Response(
        jsonEncode({
          'records': [
            {
              'timestamp': DateTime.now().toUtc().toIso8601String(),
              'timezone_offset_minutes': 0,
              'emotions': ['visit-2'],
              'danger_level': 'none',
            },
          ],
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();

    expect(requestCount, 2);
    expect(find.text('visit-2'), findsWidgets);
  });

  testWidgets('daily diagnostic is disabled after completion today', (
    tester,
  ) async {
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'diagnostic_completed_date': todayKey,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(onGoalsUpdated: (_) {}, onFollowupGoalsAdded: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Completed for today'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets("today's check-in results are restored after app reload", (
    tester,
  ) async {
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'daily_checkin_results': jsonEncode({
        'date': todayKey,
        'diagnosticCompleted': true,
        'suggestions': ['Take a short break'],
        'questions': ['What would help you feel supported?'],
        'goals': [
          {'goal': 'Take a walk', 'time_span_days': 2},
        ],
        'hasTakenFollowup': false,
      }),
    });
    List<MapEntry<String, int>> restoredGoals = [];

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onGoalsUpdated: (goals) => restoredGoals = goals,
          onFollowupGoalsAdded: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Take a short break'), findsOneWidget);
    expect(find.text('Take follow-up questions'), findsOneWidget);
    expect(restoredGoals, hasLength(1));
    expect(restoredGoals.single.key, 'Take a walk');
    expect(restoredGoals.single.value, 2);
    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Completed for today'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets("completed follow-up results are also restored", (tester) async {
    final today = DateTime.now();
    final todayKey =
        '${today.year.toString().padLeft(4, '0')}-'
        '${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'daily_checkin_results': jsonEncode({
        'date': todayKey,
        'diagnosticCompleted': true,
        'suggestions': ['Take a break', 'Ask someone for support'],
        'questions': ['What would help you feel supported?'],
        'goals': [
          {'goal': 'Take a walk', 'time_span_days': 2},
          {'goal': 'Call a friend', 'time_span_days': 1},
        ],
        'hasTakenFollowup': true,
      }),
    });
    List<MapEntry<String, int>> restoredGoals = [];

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          onGoalsUpdated: (goals) => restoredGoals = goals,
          onFollowupGoalsAdded: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Take a break'), findsOneWidget);
    expect(find.text('Ask someone for support'), findsOneWidget);
    expect(find.text('Take follow-up questions'), findsNothing);
    expect(restoredGoals.map((goal) => goal.key), [
      'Take a walk',
      'Call a friend',
    ]);
  });

  testWidgets("previous day's check-in results are no longer shown", (
    tester,
  ) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year.toString().padLeft(4, '0')}-'
        '${yesterday.month.toString().padLeft(2, '0')}-'
        '${yesterday.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'daily_checkin_results': jsonEncode({
        'date': yesterdayKey,
        'diagnosticCompleted': true,
        'suggestions': ["Yesterday's suggestion"],
        'questions': ["Yesterday's question"],
        'goals': [
          {'goal': "Yesterday's goal", 'time_span_days': 2},
        ],
        'hasTakenFollowup': false,
      }),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(onGoalsUpdated: (_) {}, onFollowupGoalsAdded: (_) {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("Yesterday's suggestion"), findsNothing);
    expect(find.text('Take follow-up questions'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Take diagnostic'),
          )
          .onPressed,
      isNotNull,
    );
  });

  test('API uses the configured base URL and validates responses', () async {
    final api = Api(
      baseUrl: 'https://example.test:8080/',
      client: MockClient((request) async {
        expect(request.url, Uri.parse('https://example.test:8080/api/health'));
        return http.Response('{"status":"ok"}', 200);
      }),
    );

    expect(await api.getHealth(), {'status': 'ok'});
  });

  test('API can use a physical phone backend over Wi-Fi', () async {
    final api = Api(
      baseUrl: 'http://backend.example.test:8080',
      client: MockClient((request) async {
        expect(
          request.url,
          Uri.parse('http://backend.example.test:8080/api/health'),
        );
        return http.Response('{"status":"ok"}', 200);
      }),
    );

    expect(await api.getHealth(), {'status': 'ok'});
  });

  test(
    'check-in API sends a persistent local user ID and timezone offset',
    () async {
      SharedPreferences.setMockInitialValues({});
      String? sentUserId;
      String? sentTimezoneOffset;
      final api = Api(
        baseUrl: 'https://example.test:8080/',
        client: MockClient((request) async {
          expect(
            request.url,
            Uri.parse('https://example.test:8080/api/checkins/process'),
          );
          sentUserId = request.headers['X-User-ID'];
          sentTimezoneOffset = request.headers['X-Time-Zone-Offset-Minutes'];
          return http.Response('{"status":"ok"}', 200);
        }),
      );

      expect(await api.processCheckins('A check-in'), {'status': 'ok'});
      expect(sentUserId, isNotEmpty);
      expect(sentTimezoneOffset, isNotNull);
      expect(int.tryParse(sentTimezoneOffset!), isNotNull);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('local_checkin_user_id'), sentUserId);
    },
  );

  test(
    'API checks Java and starts Python using the configured base URL',
    () async {
      var requestIndex = 0;
      final api = Api(
        baseUrl: 'https://example.test:8080/',
        client: MockClient((request) async {
          if (requestIndex++ == 0) {
            expect(request.method, 'GET');
            expect(
              request.url,
              Uri.parse('https://example.test:8080/api/health'),
            );
            return http.Response('{"status":"ok"}', 200);
          }

          expect(request.method, 'POST');
          expect(
            request.url,
            Uri.parse('https://example.test:8080/api/ai/start'),
          );
          return http.Response('{"status":"started"}', 200);
        }),
      );

      expect(await api.startServices(), {
        'java': {'status': 'ok'},
        'python': {'status': 'started'},
      });
      expect(requestIndex, 2);
    },
  );

  test('API explains when the Java backend is unavailable', () async {
    final api = Api(
      baseUrl: 'http://127.0.0.1:8080',
      client: MockClient((_) async {
        throw http.ClientException('Connection refused');
      }),
    );

    await expectLater(
      api.startServices(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Start App.java first'),
        ),
      ),
    );
  });

  test('API rejects non-HTTP base URLs', () {
    expect(() => Api(baseUrl: 'file:///tmp/api'), throwsArgumentError);
  });

  test('API defaults to host-accessible simulator URLs', () async {
    final originalPlatform = debugDefaultTargetPlatformOverride;
    try {
      for (final testCase in [
        (TargetPlatform.android, 'http://10.0.2.2:8080/api/health'),
        (TargetPlatform.iOS, 'http://127.0.0.1:8080/api/health'),
      ]) {
        debugDefaultTargetPlatformOverride = testCase.$1;
        final api = Api.forCurrentPlatform(
          client: MockClient((request) async {
            expect(request.url, Uri.parse(testCase.$2));
            return http.Response('{"status":"ok"}', 200);
          }),
        );

        expect(await api.getHealth(), {'status': 'ok'});
      }
    } finally {
      debugDefaultTargetPlatformOverride = originalPlatform;
    }
  });
}

Api _dangerousCheckinApi() {
  return Api(
    baseUrl: 'https://example.test/',
    client: MockClient((request) async {
      switch (request.url.path) {
        case '/api/health':
          return http.Response('{"status":"ok"}', 200);
        case '/api/ai/start':
          return http.Response('{"status":"started"}', 200);
        case '/api/checkins/process':
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'question': 'A follow-up question',
                  'suggestion': 'A suggestion',
                  'classification': {'dangerous': true},
                },
              ],
              'goals': [
                {
                  'goal': {'goal': 'A goal', 'time_span_days': 2},
                },
              ],
              'support_guidance': 'Support guidance from Python.',
            }),
            200,
          );
        case '/api/checkins/support':
          return http.Response(
            jsonEncode({'guidance': 'Support guidance from Python.'}),
            200,
          );
        default:
          throw StateError('Unexpected API request: ${request.url}');
      }
    }),
  );
}

class _FakeNotificationService extends NotificationService {
  bool canShowSystemNotification = true;
  final List<String> safetyGuidance = [];
  final List<({int id, DateTime dueDate})> scheduledGoals = [];
  final List<int> cancelledGoalIds = [];

  @override
  Future<bool> showSafetyNotification(String guidance) async {
    safetyGuidance.add(guidance);
    return canShowSystemNotification;
  }

  @override
  Future<bool> scheduleGoalReminder({
    required int id,
    required DateTime dueDate,
  }) async {
    scheduledGoals.add((id: id, dueDate: dueDate));
    return true;
  }

  @override
  Future<void> cancelGoalReminder(int id) async {
    cancelledGoalIds.add(id);
  }
}
