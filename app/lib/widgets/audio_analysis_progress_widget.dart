import 'package:flutter/material.dart';

/// Stages of audio analysis for UI feedback.
enum AudioAnalysisStage {
  idle,
  uploading,
  analyzing,
  generating,
  done,
  error,
  cached,
}

/// Widget that displays audio analysis progress with stages and messages.
class AudioAnalysisProgressWidget extends StatefulWidget {
  final AudioAnalysisStage stage;
  final double? uploadProgress;
  final String? customMessage;
  final VoidCallback? onCancel;
  final bool isCached;

  const AudioAnalysisProgressWidget({
    required this.stage,
    this.uploadProgress,
    this.customMessage,
    this.onCancel,
    this.isCached = false,
    super.key,
  });

  @override
  State<AudioAnalysisProgressWidget> createState() =>
      _AudioAnalysisProgressWidgetState();
}

class _AudioAnalysisProgressWidgetState
    extends State<AudioAnalysisProgressWidget> with TickerProviderStateMixin {
  late AnimationController _spinnerController;
  late AnimationController _fakeProgressController;

  @override
  void initState() {
    super.initState();
    _spinnerController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fakeProgressController = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    );

    if (widget.stage != AudioAnalysisStage.idle &&
        widget.stage != AudioAnalysisStage.done &&
        widget.stage != AudioAnalysisStage.error &&
        widget.stage != AudioAnalysisStage.cached) {
      _spinnerController.repeat();
      _fakeProgressController.forward();
    }
  }

  @override
  void didUpdateWidget(AudioAnalysisProgressWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.stage != oldWidget.stage) {
      if (widget.stage == AudioAnalysisStage.idle ||
          widget.stage == AudioAnalysisStage.done ||
          widget.stage == AudioAnalysisStage.error ||
          widget.stage == AudioAnalysisStage.cached) {
        _spinnerController.stop();
        _fakeProgressController.stop();
      } else {
        if (!_spinnerController.isAnimating) {
          _spinnerController.repeat();
        }
        if (!_fakeProgressController.isAnimating) {
          _fakeProgressController.forward();
        }
      }
    }
  }

  @override
  void dispose() {
    _spinnerController.dispose();
    _fakeProgressController.dispose();
    super.dispose();
  }

  String _getStageEmoji(AudioAnalysisStage stage) {
    switch (stage) {
      case AudioAnalysisStage.uploading:
        return '📤';
      case AudioAnalysisStage.analyzing:
        return '🧠';
      case AudioAnalysisStage.generating:
        return '✨';
      case AudioAnalysisStage.done:
        return '✅';
      case AudioAnalysisStage.error:
        return '⚠️';
      case AudioAnalysisStage.cached:
        return '⚡';
      case AudioAnalysisStage.idle:
        return '';
    }
  }

  String _getStageMessage(AudioAnalysisStage stage) {
    if (widget.customMessage != null && widget.customMessage!.isNotEmpty) {
      return widget.customMessage!;
    }

    switch (stage) {
      case AudioAnalysisStage.uploading:
        return 'Uploading your audio...';
      case AudioAnalysisStage.analyzing:
        return 'Analyzing speech patterns...';
      case AudioAnalysisStage.generating:
        return 'Generating assessment...';
      case AudioAnalysisStage.done:
        return 'Analysis complete!';
      case AudioAnalysisStage.error:
        return 'Something went wrong';
      case AudioAnalysisStage.cached:
        return 'Loading cached result...';
      case AudioAnalysisStage.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;

    if (stage == AudioAnalysisStage.idle) {
      return const SizedBox.shrink();
    }

    final emoji = _getStageEmoji(stage);
    final message = _getStageMessage(stage);
    final isLoading = stage != AudioAnalysisStage.done &&
        stage != AudioAnalysisStage.error &&
        stage != AudioAnalysisStage.cached;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Emoji + Spinner
          if (isLoading) ...[
            RotationTransition(
              turns: _spinnerController,
              child: Text(
                emoji,
                style: const TextStyle(fontSize: 40),
              ),
            ),
          ] else ...[
            Text(
              emoji,
              style: const TextStyle(fontSize: 40),
            ),
          ],
          const SizedBox(height: 16),

          // Stage message
          Text(
            message,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),

          // Upload progress bar (if uploading)
          if (widget.uploadProgress != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: 200,
              child: LinearProgressIndicator(
                value: widget.uploadProgress,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${(widget.uploadProgress! * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],

          // Fake progress bar (for non-upload stages)
          if (widget.uploadProgress == null && isLoading) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: 200,
              child: AnimatedBuilder(
                animation: _fakeProgressController,
                builder: (context, child) {
                  // Non-linear progress: slower at start, faster in middle, plateau at end
                  final value = _fakeProgressController.value;
                  final eased = value < 0.7
                      ? value * 1.3
                      : 0.7 + (value - 0.7) * 0.3;
                  return LinearProgressIndicator(
                    value: eased.clamp(0.0, 1.0),
                    minHeight: 6,
                  );
                },
              ),
            ),
          ],

          // Cancel button
          if (isLoading && widget.onCancel != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close),
              label: const Text('Cancel'),
            ),
          ],

          // Error hint
          if (stage == AudioAnalysisStage.error) ...[
            const SizedBox(height: 16),
            const Text(
              'Try again in a moment',
              style: TextStyle(
                fontSize: 13,
                color: Colors.white70,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Helper to map AudioPhase to AudioAnalysisStage.
/// Note: AudioPhase is imported from the screen file when used.
AudioAnalysisStage audioPhaseToStage(dynamic phase) {
  // phase is expected to be an AudioPhase enum from audio_assessment_screen
  final phaseName = phase.toString().split('.').last;
  switch (phaseName) {
    case 'idle':
      return AudioAnalysisStage.idle;
    case 'uploading':
      return AudioAnalysisStage.uploading;
    case 'analyzing':
      return AudioAnalysisStage.analyzing;
    case 'done':
      return AudioAnalysisStage.done;
    case 'error':
      return AudioAnalysisStage.error;
    default:
      return AudioAnalysisStage.idle;
  }
}
