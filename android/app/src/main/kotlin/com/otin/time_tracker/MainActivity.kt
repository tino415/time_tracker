package com.otin.time_tracker

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var wearBridge: WearBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Phone vs Wear OS detection, consumed by _detectIsWatch() in main.dart.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "time_tracker/platform",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWatch" -> {
                    val pm = applicationContext.packageManager
                    result.success(pm.hasSystemFeature(PackageManager.FEATURE_WATCH))
                }
                else -> result.notImplemented()
            }
        }

        // Attached on both form factors: one APK, and the protocol is symmetric
        // enough that the phone side is just a different set of message types.
        wearBridge = WearBridge(this, flutterEngine.dartExecutor.binaryMessenger).also { it.attach() }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) window.decorView.requestApplyInsets()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        wearBridge?.detach()
        wearBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
