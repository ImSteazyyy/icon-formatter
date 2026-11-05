package com.iconformatter.icon_formatter

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AutoSync.registerUnlock(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "listApps" -> background(result) { listApps(call.argument<Boolean>("includeSystem") ?: true) }
                "getIcons" -> background(result) { getIcons(call) }
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
                else -> result.notImplemented()
            }
        }
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
            if (ai.packageName == packageName) continue
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
                val bmp = draw(fg, size)
                val t = transparentFraction(bmp)
                if (t > 0.15 && t < 0.97) return bmp
            }
        }
        return draw(d, size)
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
        executor.shutdown()
        super.onDestroy()
    }
}
