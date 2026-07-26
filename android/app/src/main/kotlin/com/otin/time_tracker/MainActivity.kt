package com.otin.time_tracker

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Phone vs Wear OS detection consumed by _detectIsWatch() in main.dart.
        // The Wear data-layer bridge (cf. gym_tracker's GymWearBridge) arrives
        // with the watch phase.
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
    }
}
