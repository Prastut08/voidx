package com.example.mobile

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    private var relayModule: OfflineEmergencyRelay? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        relayModule = OfflineEmergencyRelay(this)
        relayModule?.register(flutterEngine)
    }
}
