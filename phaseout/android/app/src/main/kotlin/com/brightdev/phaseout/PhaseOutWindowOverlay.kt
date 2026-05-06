// ─────────────────────────────────────────────────────────────
//  PhaseOutWindowOverlay.kt  — v4
//  RULE: Never assign view.layoutParams — always pass params
//        as the second argument to parent.addView(child, params)
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.content.Context
import android.content.Intent
import android.graphics.*
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.*
import android.widget.*

object PhaseOutWindowOverlay {

    private const val TAG             = "PhaseOut.Overlay"
    private const val AUTO_DISMISS_MS = 15_000L

    private var windowManager:   WindowManager? = null
    private var overlayView:     View?          = null
    private val handler          = Handler(Looper.getMainLooper())
    private var dismissRunnable: Runnable?      = null

    // ── Show ──────────────────────────────────────────────────
    fun show(context: Context, blockedPackage: String) {
        if (!canDraw(context)) { Log.w(TAG, "SYSTEM_ALERT_WINDOW not granted"); return }
        if (overlayView != null) { Log.d(TAG, "Already showing"); return }
        try {
            val wm   = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            windowManager = wm
            val view = buildView(context, blockedPackage)
            overlayView  = view

            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_FULLSCREEN,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.TOP or Gravity.START
            wm.addView(view, params)
            Log.i(TAG, "Overlay shown: $blockedPackage")

            val r = Runnable { dismiss(); goHome(context) }
            dismissRunnable = r
            handler.postDelayed(r, AUTO_DISMISS_MS)

        } catch (e: Exception) {
            Log.e(TAG, "show failed: ${e.message}")
            overlayView   = null
            windowManager = null
        }
    }

    // ── Dismiss ───────────────────────────────────────────────
    fun dismiss() {
        dismissRunnable?.let { handler.removeCallbacks(it) }
        dismissRunnable = null
        try { overlayView?.let { windowManager?.removeView(it) } }
        catch (e: Exception) { Log.e(TAG, "dismiss: ${e.message}") }
        finally { overlayView = null; windowManager = null }
    }

    fun isShowing() = overlayView != null

    fun canDraw(context: Context): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            Settings.canDrawOverlays(context)
        else true

    private fun goHome(context: Context) {
        try {
            context.startActivity(Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        } catch (e: Exception) { Log.e(TAG, "goHome: ${e.message}") }
    }

    // ── Build view ────────────────────────────────────────────
    // Rule: every addView call includes explicit LayoutParams.
    // No view.layoutParams = ... anywhere in this file.
    private fun buildView(context: Context, blockedPackage: String): View {
        val MATCH = LinearLayout.LayoutParams.MATCH_PARENT
        val WRAP  = LinearLayout.LayoutParams.WRAP_CONTENT
        val margin = dpToPx(context, 30)

        // Root: FrameLayout fills window
        val root = FrameLayout(context)
        root.setBackgroundColor(Color.argb(236, 4, 13, 26))

        // Content: vertical LinearLayout centred in root
        val content = LinearLayout(context)
        content.orientation = LinearLayout.VERTICAL
        content.gravity     = Gravity.CENTER_HORIZONTAL

        // ── Moon ────────────────────────────────────────────
        val moonSz   = dpToPx(context, 106)
        val moonView = object : View(context) {
            override fun onDraw(canvas: Canvas) {
                val w  = width.toFloat()
                val h  = height.toFloat()
                val cx = w / 2; val cy = h / 2

                // Glow
                canvas.drawCircle(cx, cy, w * 0.46f, Paint().apply {
                    color      = Color.argb(28, 96, 165, 250)
                    maskFilter = BlurMaskFilter(56f, BlurMaskFilter.Blur.NORMAL)
                })
                // Body
                canvas.drawCircle(cx, cy, w * 0.36f,
                    Paint().apply { color = Color.argb(230, 232, 240, 255); isAntiAlias = true })
                // Crescent cutout
                canvas.drawCircle(cx + w*0.13f, cy - h*0.09f, w*0.28f,
                    Paint().apply { color = Color.argb(255, 4, 13, 26); isAntiAlias = true })
                // Eyes
                val eye = Paint().apply { color = Color.argb(190, 10, 24, 40); isAntiAlias = true }
                canvas.drawCircle(cx - w*0.09f, cy - h*0.03f, w*0.03f,  eye)
                canvas.drawCircle(cx,            cy - h*0.05f, w*0.025f, eye)
                // Smile
                canvas.drawArc(
                    RectF(cx - w*0.08f, cy + h*0.03f, cx + w*0.02f, cy + h*0.11f),
                    0f, 180f, false,
                    Paint().apply {
                        color       = Color.argb(190, 10, 24, 40)
                        style       = Paint.Style.STROKE
                        strokeWidth = w * 0.024f
                        strokeCap   = Paint.Cap.ROUND
                        isAntiAlias = true
                    })
                // Stars
                val star = Paint().apply { color = Color.argb(160, 96, 165, 250); isAntiAlias = true }
                canvas.drawCircle(cx + w*0.42f, cy - h*0.28f, w*0.024f, star)
                canvas.drawCircle(cx - w*0.38f, cy - h*0.18f, w*0.018f, star)
            }
        }
        content.addView(moonView,
            LinearLayout.LayoutParams(moonSz, moonSz).also { it.gravity = Gravity.CENTER_HORIZONTAL })

        // ── Spacer ─────────────────────────────────────────
        content.addView(View(context),
            LinearLayout.LayoutParams(MATCH, dpToPx(context, 24)))

        // ── Blocked chip ────────────────────────────────────
        val appName = blockedPackage.split(".").last().let {
            if (it.isEmpty()) blockedPackage else it[0].uppercaseChar() + it.substring(1)
        }
        val chip = LinearLayout(context)
        chip.orientation = LinearLayout.HORIZONTAL
        chip.gravity     = Gravity.CENTER
        chip.setPadding(dpToPx(context,12), dpToPx(context,5), dpToPx(context,12), dpToPx(context,5))
        chip.background  = GradientDrawable().apply {
            setColor(Color.argb(28, 239, 68, 68))
            cornerRadius = dpToPx(context, 99).toFloat()
        }
        val chipLabel = TextView(context)
        chipLabel.text     = "$appName is blocked"
        chipLabel.textSize = 12f
        chipLabel.setTextColor(Color.argb(255, 239, 68, 68))
        chipLabel.typeface = Typeface.DEFAULT_BOLD
        chip.addView(chipLabel,
            LinearLayout.LayoutParams(WRAP, WRAP))
        content.addView(chip,
            LinearLayout.LayoutParams(WRAP, WRAP).also { it.gravity = Gravity.CENTER_HORIZONTAL })

        // ── Spacer ─────────────────────────────────────────
        content.addView(View(context),
            LinearLayout.LayoutParams(MATCH, dpToPx(context, 14)))

        // ── Title ──────────────────────────────────────────
        val title = TextView(context)
        title.text     = "Stay focused."
        title.textSize = 28f
        title.setTextColor(Color.WHITE)
        title.gravity  = Gravity.CENTER
        content.addView(title, LinearLayout.LayoutParams(MATCH, WRAP))

        // ── Spacer ─────────────────────────────────────────
        content.addView(View(context),
            LinearLayout.LayoutParams(MATCH, dpToPx(context, 8)))

        // ── Subtitle ────────────────────────────────────────
        val subtitle = TextView(context)
        subtitle.text     = "This app is blocked during your\nfocus session.\nReturning to home in 15 seconds."
        subtitle.textSize = 13f
        subtitle.setTextColor(Color.argb(130, 255, 255, 255))
        subtitle.gravity = Gravity.CENTER
        subtitle.setLineSpacing(0f, 1.4f)
        content.addView(subtitle, LinearLayout.LayoutParams(MATCH, WRAP))

        // ── Spacer ─────────────────────────────────────────
        content.addView(View(context),
            LinearLayout.LayoutParams(MATCH, dpToPx(context, 32)))

        // ── Open PhaseOut button ─────────────────────────────
        val openBtn = makeButton(context, "Open PhaseOut",
            Color.argb(38, 96, 165, 250), Color.argb(255, 147, 197, 253))
        openBtn.setOnClickListener {
            val i = context.packageManager.getLaunchIntentForPackage(context.packageName)
            i?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            i?.let { context.startActivity(it) }
            dismiss()
        }
        content.addView(openBtn,
            LinearLayout.LayoutParams(MATCH, WRAP).also {
                it.leftMargin  = margin
                it.rightMargin = margin
            })

        // ── Spacer ─────────────────────────────────────────
        content.addView(View(context),
            LinearLayout.LayoutParams(MATCH, dpToPx(context, 10)))

        // ── Go home button ──────────────────────────────────
        val homeBtn = makeButton(context, "Go to home screen",
            Color.argb(20, 255, 255, 255), Color.argb(100, 255, 255, 255))
        homeBtn.setOnClickListener { dismiss(); goHome(context) }
        content.addView(homeBtn,
            LinearLayout.LayoutParams(MATCH, WRAP).also {
                it.leftMargin  = margin
                it.rightMargin = margin
            })

        // ── Add content to root ─────────────────────────────
        root.addView(content,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER
            ))

        return root
    }

    // Returns a plain TextView — no layoutParams set on it.
    // Caller passes LayoutParams to addView().
    private fun makeButton(ctx: Context, label: String, bg: Int, fg: Int): TextView {
        val tv = TextView(ctx)
        tv.text     = label
        tv.textSize = 14f
        tv.setTextColor(fg)
        tv.gravity  = Gravity.CENTER
        tv.typeface = Typeface.DEFAULT_BOLD
        tv.setPadding(0, dpToPx(ctx, 14), 0, dpToPx(ctx, 14))
        tv.background = GradientDrawable().apply {
            setColor(bg)
            cornerRadius = dpToPx(ctx, 13).toFloat()
            setStroke(1, Color.argb(80, 96, 165, 250))
        }
        return tv
    }

    private fun dpToPx(ctx: Context, dp: Int): Int =
        (dp * ctx.resources.displayMetrics.density).toInt()
}