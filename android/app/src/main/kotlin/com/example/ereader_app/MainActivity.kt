package com.neighborhoodnerd.everbound

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.neighborhoodnerd.everbound/volume_keys"
    private val PERMISSIONS_CHANNEL = "com.neighborhoodnerd.everbound/permissions"
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
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSIONS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openStoragePermissionSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        // Android 11+ (API 30+): Try to open "All files access" page for this app
                        try {
                            // First, try the app-specific "All files access" page
                            val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                            intent.data = Uri.parse("package:${packageName}")
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // If app-specific page fails, try the general "All files access" page
                            try {
                                val intent = Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                // Final fallback: open app settings
                                try {
                                    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                    intent.data = Uri.parse("package:${packageName}")
                                    startActivity(intent)
                                    result.success(true)
                                } catch (e3: Exception) {
                                    result.error("ERROR", "Failed to open settings: ${e3.message}", null)
                                }
                            }
                        }
                    } else {
                        // Android 10 and below: Open app settings (permissions are visible there)
                        try {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                            intent.data = Uri.parse("package:${packageName}")
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("ERROR", "Failed to open settings: ${e.message}", null)
                        }
                    }
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
