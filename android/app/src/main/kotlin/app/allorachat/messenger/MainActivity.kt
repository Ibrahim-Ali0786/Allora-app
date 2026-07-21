package app.allorachat.messenger

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterFragmentActivity (not FlutterActivity) is required by local_auth
 * for the BiometricPrompt API.
 *
 * Two method channels:
 *  - "…/secure"  toggles FLAG_SECURE (screenshot/recent-apps protection).
 *  - "…/bubble"  drives the floating chat overlay ([BubbleService]).
 */
class MainActivity : FlutterFragmentActivity() {
    private val secureChannel = "app.allorachat.messenger/secure"
    private val bubbleChannel = "app.allorachat.messenger/bubble"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, secureChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        runOnUiThread {
                            if (secure) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, bubbleChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(canDrawOverlays())
                    "requestPermission" -> {
                        if (!canDrawOverlays()) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "show" -> {
                        val unread = call.argument<Int>("unread") ?: 0
                        if (canDrawOverlays()) {
                            startBubble(unread)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    }
                    "updateUnread" -> {
                        val unread = call.argument<Int>("unread") ?: 0
                        if (canDrawOverlays()) startBubble(unread)
                        result.success(true)
                    }
                    "hide" -> {
                        stopService(Intent(this, BubbleService::class.java))
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun startBubble(unread: Int) {
        try {
            val intent = Intent(this, BubbleService::class.java)
            intent.putExtra(BubbleService.EXTRA_UNREAD, unread)
            startService(intent)
        } catch (e: Exception) {
            // Background service-start can be restricted on newer Android;
            // degrade gracefully rather than crash.
        }
    }
}
