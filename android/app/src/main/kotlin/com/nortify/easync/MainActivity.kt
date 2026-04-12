package com.nortify.easync

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity : FlutterFragmentActivity() {
	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		super.configureFlutterEngine(flutterEngine)
		// Defensive registration for devices/builds where auto-registration misses plugins.
		GeneratedPluginRegistrant.registerWith(flutterEngine)
	}
}