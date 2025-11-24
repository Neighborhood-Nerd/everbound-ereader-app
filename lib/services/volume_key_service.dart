import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

/// Service for handling volume key events for page navigation
/// Manages Android native key interception and Flutter volume change detection
class VolumeKeyService {
  static final VolumeKeyService instance = VolumeKeyService._internal();
  factory VolumeKeyService() => instance;
  VolumeKeyService._internal();

  final MethodChannel _volumeKeyChannel = const MethodChannel('com.neighborhoodnerd.everbound/volume_keys');
  static const EventChannel _volumeKeyEventChannel = EventChannel('com.neighborhoodnerd.everbound/volume_key_events');

  StreamSubscription? _volumeKeyEventSubscription;
  double? _lastVolume;
  double? _originalVolume; // Store original volume to restore after changes
  bool _isListening = false;
  bool _isRestoringVolume = false; // Flag to prevent recursive calls during restoration

  /// Callbacks for volume key events
  VoidCallback? onVolumeUp;
  VoidCallback? onVolumeDown;

  /// Initialize volume key listener
  /// [enabled] - whether volume keys should be intercepted
  /// [onVolumeUp] - callback when volume up is detected
  /// [onVolumeDown] - callback when volume down is detected
  Future<void> initialize({required bool enabled, VoidCallback? onVolumeUp, VoidCallback? onVolumeDown}) async {
    this.onVolumeUp = onVolumeUp;
    this.onVolumeDown = onVolumeDown;

    if (enabled) {
      await startListening();
    } else {
      await stopListening();
    }
  }

  /// Start listening for volume key events
  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    try {
      // Notify Android to intercept volume keys
      await _setVolumeKeyInterception(true);

      // Suppress system volume UI
      await FlutterVolumeController.updateShowSystemUI(false);

      // Get initial volume and store it as the original
      _originalVolume = await FlutterVolumeController.getVolume();
      _lastVolume = _originalVolume;
      print('Initial volume: $_originalVolume');

      // Listen for volume key events from Android (when keys are pressed)
      try {
        _volumeKeyEventSubscription = _volumeKeyEventChannel.receiveBroadcastStream().listen(
          (dynamic event) {
            final keyCode = event as int;
            print('Volume key pressed: $keyCode');

            // Manually change volume to trigger FlutterVolumeController listener
            if (keyCode == 24) {
              // KEYCODE_VOLUME_UP
              FlutterVolumeController.raiseVolume(null);
            } else if (keyCode == 25) {
              // KEYCODE_VOLUME_DOWN
              FlutterVolumeController.lowerVolume(null);
            }
          },
          onError: (error) {
            print('Error in volume key event stream: $error');
          },
        );
      } catch (e) {
        print('EventChannel not available (app may need rebuild): $e');
        // Continue without EventChannel - FlutterVolumeController will still work
        // for volume changes from control panel or if keys aren't intercepted
      }

      // Listen for volume changes (triggered by programmatic changes above)
      FlutterVolumeController.addListener(
        (volume) async {
          // Ignore volume changes during restoration to prevent recursion
          if (_isRestoringVolume) {
            _lastVolume = volume;
            return;
          }

          // Determine if volume went up or down compared to original
          // This ensures we always detect the correct direction regardless of restoration state
          if (_lastVolume != null && _originalVolume != null) {
            // Check if this is a restoration (volume returning to original)
            final isRestoration = (volume - _originalVolume!).abs() < 0.01; // Small tolerance for floating point
            if (isRestoration) {
              // This is a restoration, just update lastVolume and ignore
              _lastVolume = volume;
              return;
            }

            // Check if volume has actually changed from lastVolume
            // This prevents duplicate triggers when volume doesn't change
            final hasChanged = (volume - _lastVolume!).abs() > 0.01;

            // Also check that volume is different from original (not a restoration)
            final isDifferentFromOriginal = (volume - _originalVolume!).abs() > 0.01;

            if (hasChanged && isDifferentFromOriginal) {
              // Compare against original volume to determine direction
              // This is more reliable than comparing against lastVolume
              final volumeIncreased = volume > _originalVolume!;
              final volumeDecreased = volume < _originalVolume!;

              if (volumeIncreased) {
                onVolumeUp?.call();
                // Update lastVolume immediately before restoring to prevent race conditions
                _lastVolume = volume;
                // Restore original volume after a short delay
                await _restoreOriginalVolume();
              } else if (volumeDecreased) {
                onVolumeDown?.call();
                // Update lastVolume immediately before restoring to prevent race conditions
                _lastVolume = volume;
                // Restore original volume after a short delay
                await _restoreOriginalVolume();
              }
            } else {
              // Volume hasn't changed or is same as original, just update lastVolume
              _lastVolume = volume;
            }
          } else {
            // First volume reading, just store it
            _lastVolume = volume;
          }
        },
        emitOnStart: false, // Don't emit initial volume as a change
      );

      _isListening = true;
    } catch (e, stackTrace) {
      print('Error starting volume key listener: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Stop listening for volume key events
  Future<void> stopListening() async {
    if (!_isListening) {
      return;
    }

    try {
      // Notify Android to stop intercepting volume keys
      await _setVolumeKeyInterception(false);

      // Remove listeners
      FlutterVolumeController.removeListener();
      _volumeKeyEventSubscription?.cancel();
      _volumeKeyEventSubscription = null;

      // Restore system volume UI
      await FlutterVolumeController.updateShowSystemUI(true);

      // Restore original volume when stopping
      if (_originalVolume != null) {
        try {
          await FlutterVolumeController.setVolume(_originalVolume!);
        } catch (e) {
          print('Error restoring volume on stop: $e');
        }
      }

      _isListening = false;
      _originalVolume = null;
      _lastVolume = null;
    } catch (e) {
      print('Error stopping volume key listener: $e');
    }
  }

  /// Update the enabled state
  Future<void> setEnabled(bool enabled) async {
    if (enabled) {
      await startListening();
    } else {
      await stopListening();
    }
  }

  /// Update callbacks
  void updateCallbacks({VoidCallback? onVolumeUp, VoidCallback? onVolumeDown}) {
    this.onVolumeUp = onVolumeUp;
    this.onVolumeDown = onVolumeDown;
  }

  /// Restore volume to original value after detecting a change
  Future<void> _restoreOriginalVolume() async {
    if (_originalVolume == null || _isRestoringVolume) return;

    try {
      _isRestoringVolume = true;
      // Small delay to ensure the callback has been processed
      await Future.delayed(const Duration(milliseconds: 100));

      // Restore to original volume
      await FlutterVolumeController.setVolume(_originalVolume!);
      // Update lastVolume immediately to prevent false detections
      _lastVolume = _originalVolume;

      // Small delay before allowing new volume changes
      await Future.delayed(const Duration(milliseconds: 100));
      _isRestoringVolume = false;
    } catch (e) {
      print('Error restoring volume: $e');
      _isRestoringVolume = false;
    }
  }

  /// Notify Android to intercept volume keys to prevent system UI
  Future<void> _setVolumeKeyInterception(bool enabled) async {
    try {
      await _volumeKeyChannel.invokeMethod('setVolumeKeyInterception', enabled);
    } catch (e) {
      print('Error setting volume key interception: $e');
    }
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    await stopListening();
    onVolumeUp = null;
    onVolumeDown = null;
  }
}
