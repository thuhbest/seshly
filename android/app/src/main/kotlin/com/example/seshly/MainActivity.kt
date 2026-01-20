package com.example.seshly

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "seshly/seshfocus"
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startPinning" -> {
                    startLockTask()
                    val minutes = call.argument<Int>("minutes") ?: 0
                    autoUnlock(minutes)
                    result.success(null)
                }

                "stopPinning" -> {
                    stopLockTask()
                    handler.removeCallbacksAndMessages(null)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun autoUnlock(minutes: Int) {
        handler.removeCallbacksAndMessages(null)
        handler.postDelayed({
            stopLockTask()
        }, minutes * 60 * 1000L)
    }
}
