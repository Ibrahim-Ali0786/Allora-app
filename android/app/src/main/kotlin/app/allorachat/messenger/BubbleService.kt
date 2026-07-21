package app.allorachat.messenger

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import kotlin.math.abs

/**
 * A draggable floating chat bubble drawn over other apps.
 *
 * Built entirely from code (no XML resources): a circular gradient badge
 * showing "A" plus an unread counter. Drag it — it snaps to the nearest
 * edge; tap it — Allora comes to the front. Started/stopped and updated
 * from Dart via the "…/bubble" method channel in [MainActivity].
 */
class BubbleService : Service() {

    companion object {
        const val EXTRA_UNREAD = "unread"
    }

    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var badgeView: TextView? = null
    private var layoutParams: WindowManager.LayoutParams? = null
    private var unread: Int = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        unread = intent?.getIntExtra(EXTRA_UNREAD, 0) ?: 0
        if (bubbleView == null) {
            createBubble()
        } else {
            updateBadge()
        }
        return START_STICKY
    }

    private fun dp(value: Int): Int = TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP,
        value.toFloat(),
        resources.displayMetrics
    ).toInt()

    @Suppress("DEPRECATION")
    private fun createBubble() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val size = dp(56)
        val container = FrameLayout(this)

        val circle = TextView(this).apply {
            text = "A"
            setTextColor(Color.WHITE)
            textSize = 22f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                orientation = GradientDrawable.Orientation.TL_BR
                colors = intArrayOf(
                    Color.parseColor("#3A6FF8"),
                    Color.parseColor("#2F5CE0")
                )
            }
        }
        container.addView(circle, FrameLayout.LayoutParams(size, size))

        val badgeSize = dp(20)
        val badge = TextView(this).apply {
            setTextColor(Color.WHITE)
            textSize = 10f
            gravity = Gravity.CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#E5484D"))
            }
        }
        val badgeParams = FrameLayout.LayoutParams(badgeSize, badgeSize)
        badgeParams.gravity = Gravity.TOP or Gravity.END
        container.addView(badge, badgeParams)
        badgeView = badge

        bubbleView = container
        updateBadge()

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START
        params.x = dp(12)
        params.y = dp(160)
        layoutParams = params

        setupTouch(container)
        wm.addView(container, params)
    }

    private fun updateBadge() {
        val badge = badgeView ?: return
        badge.text = if (unread > 99) "99+" else unread.toString()
        badge.visibility = if (unread > 0) View.VISIBLE else View.GONE
    }

    private fun setupTouch(view: View) {
        var initialX = 0
        var initialY = 0
        var downX = 0f
        var downY = 0f
        var moved = false

        view.setOnTouchListener { _, event ->
            val params = layoutParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    downX = event.rawX
                    downY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - downX).toInt()
                    val dy = (event.rawY - downY).toInt()
                    if (abs(dx) > dp(6) || abs(dy) > dp(6)) moved = true
                    params.x = initialX + dx
                    params.y = initialY + dy
                    windowManager?.updateViewLayout(view, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (moved) snapToEdge(view) else launchApp()
                    true
                }
                else -> false
            }
        }
    }

    private fun snapToEdge(view: View) {
        val params = layoutParams ?: return
        val screenWidth = resources.displayMetrics.widthPixels
        params.x = if (params.x + view.width / 2 < screenWidth / 2) {
            dp(12)
        } else {
            screenWidth - view.width - dp(12)
        }
        windowManager?.updateViewLayout(view, params)
    }

    private fun launchApp() {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        launch?.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        )
        if (launch != null) startActivity(launch)
    }

    override fun onDestroy() {
        super.onDestroy()
        val view = bubbleView
        val wm = windowManager
        if (view != null && wm != null) {
            try {
                wm.removeView(view)
            } catch (_: Exception) {
            }
        }
        bubbleView = null
        badgeView = null
        layoutParams = null
    }
}
