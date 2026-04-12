import 'dart:math';

import 'task_templates.dart';

/// A single generated task shown to the child.
class GeneratedTask {
  final TaskType type;
  final String instruction;
  final List<String> options; // emoji or text labels
  final int correctIndex;
  final int displayDurationMs; // for memory: how long sequence was shown
  final String? sequenceDisplay; // for memory: "🐶 → 🐱 → 🐰"
  // New fields for new domains
  final String? stroopWord; // for Stroop
  final String? stroopColor; // for Stroop
  final int? nBackLevel; // for N-back
  final int? reactionDelayMs; // for Reaction Time

  const GeneratedTask({
    required this.type,
    required this.instruction,
    required this.options,
    required this.correctIndex,
    this.displayDurationMs = 4000,
    this.sequenceDisplay,
    this.stroopWord,
    this.stroopColor,
    this.nBackLevel,
    this.reactionDelayMs,
  });
}

/// One recorded trial for behavioral analysis.
class TrialRecord {
  final TaskType taskType;
  final bool correct;
  final int responseTimeMs;
  final int difficultyIndex;

  const TrialRecord({
    required this.taskType,
    required this.correct,
    required this.responseTimeMs,
    required this.difficultyIndex,
  });
}

/// Behavioral features extracted from all trials (for backend).
class BehavioralFeatures {
  final double accuracyPercent;
  final double meanReactionMs;
  final double memoryAccuracy;
  final double attentionAccuracy;
  final double languageAccuracy;
  final double executiveAccuracy;
  final double reactionAccuracy;
  final double workingMemoryAccuracy;
  final int correctCount;
  final int errorCount;
  final int omissionCount;
  final int totalTrials;
  final int memoryCorrect;
  final int memoryTotal;
  final int attentionCorrect;
  final int attentionTotal;
  final int languageCorrect;
  final int languageTotal;
  final int executiveCorrect;
  final int executiveTotal;
  final int reactionCorrect;
  final int reactionTotal;
  final int workingMemoryCorrect;
  final int workingMemoryTotal;
  final double completionTime;
  final double consistency;

  const BehavioralFeatures({
    required this.accuracyPercent,
    required this.meanReactionMs,
    required this.memoryAccuracy,
    required this.attentionAccuracy,
    required this.languageAccuracy,
    required this.executiveAccuracy,
    required this.reactionAccuracy,
    required this.workingMemoryAccuracy,
    required this.correctCount,
    required this.errorCount,
    required this.omissionCount,
    required this.totalTrials,
    required this.memoryCorrect,
    required this.memoryTotal,
    required this.attentionCorrect,
    required this.attentionTotal,
    required this.languageCorrect,
    required this.languageTotal,
    required this.executiveCorrect,
    required this.executiveTotal,
    required this.reactionCorrect,
    required this.reactionTotal,
    required this.workingMemoryCorrect,
    required this.workingMemoryTotal,
    required this.completionTime,
    required this.consistency,
  });

  Map<String, dynamic> toJson() => {
        'accuracy_percent': accuracyPercent,
        'mean_reaction_ms': meanReactionMs,
        'memory_accuracy': memoryAccuracy,
        'attention_accuracy': attentionAccuracy,
        'language_accuracy': languageAccuracy,
        'executive_accuracy': executiveAccuracy,
        'reaction_accuracy': reactionAccuracy,
        'working_memory_accuracy': workingMemoryAccuracy,
        'correct_count': correctCount,
        'error_count': errorCount,
        'omission_count': omissionCount,
        'total_trials': totalTrials,
        'memory_correct': memoryCorrect,
        'memory_total': memoryTotal,
        'attention_correct': attentionCorrect,
        'attention_total': attentionTotal,
        'language_correct': languageCorrect,
        'language_total': languageTotal,
        'executive_correct': executiveCorrect,
        'executive_total': executiveTotal,
        'reaction_correct': reactionCorrect,
        'reaction_total': reactionTotal,
        'working_memory_correct': workingMemoryCorrect,
        'working_memory_total': workingMemoryTotal,
        'completion_time': completionTime,
        'consistency': consistency,
      };
}

/// Generates random tasks from templates.
class TaskGenerator {
  final Random _rng = Random();

  GeneratedTask generateMemory(DifficultyLevel difficulty) {
    // ...existing code...
    final categories = objectCategories.keys.toList();
    final category = categories[_rng.nextInt(categories.length)];
    final pool = List<String>.from(objectCategories[category]!);
    pool.shuffle(_rng);
    final length = sequenceLengthFor(difficulty);
    final sequence = pool.take(length).toList();
    final correctItem = sequence[_rng.nextInt(sequence.length)];
    final others = categories.where((c) => c != category).toList();
    final otherCategory = others.isNotEmpty ? others[_rng.nextInt(others.length)] : category;
    final distractors = objectCategories[otherCategory]!
        .where((e) => !sequence.contains(e))
        .toList();
    distractors.shuffle(_rng);
    final options = <String>[correctItem, ...distractors.take(length)].toList();
    options.shuffle(_rng);
    final correctIndex = options.indexOf(correctItem);
    final displayMs = difficulty == DifficultyLevel.easy ? 5000 : (difficulty == DifficultyLevel.medium ? 4000 : 3500);
    return GeneratedTask(
      type: TaskType.memory,
      instruction: 'Remember the sequence. Then tap the one that was in it.',
      options: options,
      correctIndex: correctIndex,
      displayDurationMs: displayMs,
      sequenceDisplay: sequence.join(' → '),
    );
  }

  GeneratedTask generateAttention(DifficultyLevel difficulty) {
    // ...existing code...
    final rows = attentionGridRowsFor(difficulty);
    final targetCount = attentionTargetCountFor(difficulty);
    final symbols = ['🔺', '🔵'];
    final correctRow = _rng.nextInt(rows);
    final optionStrings = <String>[];
    for (int r = 0; r < rows; r++) {
      final list = <String>[];
      if (r == correctRow) {
        for (int i = 0; i < targetCount; i++) {
          list.add('⭐');
        }
        for (int i = targetCount; i < 5; i++) {
          list.add(symbols[_rng.nextInt(symbols.length)]);
        }
        list.shuffle(_rng);
      } else {
        int starCount = _rng.nextInt(6);
        if (starCount == targetCount) starCount = (targetCount + 1) % 6;
        for (int i = 0; i < starCount && i < 5; i++) {
          list.add('⭐');
        }
        for (int i = list.length; i < 5; i++) {
          list.add(symbols[_rng.nextInt(symbols.length)]);
        }
        list.shuffle(_rng);
      }
      optionStrings.add(list.join(' '));
    }
    return GeneratedTask(
      type: TaskType.attention,
      instruction: 'Tap the row that has exactly $targetCount ⭐ stars.',
      options: optionStrings,
      correctIndex: correctRow,
    );
  }

  GeneratedTask generateLanguage(DifficultyLevel difficulty) {
    // ...existing code...
    final n = languageOptionCountFor(difficulty);
    final template = languageTemplates[_rng.nextInt(languageTemplates.length)];
    final allEmojis = <String>[];
    for (final list in objectCategories.values) {
      allEmojis.addAll(list);
    }
    allEmojis.shuffle(_rng);
    final correctLabel = template.targetAttribute;
    String? correctEmoji;
    for (final e in optionLabels.entries) {
      if (e.value == correctLabel) {
        correctEmoji = e.key;
        break;
      }
    }
    correctEmoji ??= allEmojis.first;
    final options = <String>[correctEmoji];
    for (final e in allEmojis) {
      if (options.length >= n) break;
      if (e != correctEmoji && !options.contains(e)) options.add(e);
    }
    while (options.length < n && allEmojis.isNotEmpty) {
      final e = allEmojis[_rng.nextInt(allEmojis.length)];
      if (!options.contains(e)) options.add(e);
    }
    options.shuffle(_rng);
    final correctIndex = options.indexOf(correctEmoji);
    return GeneratedTask(
      type: TaskType.language,
      instruction: template.instruction,
      options: options,
      correctIndex: correctIndex >= 0 ? correctIndex : 0,
    );
  }

  // Placeholders for new domains (to be implemented in next steps)
  GeneratedTask generateStroop(DifficultyLevel difficulty) {
    // TODO: Implement Stroop task generation
    return const GeneratedTask(
      type: TaskType.executiveFunction,
      instruction: 'Stroop task (to be implemented)',
      options: ['Red', 'Blue', 'Green', 'Yellow'],
      correctIndex: 0,
      stroopWord: 'RED',
      stroopColor: 'blue',
    );
  }

  GeneratedTask generateReactionTime(DifficultyLevel difficulty) {
    // TODO: Implement Reaction Time task generation
    return const GeneratedTask(
      type: TaskType.processingSpeed,
      instruction: 'Reaction time task (to be implemented)',
      options: ['Tap!'],
      correctIndex: 0,
      reactionDelayMs: 1000,
    );
  }

  GeneratedTask generateNBack(DifficultyLevel difficulty) {
    // TODO: Implement N-back task generation
    return const GeneratedTask(
      type: TaskType.workingMemory,
      instruction: 'N-back task (to be implemented)',
      options: ['Yes', 'No'],
      correctIndex: 0,
      nBackLevel: 2,
    );
  }

  GeneratedTask generate(TaskType type, DifficultyLevel difficulty) {
    switch (type) {
      case TaskType.memory:
        return generateMemory(difficulty);
      case TaskType.attention:
        return generateAttention(difficulty);
      case TaskType.language:
        return generateLanguage(difficulty);
      case TaskType.executiveFunction:
        return generateStroop(difficulty);
      case TaskType.processingSpeed:
        return generateReactionTime(difficulty);
      case TaskType.workingMemory:
        return generateNBack(difficulty);
    }
  }
}

/// Records every trial and computes behavioral features.
class BehavioralRecorder {
  final List<TrialRecord> _trials = [];

  void record(TaskType type, bool correct, int responseTimeMs, int difficultyIndex) {
    _trials.add(TrialRecord(
      taskType: type,
      correct: correct,
      responseTimeMs: responseTimeMs,
      difficultyIndex: difficultyIndex,
    ));
  }

  BehavioralFeatures getFeatures() {
    if (_trials.isEmpty) {
      return const BehavioralFeatures(
        accuracyPercent: 0,
        meanReactionMs: 1200,
        memoryAccuracy: 0,
        attentionAccuracy: 0,
        languageAccuracy: 0,
        executiveAccuracy: 0,
        reactionAccuracy: 0,
        workingMemoryAccuracy: 0,
        correctCount: 0,
        errorCount: 0,
        omissionCount: 0,
        totalTrials: 0,
        memoryCorrect: 0,
        memoryTotal: 0,
        attentionCorrect: 0,
        attentionTotal: 0,
        languageCorrect: 0,
        languageTotal: 0,
        executiveCorrect: 0,
        executiveTotal: 0,
        reactionCorrect: 0,
        reactionTotal: 0,
        workingMemoryCorrect: 0,
        workingMemoryTotal: 0,
        completionTime: 0,
        consistency: 0,
      );
    }
    final total = _trials.length;
    final correct = _trials.where((t) => t.correct).length;
    final totalMs = _trials.fold<int>(0, (s, t) => s + t.responseTimeMs);
    final mem = _trials.where((t) => t.taskType == TaskType.memory).toList();
    final att = _trials.where((t) => t.taskType == TaskType.attention).toList();
    final lang = _trials.where((t) => t.taskType == TaskType.language).toList();
    final exec = _trials.where((t) => t.taskType == TaskType.executiveFunction).toList();
    final react = _trials.where((t) => t.taskType == TaskType.processingSpeed).toList();
    final wm = _trials.where((t) => t.taskType == TaskType.workingMemory).toList();

    final memCorrect = mem.where((t) => t.correct).length;
    final attCorrect = att.where((t) => t.correct).length;
    final langCorrect = lang.where((t) => t.correct).length;
    final execCorrect = exec.where((t) => t.correct).length;
    final reactCorrect = react.where((t) => t.correct).length;
    final wmCorrect = wm.where((t) => t.correct).length;
    final memTotal = mem.length;
    final attTotal = att.length;
    final langTotal = lang.length;
    final execTotal = exec.length;
    final reactTotal = react.length;
    final wmTotal = wm.length;

    double memAcc = memTotal == 0 ? 0 : memCorrect / memTotal * 100;
    double attAcc = attTotal == 0 ? 0 : attCorrect / attTotal * 100;
    double langAcc = langTotal == 0 ? 0 : langCorrect / langTotal * 100;
    double execAcc = execTotal == 0 ? 0 : execCorrect / execTotal * 100;
    double reactAcc = reactTotal == 0 ? 0 : reactCorrect / reactTotal * 100;
    double wmAcc = wmTotal == 0 ? 0 : wmCorrect / wmTotal * 100;

    // Omissions: trials with response time > 10s (or not answered, if tracked)
    final omissionCount = _trials.where((t) => t.responseTimeMs > 10000).length;
    // Completion time: sum of all response times (ms)
    final completionTime = totalMs / 1000.0; // seconds
    // Consistency: store response-time variance (ms²). Lower values indicate
    // steadier performance across trials and are later normalized in backend scoring.
    final mean = totalMs / total;
    final variance = _trials.fold<double>(
          0,
          (s, t) => s + (t.responseTimeMs - mean) * (t.responseTimeMs - mean),
        ) /
        total;
    final consistency = variance;

    return BehavioralFeatures(
      accuracyPercent: correct / total * 100,
      meanReactionMs: totalMs / total.toDouble(),
      memoryAccuracy: memAcc,
      attentionAccuracy: attAcc,
      languageAccuracy: langAcc,
      executiveAccuracy: execAcc,
      reactionAccuracy: reactAcc,
      workingMemoryAccuracy: wmAcc,
      correctCount: correct,
      errorCount: total - correct,
      omissionCount: omissionCount,
      totalTrials: total,
      memoryCorrect: memCorrect,
      memoryTotal: memTotal,
      attentionCorrect: attCorrect,
      attentionTotal: attTotal,
      languageCorrect: langCorrect,
      languageTotal: langTotal,
      executiveCorrect: execCorrect,
      executiveTotal: execTotal,
      reactionCorrect: reactCorrect,
      reactionTotal: reactTotal,
      workingMemoryCorrect: wmCorrect,
      workingMemoryTotal: wmTotal,
      completionTime: completionTime,
      consistency: consistency.toDouble(),
    );
  }

  void clear() => _trials.clear();
}

/// Adaptive difficulty: increase if accuracy > 80%, decrease if < 40%.

class CognitiveGameEngine {
  int _memoryLevel = 1;
  int _attentionLevel = 1;
  int _languageLevel = 1;
  final int _executiveLevel = 1;
  final int _processingLevel = 1;
  final int _workingMemoryLevel = 1;

  static const int maxLevel = 2; // 0=easy, 1=medium, 2=hard

  DifficultyLevel getMemoryDifficulty() => _levelToDifficulty(_memoryLevel);
  DifficultyLevel getAttentionDifficulty() => _levelToDifficulty(_attentionLevel);
  DifficultyLevel getLanguageDifficulty() => _levelToDifficulty(_languageLevel);
  DifficultyLevel getExecutiveFunctionDifficulty() => _levelToDifficulty(_executiveLevel);
  DifficultyLevel getProcessingSpeedDifficulty() => _levelToDifficulty(_processingLevel);
  DifficultyLevel getWorkingMemoryDifficulty() => _levelToDifficulty(_workingMemoryLevel);

  DifficultyLevel _levelToDifficulty(int level) {
    if (level <= 0) return DifficultyLevel.easy;
    if (level >= 2) return DifficultyLevel.hard;
    return DifficultyLevel.medium;
  }

  int get memoryLevel => _memoryLevel;
  int get attentionLevel => _attentionLevel;
  int get languageLevel => _languageLevel;

  void update(TaskType type, double accuracyPercent) {
    if (accuracyPercent > 80 && type == TaskType.memory && _memoryLevel < maxLevel) _memoryLevel++;
    if (accuracyPercent < 40 && type == TaskType.memory && _memoryLevel > 0) _memoryLevel--;
    if (accuracyPercent > 80 && type == TaskType.attention && _attentionLevel < maxLevel) _attentionLevel++;
    if (accuracyPercent < 40 && type == TaskType.attention && _attentionLevel > 0) _attentionLevel--;
    if (accuracyPercent > 80 && type == TaskType.language && _languageLevel < maxLevel) _languageLevel++;
    if (accuracyPercent < 40 && type == TaskType.language && _languageLevel > 0) _languageLevel--;
  }
}
