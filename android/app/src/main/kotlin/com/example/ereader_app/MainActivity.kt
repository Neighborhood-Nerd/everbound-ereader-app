package com.neighborhoodnerd.everbound

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.neighborhoodnerd.everbound/volume_keys"
    private val EVENT_CHANNEL = "com.neighborhoodnerd.everbound/volume_key_events"
    private var shouldInterceptVolumeKeys = false
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeKeyInterception" -> {
                    shouldInterceptVolumeKeys = call.arguments as Boolean
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // Intercept volume keys if enabled
        if (shouldInterceptVolumeKeys) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    // Send event to Flutter
                    eventSink?.success(keyCode)
                    // Consume the event to prevent system volume UI from showing
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }
}
