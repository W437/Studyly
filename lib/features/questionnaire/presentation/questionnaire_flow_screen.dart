import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app/navigation/routes.dart';
import '../../../ui/theme/color_tokens.dart';
import '../../../ui/theme/spacing.dart';

class QuestionnaireFlowScreen extends StatefulWidget {
  const QuestionnaireFlowScreen({super.key});

  @override
  State<QuestionnaireFlowScreen> createState() =>
      _QuestionnaireFlowScreenState();
}

class _QuestionnaireFlowScreenState extends State<QuestionnaireFlowScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 10;

  String _name = '';
  int _age = 20;
  String? _purpose;
  String? _educationLevel;
  String? _university;
  String? _degree;
  String? _subject;
  String? _year;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 20, minute: 0);
  String? _hearAbout;

  void _updatePage(int index) {
    setState(() => _currentPage = index);
  }

  void _nextPage() {
    FocusScope.of(context).unfocus();
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      // Navigate back to auth welcome screen
      context.go(AppRoute.authWelcome.path);
    }
  }

  void _finish() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PreparingScreen(
        onCompleted: () {
          if (!mounted) return;
          Navigator.of(context).pop();
          context.go(AppRoute.home.path);
        },
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _NamePage(
        name: _name,
        onNameChanged: (value) => setState(() => _name = value),
        onContinue: _nextPage,
      ),
      _AgePage(
        age: _age,
        onAgeChanged: (value) => setState(() => _age = value),
        onContinue: _nextPage,
      ),
      _OptionPage(
        title: 'What brings you here?',
        subtitle: 'Choose the reason that best describes why you\'re here.',
        selected: _purpose,
        options: const [
          _OptionItem('Improve my grades'),
          _OptionItem('Prepare for exams'),
          _OptionItem('Learn new subjects'),
          _OptionItem('Supplement my studies'),
          _OptionItem('Get organized for the semester'),
          _OptionItem('Other'),
        ],
        onSelected: (value) => setState(() => _purpose = value),
        onContinue: _nextPage,
      ),
      _OptionPage(
        title: 'Now are you in ...',
        subtitle:
            'Choose the option that best describes your current education level.',
        selected: _educationLevel,
        options: const [
          _OptionItem('School'),
          _OptionItem('College/University'),
          _OptionItem('Online Courses'),
          _OptionItem('Other'),
        ],
        onSelected: (value) => setState(() => _educationLevel = value),
        onContinue: _nextPage,
      ),
      _OptionPage(
        title: 'Select your university',
        subtitle: 'Choose the college/university you are in now.',
        selected: _university,
        header: _SearchField(hintText: 'Search'),
        options: const [
          _OptionItem('Harvard University'),
          _OptionItem('Stanford University'),
          _OptionItem('Massachusetts Institute of Technology'),
          _OptionItem('University of California, Berkeley'),
          _OptionItem('Princeton University'),
          _OptionItem('Yale University'),
        ],
        onSelected: (value) => setState(() => _university = value),
        onContinue: _nextPage,
      ),
      _OptionPage(
        title: 'Select your degree',
        subtitle: 'Select the degree program you\'re currently enrolled in.',
        selected: _degree,
        options: const [
          _OptionItem('Bachelor\'s'),
          _OptionItem('Master\'s'),
          _OptionItem('Doctoral/PhD'),
          _OptionItem('Associate\'s'),
          _OptionItem('Certificate/Diploma'),
          _OptionItem('Other'),
        ],
        onSelected: (value) => setState(() => _degree = value),
        onContinue: _nextPage,
      ),
      _OptionPage(
        title: 'Select your subject',
        subtitle: 'Choose your subject of study from the list.',
        selected: _subject,
        header: _SearchField(hintText: 'Search'),
        options: const [
          _OptionItem('Accounting'),
          _OptionItem('Biology'),
          _OptionItem('Chemistry'),
          _OptionItem('Computer Science'),
          _OptionItem('Economics'),
          _OptionItem('Engineering'),
        ],
        onSelected: (value) => setState(() => _subject = value),
        onContinue: _nextPage,
      ),
      _OptionPage(
        title: 'What year are you in?',
        subtitle: 'Let us know your current year of study.',
        selected: _year,
        options: const [
          _OptionItem('Freshman'),
          _OptionItem('Sophomore'),
          _OptionItem('Junior'),
          _OptionItem('Senior'),
          _OptionItem('Graduate'),
          _OptionItem('Other'),
        ],
        onSelected: (value) => setState(() => _year = value),
        onContinue: _nextPage,
      ),
      _ReminderPage(
        time: _reminderTime,
        onTimeChanged: (value) => setState(() => _reminderTime = value),
        onContinue: _nextPage,
      ),
      _OptionPage(
        title: 'Lastly, how did you hear\nabout Studyly?',
        subtitle: 'This helps us understand where our users come from.',
        selected: _hearAbout,
        options: const [
          _OptionItem('Social Media', leadingIcon: '📱'),
          _OptionItem(
            'Google Search',
            leadingIcon: 'G',
            leadingIconColor: Colors.red,
          ),
          _OptionItem(
            'YouTube',
            leadingIcon: '▶',
            leadingIconColor: Colors.red,
          ),
          _OptionItem(
            'App Store',
            leadingIcon: 'A',
            leadingIconColor: Colors.blue,
          ),
          _OptionItem('Friends / Family', leadingIcon: '👥'),
        ],
        onSelected: (value) => setState(() => _hearAbout = value),
        onContinue: _nextPage,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: _previousPage,
        ),
        title: Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / _totalPages,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(StudyColors.primary),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Text(
              '${_currentPage + 1} / $_totalPages',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: _updatePage,
        children: pages,
      ),
    );
  }
}

class _NamePage extends StatelessWidget {
  const _NamePage({
    required this.name,
    required this.onNameChanged,
    required this.onContinue,
  });

  final String name;
  final ValueChanged<String> onNameChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _QuestionLayout(
      title: 'What\'s your name?',
      subtitle: 'We\'d love to know what to call you.',
      onContinue: onContinue,
      isContinueEnabled: name.trim().isNotEmpty,
      crossAxisAlignment: CrossAxisAlignment.center,
      headerTextAlign: TextAlign.center,
      childAlignment: Alignment.center,
      wrapChildInScrollView: false,
      child: SizedBox(
        width: double.infinity,
        child: TextField(
          onChanged: onNameChanged,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            hintText: 'Andrew',
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}

class _AgePage extends StatelessWidget {
  const _AgePage({
    required this.age,
    required this.onAgeChanged,
    required this.onContinue,
  });

  static const int _minAge = 10;
  static const int _maxAge = 90;
  static const double _itemExtent = 70;

  final int age;
  final ValueChanged<int> onAgeChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final itemCount = _maxAge - _minAge + 1;
    final initialIndex = (age - _minAge).clamp(0, itemCount - 1);

    return _QuestionLayout(
      title: 'How old are you?',
      subtitle: 'This helps us tailor your study plan.',
      onContinue: onContinue,
      crossAxisAlignment: CrossAxisAlignment.center,
      headerTextAlign: TextAlign.center,
      wrapChildInScrollView: false,
      childAlignment: Alignment.center,
      child: SizedBox(
        height: _itemExtent * 3,
        width: 220,
        child: ListWheelScrollView.useDelegate(
          itemExtent: _itemExtent,
          diameterRatio: 1.5,
          perspective: 0.003,
          controller: FixedExtentScrollController(initialItem: initialIndex),
          onSelectedItemChanged: (index) => onAgeChanged(_minAge + index),
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: itemCount,
            builder: (context, index) {
              if (index < 0 || index >= itemCount) {
                return null;
              }

              final ageValue = _minAge + index;
              final isSelected = ageValue == age;

              return SizedBox(
                height: _itemExtent,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSelected)
                      Container(
                        height: 1,
                        width: 180,
                        color: Colors.grey.shade300,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$ageValue',
                            style: TextStyle(
                              fontSize: isSelected ? 32 : 24,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? StudyColors.primary
                                  : Colors.black54,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            const Text(
                              'years',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isSelected)
                      Container(
                        height: 1,
                        width: 180,
                        color: Colors.grey.shade300,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OptionPage extends StatelessWidget {
  const _OptionPage({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.options,
    required this.onSelected,
    required this.onContinue,
    this.header,
  });

  final String title;
  final String subtitle;
  final String? selected;
  final List<_OptionItem> options;
  final ValueChanged<String> onSelected;
  final VoidCallback onContinue;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return _QuestionLayout(
      title: title,
      subtitle: subtitle,
      onContinue: onContinue,
      isContinueEnabled: selected != null,
      child: Column(
        children: [
          if (header != null) ...[
            header!,
            const SizedBox(height: StudySpacing.lg),
          ],
          for (final option in options) ...[
            _OptionButton(
              label: option.label,
              isSelected: selected == option.label,
              onTap: () => onSelected(option.label),
              leadingIcon: option.leadingIcon,
              leadingIconColor: option.leadingIconColor,
            ),
            if (option != options.last) const SizedBox(height: StudySpacing.md),
          ],
        ],
      ),
    );
  }
}

class _ReminderPage extends StatelessWidget {
  const _ReminderPage({
    required this.time,
    required this.onTimeChanged,
    required this.onContinue,
  });

  final TimeOfDay time;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _QuestionLayout(
      title: 'Set your study reminder',
      subtitle: 'Choose a time for your daily study reminder.',
      onContinue: onContinue,
      wrapChildInScrollView: false,
      childAlignment: Alignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      headerTextAlign: TextAlign.center,
      child: SizedBox(
        height: 320,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 250,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 60,
                    child: ListWheelScrollView.useDelegate(
                      itemExtent: 50,
                      diameterRatio: 1.5,
                      perspective: 0.003,
                      controller: FixedExtentScrollController(
                        initialItem: (time.hour % 12).clamp(0, 11),
                      ),
                      onSelectedItemChanged: (index) {
                        final hour = (index + 1) % 12;
                        final adjustedHour = hour == 0 ? 12 : hour;
                        onTimeChanged(
                          TimeOfDay(
                            hour: time.period == DayPeriod.pm
                                ? (adjustedHour % 12) + 12
                                : adjustedHour % 12,
                            minute: time.minute,
                          ),
                        );
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: 12,
                        builder: (context, index) {
                          final hour = index + 1;
                          final displayHour = hour == 12 ? 12 : hour;
                          final isSelected =
                              displayHour == ((time.hour - 1) % 12) + 1;
                          return Center(
                            child: Text(
                              displayHour.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: isSelected ? 32 : 24,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? StudyColors.primary
                                    : Colors.black54,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      ':',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: ListWheelScrollView.useDelegate(
                      itemExtent: 50,
                      diameterRatio: 1.5,
                      perspective: 0.003,
                      controller: FixedExtentScrollController(
                        initialItem: time.minute,
                      ),
                      onSelectedItemChanged: (index) {
                        onTimeChanged(
                          TimeOfDay(hour: time.hour, minute: index),
                        );
                      },
                      childDelegate: ListWheelChildBuilderDelegate(
                        childCount: 60,
                        builder: (context, index) {
                          final isSelected = index == time.minute;
                          return Center(
                            child: Text(
                              index.toString().padLeft(2, '0'),
                              style: TextStyle(
                                fontSize: isSelected ? 32 : 24,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? StudyColors.primary
                                    : Colors.black54,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  DropdownButton<DayPeriod>(
                    value: time.period,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: DayPeriod.am, child: Text('AM')),
                      DropdownMenuItem(value: DayPeriod.pm, child: Text('PM')),
                    ],
                    onChanged: (period) {
                      if (period == null) return;
                      final adjustedHour = period == DayPeriod.pm
                          ? (time.hour % 12) + 12
                          : time.hour % 12;
                      onTimeChanged(
                        TimeOfDay(hour: adjustedHour, minute: time.minute),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'You can always change this later.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionLayout extends StatelessWidget {
  const _QuestionLayout({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.onContinue,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.headerTextAlign = TextAlign.left,
    this.wrapChildInScrollView = true,
    this.childAlignment = Alignment.topLeft,
    this.isContinueEnabled = true,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final VoidCallback onContinue;
  final CrossAxisAlignment crossAxisAlignment;
  final TextAlign headerTextAlign;
  final bool wrapChildInScrollView;
  final Alignment childAlignment;
  final bool isContinueEnabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Text(
            title,
            textAlign: headerTextAlign,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: headerTextAlign,
            style: const TextStyle(
              fontSize: 15,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: Align(
              alignment: childAlignment,
              child: wrapChildInScrollView
                  ? SingleChildScrollView(child: child)
                  : child,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: isContinueEnabled ? onContinue : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: StudyColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  const _OptionButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.leadingIcon,
    this.leadingIconColor,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final String? leadingIcon;
  final Color? leadingIconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: StudySpacing.md,
          vertical: StudySpacing.lg,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? StudyColors.primary : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? StudyColors.primary.withOpacity(0.08)
              : Colors.white,
        ),
        child: Row(
          children: [
            if (leadingIcon != null)
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color:
                      leadingIconColor?.withOpacity(0.15) ??
                      Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: StudySpacing.md),
                child: Text(
                  leadingIcon!,
                  style: TextStyle(
                    fontSize: 16,
                    color: leadingIconColor ?? Colors.black87,
                  ),
                ),
              ),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? StudyColors.primary : Colors.black87,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check, color: StudyColors.primary, size: 24),
          ],
        ),
      ),
    );
  }
}

class _OptionItem {
  const _OptionItem(this.label, {this.leadingIcon, this.leadingIconColor});

  final String label;
  final String? leadingIcon;
  final Color? leadingIconColor;
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.hintText});

  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }
}

class PreparingScreen extends StatefulWidget {
  const PreparingScreen({super.key, required this.onCompleted});

  final VoidCallback onCompleted;

  @override
  State<PreparingScreen> createState() => _PreparingScreenState();
}

class _PreparingScreenState extends State<PreparingScreen> {
  static const Duration _tickInterval = Duration(milliseconds: 60);
  static const Duration _targetDuration = Duration(seconds: 5);

  final Random _random = Random();
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  int _percent = 1;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_tickInterval, _handleTick);
  }

  void _handleTick(Timer timer) {
    if (!mounted) {
      timer.cancel();
      return;
    }

    setState(() {
      _elapsed += _tickInterval;
      final remaining = 100 - _percent;

      if (remaining <= 0 || _elapsed >= _targetDuration) {
        _percent = 100;
      } else {
        final step = (remaining > 1 && _random.nextDouble() < 0.35) ? 2 : 1;
        _percent = min(100, _percent + step);
      }

      HapticFeedback.selectionClick();
    });

    if (_percent >= 100) {
      _timer?.cancel();
      Future.microtask(widget.onCompleted);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Preparing a personalized\npage for you...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Please wait...',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 120,
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 120,
                    child: CircularProgressIndicator(
                      strokeWidth: 8,
                      value: _percent / 100,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation(
                        StudyColors.primary,
                      ),
                    ),
                  ),
                  Text(
                    '$_percent%',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            const Text(
              'This might take a few moments. Get ready for an amazing study experience!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
