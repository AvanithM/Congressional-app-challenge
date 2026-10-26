// (USER+AI)
import 'package:flutter/material.dart';
import 'package:congress_app/services/api.dart';
import 'package:congress_app/services/notification.dart';

class FollowScreen extends StatefulWidget {
  const FollowScreen({
    super.key,
    required this.questions,
    this.api,
    this.notificationService,
  });

  final List<String> questions;
  final Api? api;
  final NotificationService? notificationService;

  @override
  State<FollowScreen> createState() => FollowScreenState();
}

class FollowScreenState extends State<FollowScreen> {
  final resControl = TextEditingController();
  final List<MapEntry<String, int>> goals = [];
  final List<String> suggestions = [];
  int qind = 0;
  bool isSubmitting = false;

  @override
  void dispose() {
    resControl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api ?? Api.forCurrentPlatform();
    final notificationService =
        widget.notificationService ?? NotificationService();
    final colors = Theme.of(context).colorScheme;

    if (widget.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Follow-up Questions')),
        body: const Center(
          child: Text('No follow-up questions are available.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Follow-up Questions')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Card(
            color: colors.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.question_answer, size: 36),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, animation) {
                      final slideAnimation = Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(animation);
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: slideAnimation,
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      widget.questions[qind],
                      key: ValueKey(qind),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Enter your response below: '),
                  const SizedBox(height: 8),
                  TextField(
                    autocorrect: true,
                    controller: resControl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Type your response...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final response = resControl.text.trim();
                            setState(() {
                              isSubmitting = true;
                            });
                            try {
                              await api.startServices();
                              final result = await api.processCheckins(
                                response,
                              );

                              final results =
                                  result['results'] as List<dynamic>;
                              if (results.isEmpty) {
                                throw const FormatException(
                                  'No results were returned.',
                                );
                              }
                              final firstResult =
                                  results[0] as Map<String, dynamic>;

                              String? supportGuidance;
                              try {
                                supportGuidance = await notificationService
                                    .getSupportGuidanceIfDangerous(api, result);
                              } catch (error) {
                                debugPrint(
                                  'Could not load dangerous check-in support '
                                  'guidance: $error',
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Your response was processed, but '
                                        'support guidance could not be loaded: '
                                        '$error',
                                      ),
                                    ),
                                  );
                                }
                              }
                              if (supportGuidance != null && context.mounted) {
                                var shown = false;
                                try {
                                  shown = await notificationService
                                      .showSafetyNotification(supportGuidance);
                                } catch (error) {
                                  debugPrint(
                                    'Could not send dangerous check-in '
                                    'notification: $error',
                                  );
                                }
                                if (!shown && context.mounted) {
                                  await notificationService
                                      .showSafetyGuidanceDialog(
                                        context,
                                        supportGuidance,
                                      );
                                }
                              }

                              final goalResults =
                                  result['goals'] as List<dynamic>;
                              if (goalResults.isEmpty) {
                                throw const FormatException(
                                  'No goals were returned.',
                                );
                              }
                              final firstGoalEntry =
                                  goalResults[0] as Map<String, dynamic>;
                              final goalDetails =
                                  firstGoalEntry['goal']
                                      as Map<String, dynamic>;

                              final suggestionText =
                                  firstResult['suggestion'] as String;
                              final goalText = goalDetails['goal'] as String;
                              final goalDurationDays =
                                  goalDetails['time_span_days'] as int;

                              suggestions.add(suggestionText);
                              goals.add(MapEntry(goalText, goalDurationDays));

                              if (!context.mounted) return;
                              if (qind == widget.questions.length - 1) {
                                Navigator.of(context).pop({
                                  'goals': List<MapEntry<String, int>>.of(
                                    goals,
                                  ),
                                  'suggestions': List<String>.of(suggestions),
                                });
                              } else {
                                setState(() {
                                  qind++;
                                  resControl.clear();
                                });
                              }
                            } catch (error) {
                              debugPrint('API request failed: $error');
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not submit follow-up: $error',
                                  ),
                                ),
                              );
                            } finally {
                              if (mounted) {
                                setState(() {
                                  isSubmitting = false;
                                });
                              }
                            }
                          },
                    child: const Text('Submit'),
                  ),
                ],
              ),
            ),
          ),
          if (isSubmitting)
            Positioned.fill(
              child: ColoredBox(
                color: colors.scrim.withAlpha(110),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            'Processing your response...',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
