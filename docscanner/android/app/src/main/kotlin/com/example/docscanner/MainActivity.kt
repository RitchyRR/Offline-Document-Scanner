package com.example.docscanner

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var captureVolumeKeys = false
    private lateinit var volumeChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        volumeChannel.setMethodCallHandler { call, result ->
            if (call.method == "setEnabled") {
                captureVolumeKeys = call.arguments as? Boolean ?: false
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (captureVolumeKeys &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            if (event?.repeatCount == 0) volumeChannel.invokeMethod("volumeKey", null)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    companion object {
        private const val CHANNEL = "docscanner/volume"
    }
}
