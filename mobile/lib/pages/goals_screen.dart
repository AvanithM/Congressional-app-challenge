import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:congress_app/services/notification.dart';

const _activeGoalsKey = 'active_goal_queue';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key, required this.goals, this.notificationService});

  final List<MapEntry<String, int>> goals;
  final NotificationService? notificationService;

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  final Set<int> _selectedSuggestionIndexes = {};
  final List<_ActiveGoal> _activeGoals = [];
  bool _showSuggestionPicker = true;
  bool _isLoadingGoals = true;
  bool _isSavingGoals = false;
  String? _goalStorageError;
  late final NotificationService _notificationService =
      widget.notificationService ?? NotificationService();

  @override
  void initState() {
    super.initState();
    _loadActiveGoals();
  }

  Future<void> _loadActiveGoals() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final storedGoals = preferences.getString(_activeGoalsKey);
      final goals = storedGoals == null
          ? <_ActiveGoal>[]
          : _decodeActiveGoals(storedGoals);
      if (!mounted) return;

      setState(() {
        _activeGoals
          ..clear()
          ..addAll(goals);
        _goalStorageError = null;
        _isLoadingGoals = false;
      });
    } catch (error) {
      debugPrint('Could not load active goals: $error');
      if (!mounted) return;
      setState(() {
        _goalStorageError = error.toString();
        _isLoadingGoals = false;
      });
    }
  }

  List<_ActiveGoal> _decodeActiveGoals(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      throw const FormatException('Saved goals are not a list.');
    }

    final goals = decoded.map((item) {
      if (item is! Map ||
          item['id'] is! int ||
          item['title'] is! String ||
          (item['title'] as String).trim().isEmpty ||
          item['dueDate'] is! String) {
        throw const FormatException('Saved goal data is invalid.');
      }
      final dueDate = DateTime.tryParse(item['dueDate'] as String);
      if (dueDate == null) {
        throw const FormatException('Saved goal has an invalid due date.');
      }
      return _ActiveGoal(
        notificationId: item['id'] as int,
        title: (item['title'] as String).trim(),
        dueDate: dueDate,
      );
    }).toList();
    if (goals.map((goal) => goal.notificationId).toSet().length !=
        goals.length) {
      throw const FormatException('Saved goals contain duplicate IDs.');
    }
    return goals;
  }

  Future<void> _saveActiveGoals() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _activeGoalsKey,
      jsonEncode([
        for (final goal in _activeGoals)
          {
            'id': goal.notificationId,
            'title': goal.title,
            'dueDate': goal.dueDate.toIso8601String(),
          },
      ]),
    );
    if (!saved) {
      throw StateError('Could not save the active goal queue.');
    }
  }

  List<_ActiveGoal> get _queue {
    final queue = List<_ActiveGoal>.of(_activeGoals);
    queue.sort((first, second) => first.dueDate.compareTo(second.dueDate));
    return queue;
  }

  List<int> get _availableSuggestionIndexes {
    final activeTitles = _activeGoals
        .map((goal) => _normalizeGoalTitle(goal.title))
        .toSet();
    final seenTitles = <String>{};
    return [
      for (var index = 0; index < widget.goals.length; index++)
        if (!activeTitles.contains(
              _normalizeGoalTitle(widget.goals[index].key),
            ) &&
            seenTitles.add(_normalizeGoalTitle(widget.goals[index].key)))
          index,
    ];
  }

  Future<void> _addSelectedGoals() async {
    if (_isSavingGoals || _selectedSuggestionIndexes.isEmpty) return;

    final today = DateUtils.dateOnly(DateTime.now());
    final addedGoals = <_ActiveGoal>[];
    final activeTitles = _activeGoals
        .map((goal) => _normalizeGoalTitle(goal.title))
        .toSet();
    for (final index in _selectedSuggestionIndexes) {
      if (index >= widget.goals.length) continue;
      final suggestion = widget.goals[index];
      if (!activeTitles.add(_normalizeGoalTitle(suggestion.key))) continue;
      final goal = _ActiveGoal(
        notificationId: _newGoalNotificationId(),
        title: suggestion.key,
        dueDate: today.add(
          Duration(days: suggestion.value < 0 ? 0 : suggestion.value),
        ),
      );
      _activeGoals.add(goal);
      addedGoals.add(goal);
    }

    setState(() {
      _selectedSuggestionIndexes.clear();
      _showSuggestionPicker = false;
      _isSavingGoals = true;
    });
    try {
      await _saveActiveGoals();
    } catch (error) {
      debugPrint('Could not save active goals: $error');
      if (mounted) {
        setState(() {
          _activeGoals.removeWhere(addedGoals.contains);
          _showSuggestionPicker = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save goals: $error')));
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isSavingGoals = false;
        });
      }
    }
    for (final goal in addedGoals) {
      _scheduleReminder(goal);
    }
  }

  String _normalizeGoalTitle(String title) => title.trim().toLowerCase();

  int _newGoalNotificationId() {
    var id = DateTime.now().microsecondsSinceEpoch.remainder(2147483647);
    while (_activeGoals.any((goal) => goal.notificationId == id)) {
      id = (id + 1) % 2147483647;
    }
    return id;
  }

  Future<void> _scheduleReminder(_ActiveGoal goal) async {
    try {
      final scheduled = await _notificationService.scheduleGoalReminder(
        id: goal.notificationId,
        dueDate: goal.dueDate,
      );
      if (!scheduled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Goal reminder was not scheduled. Check notification permissions.',
            ),
          ),
        );
      }
    } catch (error) {
      debugPrint('Could not schedule goal reminder: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not schedule goal reminder: $error')),
      );
    }
  }

  Future<void> _editGoal(_ActiveGoal goal) async {
    if (_isSavingGoals) return;

    final changes = await showDialog<({String title, int additionalDays})>(
      context: context,
      builder: (_) => _GoalEditDialog(goal: goal),
    );

    if (!mounted || changes == null) return;

    final previousTitle = goal.title;
    final previousDueDate = goal.dueDate;
    setState(() {
      goal
        ..title = changes.title
        ..dueDate = goal.dueDate.add(Duration(days: changes.additionalDays));
      _isSavingGoals = true;
    });
    try {
      await _saveActiveGoals();
    } catch (error) {
      debugPrint('Could not save edited goal: $error');
      if (mounted) {
        setState(() {
          goal
            ..title = previousTitle
            ..dueDate = previousDueDate;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save edited goal: $error')),
        );
      }
      return;
    } finally {
      if (mounted) {
        setState(() {
          _isSavingGoals = false;
        });
      }
    }
    if (goal.dueDate != previousDueDate) {
      try {
        await _notificationService.cancelGoalReminder(goal.notificationId);
      } catch (error) {
        debugPrint('Could not update goal reminder: $error');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update goal reminder: $error')),
        );
        return;
      }
      await _scheduleReminder(goal);
    }
  }

  String _formatDate(DateTime date) {
    final month = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (_isLoadingGoals) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_goalStorageError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load your saved goals: $_goalStorageError'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoadingGoals = true;
                  });
                  _loadActiveGoals();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final queue = _queue;
    final currentGoal = queue.isEmpty ? null : queue.first;
    final today = DateUtils.dateOnly(DateTime.now());

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (currentGoal != null) ...[
          Card(
            color: colors.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.flag, color: colors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'CURRENT GOAL',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Edit goal or add days',
                        onPressed: _isSavingGoals
                            ? null
                            : () => _editGoal(currentGoal),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  Text(currentGoal.title, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '${currentGoal.dueDate.difference(today).inDays.clamp(0, 36500)} '
                    'days left · Due ${_formatDate(currentGoal.dueDate)}',
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (queue.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '${queue.length - 1} more goal${queue.length == 2 ? '' : 's'} in your queue',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final goal in queue.skip(1))
            Card(
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(goal.title),
                subtitle: Text(
                  '${goal.dueDate.difference(today).inDays.clamp(0, 36500)} days left · '
                  'Due ${_formatDate(goal.dueDate)}',
                ),
                trailing: IconButton(
                  tooltip: 'Edit goal or add days',
                  onPressed: _isSavingGoals ? null : () => _editGoal(goal),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ),
            ),
        ] else ...[
          Icon(Icons.flag_outlined, size: 56, color: colors.primary),
          const SizedBox(height: 8),
          Text('Your goals', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Choose suggested goals to start building your queue.'),
        ],
        if (widget.goals.isNotEmpty && _showSuggestionPicker) ...[
          const SizedBox(height: 16),
          Card(
            child: ExpansionTile(
              key: PageStorageKey<bool>(_showSuggestionPicker),
              initiallyExpanded: true,
              onExpansionChanged: (expanded) {
                setState(() {
                  _showSuggestionPicker = expanded;
                });
              },
              leading: const Icon(Icons.checklist),
              title: const Text('Choose suggested goals'),
              children: [
                for (final index in _availableSuggestionIndexes)
                  CheckboxListTile(
                    value: _selectedSuggestionIndexes.contains(index),
                    onChanged: (selected) {
                      setState(() {
                        if (selected ?? false) {
                          _selectedSuggestionIndexes.add(index);
                        } else {
                          _selectedSuggestionIndexes.remove(index);
                        }
                      });
                    },
                    title: Text(widget.goals[index].key),
                    subtitle: Text(
                      'Suggested duration: ${widget.goals[index].value} days',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          _selectedSuggestionIndexes.isEmpty || _isSavingGoals
                          ? null
                          : _addSelectedGoals,
                      child: Text(
                        _isSavingGoals
                            ? 'Saving goals...'
                            : 'Add selected goals',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (widget.goals.isNotEmpty && !_showSuggestionPicker) ...[
          TextButton.icon(
            onPressed: () {
              setState(() {
                _showSuggestionPicker = true;
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Choose more suggested goals'),
          ),
        ] else if (widget.goals.isEmpty && _activeGoals.isEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Suggested goals from your check-ins will appear here.',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

class _ActiveGoal {
  _ActiveGoal({
    required this.notificationId,
    required this.title,
    required this.dueDate,
  });

  final int notificationId;
  String title;
  DateTime dueDate;
}

class _GoalEditDialog extends StatefulWidget {
  const _GoalEditDialog({required this.goal});

  final _ActiveGoal goal;

  @override
  State<_GoalEditDialog> createState() => _GoalEditDialogState();
}

class _GoalEditDialogState extends State<_GoalEditDialog> {
  late final TextEditingController _titleController;
  final _daysController = TextEditingController(text: '0');
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.goal.title);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _daysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit goal'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Goal'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a goal.'
                  : null,
            ),
            TextFormField(
              controller: _daysController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Add days to the deadline',
              ),
              validator: (value) {
                final days = int.tryParse(value ?? '');
                return days == null || days < 0
                    ? 'Enter zero or a positive number.'
                    : null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.of(context).pop((
              title: _titleController.text.trim(),
              additionalDays: int.parse(_daysController.text),
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
