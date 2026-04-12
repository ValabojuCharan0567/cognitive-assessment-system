/// Task template library for the Cognitive Game Engine.
/// Defines categories, instruction templates, and parameters for dynamic task generation.
library;

enum TaskType {
  memory,
  attention,
  language,
  executiveFunction, // Stroop
  processingSpeed,   // Reaction Time
  workingMemory      // N-back
}

enum DifficultyLevel { easy, medium, hard }

// New: Cognitive domains for clarity (optional, for future extensibility)
enum CognitiveDomain {
  attention,
  memory,
  language,
  executiveFunction,
  processingSpeed,
  workingMemory,
}

/// Object categories for memory and language tasks (emoji + label).
const Map<String, List<String>> objectCategories = {
  'animals': ['🐶', '🐱', '🐰', '🐻', '🐼', '🐸', '🐵', '🐔', '🐧', '🐴'],
  'fruits': ['🍎', '🍊', '🍋', '🍇', '🍓', '🍑', '🍒', '🥝', '🍌', '🍉'],
  'shapes': ['⭐', '🔺', '🔵', '■', '♥', '♦', '🔶', '⬟', '🔷', '★'],
  'vehicles': ['🚗', '🚲', '✈️', '🚀', '🚂', '🚌', '🛵', '🚁', '⛵', '🚜'],
  'nature': ['🌳', '🌸', '🌻', '🍀', '🌴', '🌺', '🍁', '🌙', '☀️', '🌈'],
};

/// Instruction templates for language tasks: (instruction text, correct attribute).
/// Placeholder {{options}} can be used; we fill options from category.
final List<({String instruction, String targetAttribute})> languageTemplates = [
  (instruction: 'Tap the animal that barks.', targetAttribute: 'dog'),
  (instruction: 'Tap the animal that flies.', targetAttribute: 'bird'),
  (instruction: 'Tap the animal that says meow.', targetAttribute: 'cat'),
  (instruction: 'Tap the red one.', targetAttribute: 'red'),
  (instruction: 'Tap the fruit that is yellow.', targetAttribute: 'banana'),
  (instruction: 'Tap the animal that hops.', targetAttribute: 'rabbit'),
  (instruction: 'Tap the one that is round.', targetAttribute: 'ball'),
  (instruction: 'Tap the star.', targetAttribute: 'star'),
];

/// Labels for language options (for matching target attribute).
const Map<String, String> optionLabels = {
  '🐶': 'dog',
  '🐱': 'cat',
  '🐰': 'rabbit',
  '🐻': 'bear',
  '🐼': 'panda',
  '🐸': 'frog',
  '🐵': 'monkey',
  '🐔': 'chicken',
  '🐧': 'penguin',
  '🐴': 'horse',
  '🍎': 'apple',
  '🍊': 'orange',
  '🍋': 'lemon',
  '🍇': 'grape',
  '🍓': 'strawberry',
  '🍑': 'peach',
  '🍒': 'cherry',
  '🥝': 'kiwi',
  '🍌': 'banana',
  '🍉': 'watermelon',
  '⭐': 'star',
  '🔺': 'triangle',
  '🔵': 'circle',
  '🚗': 'car',
  '🚲': 'bike',
  '✈️': 'plane',
};

/// Difficulty parameters: sequence length (memory), grid size / targets (attention), option count, etc.
int sequenceLengthFor(DifficultyLevel d) {
  switch (d) {
    case DifficultyLevel.easy:
      return 3;
    case DifficultyLevel.medium:
      return 4;
    case DifficultyLevel.hard:
      return 5;
  }
}

int attentionGridRowsFor(DifficultyLevel d) {
  switch (d) {
    case DifficultyLevel.easy:
      return 3;
    case DifficultyLevel.medium:
      return 4;
    case DifficultyLevel.hard:
      return 5;
  }
}

int attentionTargetCountFor(DifficultyLevel d) {
  switch (d) {
    case DifficultyLevel.easy:
      return 2;
    case DifficultyLevel.medium:
      return 3;
    case DifficultyLevel.hard:
      return 4;
  }
}

int languageOptionCountFor(DifficultyLevel d) {
  switch (d) {
    case DifficultyLevel.easy:
      return 3;
    case DifficultyLevel.medium:
      return 4;
    case DifficultyLevel.hard:
      return 5;
  }
}

// Placeholders for new domains (to be implemented in next steps)
int stroopTrialCountFor(DifficultyLevel d) {
  switch (d) {
    case DifficultyLevel.easy:
      return 4;
    case DifficultyLevel.medium:
      return 6;
    case DifficultyLevel.hard:
      return 8;
  }
}

int reactionTimeTrialCountFor(DifficultyLevel d) {
  switch (d) {
    case DifficultyLevel.easy:
      return 5;
    case DifficultyLevel.medium:
      return 7;
    case DifficultyLevel.hard:
      return 10;
  }
}

int nBackLevelFor(DifficultyLevel d) {
  switch (d) {
    case DifficultyLevel.easy:
      return 1;
    case DifficultyLevel.medium:
      return 2;
    case DifficultyLevel.hard:
      return 3;
  }
}
