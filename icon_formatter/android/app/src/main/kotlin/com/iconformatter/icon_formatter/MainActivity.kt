package com.iconformatter.icon_formatter

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.Drawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "icon_formatter/native"
    private val executor = Executors.newFixedThreadPool(2)
    private val main = Handler(Looper.getMainLooper())
    private var pendingTree: MethodChannel.Result? = null
    private val reqTree = 4711

    /** Display mode last written to the window (0 = no preference). */
    private var requestedMode = 0

    // Nothing OS (and other phones that pick the rate per app) keeps an app
    // that asks for nothing at its middle rate: 90 Hz on the Phone (2a) Plus,
    // while the panel can do 120. A frame rate voted from a view is clamped
    // the same way; a window naming the display mode it wants is honoured.
    // Asked while the app is on screen and released when it leaves. With no
    // frames to draw the phone still lowers the rate where its panel can.
    override fun onStart() {
        super.onStart()
        requestDisplayMode(fastestMode())
        // a key event (hardware keyboard, adb) leaves touch mode and Android
        // then rings the focused FlutterView with its default focus highlight:
        // a green frame around the whole app. Flutter draws its own focus.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            findViewById<android.view.View>(FLUTTER_VIEW_ID)?.defaultFocusHighlightEnabled = false
        }
    }

    override fun onStop() {
        requestDisplayMode(0)
        super.onStop()
    }

    /** The fastest mode at the current resolution (a different resolution would be a resolution change). */
    @Suppress("DEPRECATION")
    private fun fastestMode(): Int {
        val display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay) ?: return 0
        val current = display.mode
        return display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate }?.modeId ?: 0
    }

    private fun requestDisplayMode(modeId: Int) {
        if (modeId == requestedMode) return
        requestedMode = modeId
        runCatching {
            val attrs = window.attributes
            attrs.preferredDisplayModeId = modeId
            window.attributes = attrs
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AutoSync.registerUnlock(applicationContext)
        // ask Shizuku permission once when Shizuku is running and it is missing
        rikka.shizuku.Shizuku.addBinderReceivedListenerSticky(shizukuBinder)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "listApps" -> background(result) { listApps(call.argument<Boolean>("includeSystem") ?: true) }
                "getIcons" -> background(result) { getIcons(call) }
                "appCatalog" -> background(result) {
                    appCatalog(call.argument<String>("dir")!!, (call.argument<Int>("size") ?: 432).coerceIn(48, 1024))
                }
                "pickTree" -> pickTree(result)
                "writeDirToTree" -> background(result) {
                    writeDirToTree(call.argument<String>("treeUri")!!, call.argument<String>("srcDir")!!, call.argument<String>("subfolder"))
                }
                "copyTreeToDir" -> background(result) {
                    copyTreeToDir(call.argument<String>("treeUri")!!, call.argument<String>("destDir")!!)
                }
                "autoSyncStatus" -> background(result) { AutoSync.status(applicationContext) }
                "autoSyncSetEnabled" -> {
                    val on = call.argument<Boolean>("enabled") ?: false
                    if (on && Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 4712)
                    }
                    background(result) { AutoSync.setEnabled(applicationContext, on); AutoSync.status(applicationContext) }
                }
                "autoSyncCheckNow" -> background(result) { AutoSync.check(applicationContext, notify = false); AutoSync.status(applicationContext) }
                "autoSyncClear" -> background(result) { AutoSync.clearPending(applicationContext, call.argument<List<String>>("components")); true }
                "takeLaunchAction" -> {
                    val open = intent?.getBooleanExtra("openBuilder", false) ?: false
                    intent?.removeExtra("openBuilder")
                    result.success(if (open) "builder" else null)
                }
                "openHomeSettings" -> {
                    // launcher settings (icon pack choice lives there on most launchers)
                    val i = Intent(android.provider.Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    result.success(try { startActivity(i); true } catch (e: Exception) { false })
                }
                "shizukuState" -> result.success(DevicePack.shizukuState(applicationContext))
                "shizukuRequest" -> result.success(DevicePack.requestShizukuIfNeeded(force = true))
                "openShizuku" -> result.success(DevicePack.openShizuku(this))
                "devicePackInfo" -> background(result) {
                    mapOf(
                        "shizuku" to DevicePack.shizukuState(applicationContext),
                        "launcher" to DevicePack.launcherInstalled(applicationContext),
                        "installed" to (DevicePack.installedVersion(applicationContext) != null),
                        "version" to DevicePack.installedVersionName(applicationContext),
                        "package" to DevicePack.PACKAGE,
                        "selector" to try { DevicePack.currentSelector() } catch (_: Exception) { null },
                    )
                }
                "devicePackBuild" -> background(result) {
                    val built = DevicePack.build(
                        applicationContext,
                        call.argument<String>("packDir")!!,
                        call.argument<String>("name") ?: "Icon Formatter Pack",
                        call.argument<String>("accent") ?: "#BA4CD4",
                    )
                    mapOf("apk" to built.apk.absolutePath, "count" to built.count, "version" to built.versionName)
                }
                "devicePackInstall" -> background(result) {
                    val apk = File(call.argument<String>("apk")!!)
                    if (call.argument<Boolean>("shizuku") == true) {
                        DevicePack.installShizuku(applicationContext, apk)
                    } else {
                        DevicePack.installSession(this, apk); "pending"
                    }
                }
                "devicePackApply" -> background(result) { DevicePack.apply(this) }
                "devicePackSource" -> background(result) { DevicePack.installedSource(applicationContext) }
                "devicePackArchiveInfo" -> background(result) { DevicePack.archiveInfo(applicationContext, call.argument<String>("path")!!) }
                "devicePackUninstall" -> background(result) { DevicePack.uninstallShizuku(applicationContext); true }
                "devicePackRestore" -> background(result) { DevicePack.restore(applicationContext) }
                "openNothingPicker" -> result.success(DevicePack.openPicker(this))
                else -> result.notImplemented()
            }
        }
    }

    private val shizukuBinder = rikka.shizuku.Shizuku.OnBinderReceivedListener {
        main.post { DevicePack.requestShizukuIfNeeded() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        executor.execute {
            try {
                val v = work()
                main.post { result.success(v) }
            } catch (e: Exception) {
                main.post { result.error("native_error", e.message ?: e.toString(), null) }
            }
        }
    }

    // ------------------------------------------------------------- installed apps

    /** Launcher activities visible through the <queries> MAIN/LAUNCHER intent (no QUERY_ALL_PACKAGES). */
    private fun listApps(includeSystem: Boolean): List<Map<String, Any?>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val infos = if (Build.VERSION.SDK_INT >= 33) {
            pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            pm.queryIntentActivities(intent, 0)
        }
        val out = ArrayList<Map<String, Any?>>()
        for (ri in infos) {
            val ai = ri.activityInfo ?: continue
            val appInfo = ai.applicationInfo
            val isSystem = (appInfo.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                (appInfo.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
            if (!includeSystem && isSystem) continue
            var adaptive = false
            var mono = false
            try {
                val d = ri.loadIcon(pm)
                if (Build.VERSION.SDK_INT >= 26 && d is AdaptiveIconDrawable) {
                    adaptive = true
                    if (Build.VERSION.SDK_INT >= 33) mono = d.monochrome != null
                }
            } catch (_: Exception) {
            }
            out.add(
                mapOf(
                    "label" to (ri.loadLabel(pm)?.toString() ?: ai.packageName),
                    "package" to ai.packageName,
                    "activity" to ai.name,
                    "isSystem" to isSystem,
                    "isAdaptive" to adaptive,
                    "hasMonochrome" to mono,
                )
            )
        }
        out.sortBy { (it["label"] as String).lowercase() }
        return out
    }

    /**
     * Pack catalogue: every launcher activity (system apps, Icon Formatter and
     * its packs included) with its full icon cached as a PNG file in [dir].
     * A file is reused while the app is not updated (lastUpdateTime in the
     * name), so later opens only list the apps. Icons are rendered on a small
     * pool, off the UI thread.
     */
    private fun appCatalog(dir: String, size: Int): Map<String, Any?> {
        val apps = listApps(true)
        val d = File(dir).apply { mkdirs() }
        val pm = packageManager
        val keep = HashSet<String>()
        val pool = Executors.newFixedThreadPool(maxOf(2, minOf(4, Runtime.getRuntime().availableProcessors() - 1)))
        val out = apps.map { a ->
            val pkg = a["package"] as String
            val act = a["activity"] as String
            val updated = try { pm.getPackageInfo(pkg, 0).lastUpdateTime } catch (_: Exception) { 0L }
            val name = "${pkg}__${Integer.toHexString(act.hashCode())}_${updated}_$size.png"
            keep.add(name)
            val f = File(d, name)
            pool.submit<Map<String, Any?>> {
                var ok = f.exists() && f.length() > 0
                if (!ok) {
                    try {
                        val icon = pm.getActivityIcon(ComponentName(pkg, act))
                        val tmp = File(d, "$name.tmp")
                        tmp.writeBytes(png(renderIcon(icon, size, false)))
                        ok = tmp.renameTo(f)
                    } catch (_: Exception) {
                    }
                }
                a + mapOf("icon" to (if (ok) f.absolutePath else null))
            }
        }.map { it.get() }
        pool.shutdown()
        // icons of uninstalled / updated apps are removed from the cache
        d.listFiles()?.forEach { if (it.name !in keep) it.delete() }
        return mapOf("apps" to out, "visible" to apps.size)
    }

    private fun getIcons(call: MethodCall): List<ByteArray?> {
        val items = call.argument<List<Map<String, String>>>("items") ?: emptyList()
        val size = (call.argument<Int>("size") ?: 432).coerceIn(48, 1024)
        val glyphOnly = call.argument<Boolean>("glyphOnly") ?: true
        val pm = packageManager
        return items.map { m ->
            try {
                val pkg = m["package"]!!
                val act = m["activity"] ?: ""
                val d: Drawable = if (act.isNotEmpty()) pm.getActivityIcon(ComponentName(pkg, act)) else pm.getApplicationIcon(pkg)
                png(renderIcon(d, size, glyphOnly))
            } catch (e: Exception) {
                null
            }
        }
    }

    /**
     * Adaptive icons: the foreground layer alone is the glyph when it has real
     * transparency; it is drawn over the full 108dp canvas. Otherwise the
     * complete icon (with the system mask) is drawn and segmented in Rust.
     */
    private fun renderIcon(d: Drawable, size: Int, glyphOnly: Boolean): Bitmap {
        if (glyphOnly && Build.VERSION.SDK_INT >= 26 && d is AdaptiveIconDrawable) {
            val fg = d.foreground
            val bg = d.background
            // The foreground alone is the glyph only when it really has content
            // and the background layer is a plain colour/gradient; otherwise the
            // background carries part of the logo identity (e.g. a clock face).
            if (fg != null && (bg == null || isPlainLayer(bg))) {
                // the foreground as the launcher shows it: the central 72dp of
                // the 108dp layer, clipped by the system mask (artwork outside
                // the mask, e.g. KFC stripes or Contacts tabs, is never visible)
                val mask = maskBitmap(d, size)
                val bmp = drawLayerMasked(d, fg, mask, size)
                val (cover, edge) = maskStats(bmp, mask)
                // a real glyph: some content, plenty of empty plate, and not
                // artwork that bleeds into the mask edge (that is a full-bleed
                // design: the whole icon goes to Rust and is handled as a tile)
                if (cover > 0.02 && cover < 0.80 && edge < 0.06) return bmp
            }
        }
        return draw(d, size)
    }

    /** Alpha mask (0..255) of the adaptive icon's system shape at `size`. */
    private fun maskBitmap(d: AdaptiveIconDrawable, size: Int): Bitmap {
        d.setBounds(0, 0, size, size)
        val m = Bitmap.createBitmap(size, size, Bitmap.Config.ALPHA_8)
        Canvas(m).drawPath(d.iconMask, Paint(Paint.ANTI_ALIAS_FLAG))
        return m
    }

    /** `layer` drawn like AdaptiveIconDrawable does (layer bounds 1.5x the icon), anti-aliased mask applied. */
    private fun drawLayerMasked(d: AdaptiveIconDrawable, layer: Drawable, mask: Bitmap, size: Int): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        val old = layer.copyBounds()
        val inset = size / 4
        layer.setBounds(-inset, -inset, size + inset, size + inset)
        layer.draw(c)
        layer.bounds = old
        c.drawBitmap(mask, 0f, 0f, Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) })
        return bmp
    }

    /**
     * Share of the mask covered by the layer, and share of the mask's edge band
     * (pixels within 3% of the outline) where the layer is opaque.
     */
    private fun maskStats(b: Bitmap, mask: Bitmap): Pair<Double, Double> {
        val s = b.width
        val px = IntArray(s * s).also { b.getPixels(it, 0, s, 0, 0, s, s) }
        val buf = java.nio.ByteBuffer.allocate(mask.rowBytes * mask.height)
        mask.copyPixelsToBuffer(buf)
        val mb = buf.array()
        val rb = mask.rowBytes
        fun m(x: Int, y: Int): Int = if (x < 0 || y < 0 || x >= s || y >= s) 0 else mb[y * rb + x].toInt() and 0xff
        val e = maxOf(2, (s * 0.03).toInt())
        var inMask = 0
        var covered = 0
        var band = 0
        var bandHit = 0
        for (y in 0 until s step 2) {
            for (x in 0 until s step 2) {
                if (m(x, y) < 200) continue
                inMask++
                val opaque = (px[y * s + x] ushr 24) > 128
                if (opaque) covered++
                if (m(x - e, y) < 128 || m(x + e, y) < 128 || m(x, y - e) < 128 || m(x, y + e) < 128) {
                    band++
                    if (opaque) bandHit++
                }
            }
        }
        return Pair(if (inMask == 0) 0.0 else covered.toDouble() / inMask, if (band == 0) 0.0 else bandHit.toDouble() / band)
    }

    /** True when a layer is a flat colour or smooth gradient (low local detail). */
    private fun isPlainLayer(layer: Drawable): Boolean {
        val s = 48
        val b = draw(layer, s)
        var detail = 0.0
        var n = 0
        for (y in 1 until s) {
            for (x in 1 until s) {
                val p = b.getPixel(x, y)
                val l = b.getPixel(x - 1, y)
                val u = b.getPixel(x, y - 1)
                fun ch(c: Int, sh: Int) = (c shr sh) and 0xff
                var dmax = 0
                for (sh in intArrayOf(16, 8, 0)) {
                    dmax = maxOf(dmax, kotlin.math.abs(ch(p, sh) - ch(l, sh)), kotlin.math.abs(ch(p, sh) - ch(u, sh)))
                }
                if (dmax > 24) detail++
                n++
            }
        }
        return detail / n < 0.02
    }

    private fun draw(d: Drawable, size: Int): Bitmap {
        val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        d.setBounds(0, 0, size, size)
        d.draw(c)
        return bmp
    }

    private fun transparentFraction(b: Bitmap): Double {
        val step = 4
        var t = 0
        var n = 0
        var y = 0
        while (y < b.height) {
            var x = 0
            while (x < b.width) {
                if ((b.getPixel(x, y) ushr 24) < 16) t++
                n++
                x += step
            }
            y += step
        }
        return if (n == 0) 0.0 else t.toDouble() / n
    }

    private fun png(b: Bitmap): ByteArray {
        val s = ByteArrayOutputStream()
        b.compress(Bitmap.CompressFormat.PNG, 100, s)
        return s.toByteArray()
    }

    // ------------------------------------------------------------- Storage Access Framework

    private fun pickTree(result: MethodChannel.Result) {
        if (pendingTree != null) {
            result.error("busy", "folder picker already open", null)
            return
        }
        pendingTree = result
        val i = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        )
        startActivityForResult(i, reqTree)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == reqTree) {
            val r = pendingTree
            pendingTree = null
            val uri = data?.data
            if (resultCode == Activity.RESULT_OK && uri != null) {
                try {
                    contentResolver.takePersistableUriPermission(
                        uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                } catch (_: Exception) {
                }
                r?.success(uri.toString())
            } else {
                r?.success(null)
            }
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun uniqueName(dir: DocumentFile, name: String): String {
        if (dir.findFile(name) == null) return name
        val dot = name.lastIndexOf('.')
        val stem = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 1
        while (dir.findFile("$stem ($i)$ext") != null) i++
        return "$stem ($i)$ext"
    }

    private fun mime(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "png" -> "image/png"
        "xml" -> "text/xml"
        "json" -> "application/json"
        "zip" -> "application/zip"
        "txt" -> "text/plain"
        else -> "application/octet-stream"
    }

    private fun writeDirToTree(treeUri: String, srcDir: String, subfolder: String?): Int {
        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri)) ?: throw IllegalStateException("invalid folder")
        var target = root
        if (!subfolder.isNullOrEmpty()) {
            target = root.createDirectory(uniqueName(root, subfolder)) ?: throw IllegalStateException("cannot create folder")
        }
        return copyDir(File(srcDir), target)
    }

    private fun copyDir(src: File, dst: DocumentFile): Int {
        var n = 0
        val children = src.listFiles()?.sortedBy { it.name } ?: return 0
        for (f in children) {
            if (f.isDirectory) {
                val sub = dst.findFile(f.name)?.takeIf { it.isDirectory } ?: dst.createDirectory(f.name) ?: continue
                n += copyDir(f, sub)
            } else {
                val name = uniqueName(dst, f.name)
                val doc = dst.createFile(mime(f.name), name) ?: continue
                contentResolver.openOutputStream(doc.uri)?.use { out -> f.inputStream().use { it.copyTo(out) } }
                n++
            }
        }
        return n
    }

    private fun copyTreeToDir(treeUri: String, destDir: String): Int {
        val root = DocumentFile.fromTreeUri(this, Uri.parse(treeUri)) ?: throw IllegalStateException("invalid folder")
        val dest = File(destDir)
        dest.mkdirs()
        return copyTree(root, dest)
    }

    private fun copyTree(src: DocumentFile, dest: File): Int {
        var n = 0
        for (f in src.listFiles()) {
            val name = f.name ?: continue
            if (f.isDirectory) {
                n += copyTree(f, File(dest, name).apply { mkdirs() })
            } else {
                contentResolver.openInputStream(f.uri)?.use { inp -> File(dest, name).outputStream().use { inp.copyTo(it) } }
                n++
            }
        }
        return n
    }

    override fun onDestroy() {
        rikka.shizuku.Shizuku.removeBinderReceivedListener(shizukuBinder)
        executor.shutdown()
        super.onDestroy()
    }
}
