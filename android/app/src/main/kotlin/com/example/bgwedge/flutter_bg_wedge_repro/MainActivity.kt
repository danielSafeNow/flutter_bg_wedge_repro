package com.example.bgwedge.flutter_bg_wedge_repro

import android.app.ActivityManager
import android.content.Context
import android.os.Bundle
import android.os.Process
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import java.lang.reflect.Field

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val MODULE_CLASS =
            "com.transistorsoft.flutter.backgroundgeolocation.BackgroundGeolocationModule"
        private var activityCreateCount = 0
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        activityCreateCount += 1
        Log.i(TAG, "lifecycle.onCreate {activityCreateCount=$activityCreateCount, pid=${Process.myPid()}}")
        probe("onCreate.done")
        logFgsState("onCreate.done")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        Log.i(TAG, "configureFlutterEngine.start")
        super.configureFlutterEngine(flutterEngine)
        Log.i(TAG, "configureFlutterEngine.done")
        probe("configureFlutterEngine.done")
        logFgsState("configureFlutterEngine.done")
    }

    override fun onResume() {
        super.onResume()
        Log.i(TAG, "lifecycle.onResume {activityCreateCount=$activityCreateCount}")
        probe("onResume.done")
    }

    override fun onPause() {
        Log.i(TAG, "lifecycle.onPause {hasFocus=${hasWindowFocus()}, isFinishing=$isFinishing}")
        super.onPause()
    }

    override fun onDestroy() {
        Log.i(TAG, "lifecycle.onDestroy {isFinishing=$isFinishing}")
        super.onDestroy()
    }

    private fun probe(site: String) {
        try {
            val moduleClass = Class.forName(MODULE_CLASS)
            val instance = moduleClass.getMethod("getInstance").invoke(null)
            val field: Field = moduleClass.getDeclaredField("mActivity").apply { isAccessible = true }
            val pluginActivity = field.get(instance) as? android.app.Activity
            val matchesCurrent = pluginActivity != null && pluginActivity.hashCode() == this.hashCode()
            Log.i(
                "BgPluginProbe",
                "mActivity.read {site=$site, pluginActivityHash=${pluginActivity?.hashCode()}, currentActivityHash=${hashCode()}, matchesCurrent=$matchesCurrent, pluginActivityClass=${pluginActivity?.javaClass?.name}}"
            )
        } catch (t: Throwable) {
            Log.w("BgPluginProbe", "probe.failed {site=$site, error=${t.javaClass.simpleName}: ${t.message}}")
        }
    }

    private fun logFgsState(site: String) {
        try {
            val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val ourUid = Process.myUid()
            @Suppress("DEPRECATION")
            val services = am.getRunningServices(Int.MAX_VALUE).filter { it.uid == ourUid }
            val trackingService = services.firstOrNull { it.service.className.contains("TrackingService") }
            Log.i(
                "BgPluginProbe",
                "fgs.state {site=$site, ourServiceCount=${services.size}, trackingServiceForeground=${trackingService?.foreground}, trackingServiceStarted=${trackingService?.started}, services=${services.map { it.service.className }}}"
            )
        } catch (t: Throwable) {
            Log.w("BgPluginProbe", "fgs.probe.failed {site=$site, error=${t.javaClass.simpleName}: ${t.message}}")
        }
    }
}