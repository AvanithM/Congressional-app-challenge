import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:congress_app/pages/follow.dart';
import 'package:congress_app/pages/question_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:congress_app/services/notification.dart';

const _diagnosticDateKey = 'diagnostic_completed_date';
const _dailyResultsKey = 'daily_checkin_results';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onGoalsUpdated,
    required this.onFollowupGoalsAdded,
    this.notificationService,
  });

  final ValueChanged<List<MapEntry<String, int>>> onGoalsUpdated;
  final ValueChanged<List<MapEntry<String, int>>> onFollowupGoalsAdded;
  final NotificationService? notificationService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<String> _suggestions = [];
  final List<String> _followupQuestions = [];
  final List<MapEntry<String, int>> _goalSuggestions = [];
  bool _hasTakenFollowup = false;
  bool _isLoadingDiagnosticStatus = true;
  bool _hasCompletedDiagnosticToday = false;
  bool _isStartingDiagnostic = false;
  String? _diagnosticStatusError;

  @override
  void initState() {
    super.initState();
    _loadDiagnosticStatus();
  }

  String get _todayKey {
    final today = DateTime.now();
    final year = today.year.toString().padLeft(4, '0');
    final month = today.month.toString().padLeft(2, '0');
    final day = today.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  Future<void> _loadDiagnosticStatus() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedResults = preferences.getString(_dailyResultsKey);
      var hasCompletedToday =
          preferences.getString(_diagnosticDateKey) == _todayKey;
      var restoredGoals = <MapEntry<String, int>>[];

      if (savedResults != null) {
        final decoded = jsonDecode(savedResults);
        if (decoded is! Map<String, dynamic> || decoded['date'] is! String) {
          throw const FormatException('Saved daily check-in is invalid.');
        }

        if (decoded['date'] == _todayKey) {
          final suggestions = _readStringList(decoded['suggestions']);
          final questions = _readStringList(decoded['questions']);
          final goals = _readGoalList(decoded['goals']);
          final hasTakenFollowup = decoded['hasTakenFollowup'];
          if (hasTakenFollowup is! bool ||
              decoded['diagnosticCompleted'] is! bool) {
            throw const FormatException('Saved daily check-in is invalid.');
          }

          _suggestions.addAll(suggestions);
          _followupQuestions.addAll(questions);
          _goalSuggestions.addAll(goals);
          _hasTakenFollowup = hasTakenFollowup;
          restoredGoals = goals;
          hasCompletedToday = decoded['diagnosticCompleted'] as bool;
        }
      }

      if (!mounted) return;

      setState(() {
        _hasCompletedDiagnosticToday = hasCompletedToday;
        _isLoadingDiagnosticStatus = false;
      });
      if (restoredGoals.isNotEmpty) {
        widget.onGoalsUpdated(restoredGoals);
      }
    } catch (error) {
      debugPrint('Could not check daily diagnostic status: $error');
      if (!mounted) return;

      setState(() {
        _diagnosticStatusError = error.toString();
        _isLoadingDiagnosticStatus = false;
      });
    }
  }

  List<String> _readStringList(Object? value) {
    if (value is! List || value.any((item) => item is! String)) {
      throw const FormatException('Saved daily check-in is invalid.');
    }
    return value.cast<String>();
  }

  List<MapEntry<String, int>> _readGoalList(Object? value) {
    if (value is! List) {
      throw const FormatException('Saved daily check-in is invalid.');
    }

    return value.map((item) {
      if (item is! Map ||
          item['goal'] is! String ||
          item['time_span_days'] is! int) {
        throw const FormatException('Saved daily check-in is invalid.');
      }
      return MapEntry(item['goal'] as String, item['time_span_days'] as int);
    }).toList();
  }

  Future<void> _saveDailyResults() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _dailyResultsKey,
      jsonEncode({
        'date': _todayKey,
        'diagnosticCompleted': _hasCompletedDiagnosticToday,
        'suggestions': _suggestions,
        'questions': _followupQuestions,
        'goals': [
          for (final goal in _goalSuggestions)
            {'goal': goal.key, 'time_span_days': goal.value},
        ],
        'hasTakenFollowup': _hasTakenFollowup,
      }),
    );
    if (!saved) {
      throw StateError('Could not save today\'s check-in results.');
    }
  }

  Future<void> _startDiagnostic() async {
    if (_isStartingDiagnostic ||
        _isLoadingDiagnosticStatus ||
        _hasCompletedDiagnosticToday ||
        _diagnosticStatusError != null) {
      return;
    }

    setState(() {
      _isStartingDiagnostic = true;
    });

    try {
      final diagnostic = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute<Map<String, dynamic>>(
          builder: (context) =>
              QuestionScreen(notificationService: widget.notificationService),
        ),
      );
      if (!mounted || diagnostic == null) return;

      setState(() {
        _suggestions
          ..clear()
          ..addAll(diagnostic['suggestions'] as List<String>);
        _followupQuestions
          ..clear()
          ..addAll(diagnostic['questions'] as List<String>);
        _goalSuggestions
          ..clear()
          ..addAll(diagnostic['goals'] as List<MapEntry<String, int>>);
        _hasTakenFollowup = false;
        _hasCompletedDiagnosticToday = true;
      });
      widget.onGoalsUpdated(List.of(_goalSuggestions));

      try {
        await _saveDailyResults();
      } catch (error) {
        debugPrint('Could not save daily check-in results: $error');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save today\'s check-in results: $error'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStartingDiagnostic = false;
        });
      }
    }
  }

  Future<void> _takeFollowup() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (context) => FollowScreen(
          questions: List<String>.of(_followupQuestions),
          notificationService: widget.notificationService,
        ),
      ),
    );
    if (!mounted || result == null) return;

    setState(() {
      _hasTakenFollowup = true;
      _suggestions.addAll(result['suggestions'] as List<String>);
      _goalSuggestions.addAll(result['goals'] as List<MapEntry<String, int>>);
    });
    widget.onFollowupGoalsAdded(result['goals'] as List<MapEntry<String, int>>);
    try {
      await _saveDailyResults();
    } catch (error) {
      debugPrint('Could not save daily check-in results: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save today\'s check-in results: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Welcome!', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Take a moment to check in with yourself.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 24),
        Card(
          color: colors.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.wb_sunny_outlined, size: 36, color: colors.primary),
                const SizedBox(height: 16),
                Text(
                  'Your daily check-in',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Answer a few questions about today to get helpful '
                  'suggestions and goals.',
                ),
                ElevatedButton(
                  onPressed:
                      _isLoadingDiagnosticStatus ||
                          _hasCompletedDiagnosticToday ||
                          _isStartingDiagnostic ||
                          _diagnosticStatusError != null
                      ? null
                      : _startDiagnostic,
                  child: Text(
                    _isLoadingDiagnosticStatus
                        ? 'Checking today\'s status...'
                        : _hasCompletedDiagnosticToday
                        ? 'Completed for today'
                        : _isStartingDiagnostic
                        ? 'Starting diagnostic...'
                        : 'Take diagnostic',
                  ),
                ),
                if (_diagnosticStatusError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Could not verify whether today\'s diagnostic is '
                      'already completed. Restart the app and try again. '
                      'Details: $_diagnosticStatusError',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Suggestions', style: Theme.of(context).textTheme.titleLarge),
          for (final suggestion in _suggestions)
            Card(
              child: ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(suggestion),
              ),
            ),
        ],
        if (_followupQuestions.isNotEmpty && !_hasTakenFollowup) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Would you like to take your follow-up questions?',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _takeFollowup,
                    child: const Text('Take follow-up questions'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
