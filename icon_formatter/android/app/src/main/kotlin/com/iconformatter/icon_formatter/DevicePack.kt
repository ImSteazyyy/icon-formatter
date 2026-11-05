package com.iconformatter.icon_formatter

import android.app.Activity
import android.app.ActivityOptions
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Xml
import com.android.apksig.ApkSigner
import io.flutter.FlutterInjector
import org.json.JSONArray
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import rikka.shizuku.Shizuku
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

/**
 * Builds the icon pack APK on the phone and applies it to Nothing Launcher.
 *
 * The pack is its own app ([PACKAGE]); the system packs are never touched.
 * Build: assets/iconpack_base.apk (template with empty drawable slots, see
 * tool/make_base_apk.py) gets the pack PNGs, binary appfilter/drawable XML,
 * mapping.json and pack.json, then is signed with apksig using a key kept in
 * the Android Keystore (same key every time, so updates install in place).
 *
 * Apply (same sequence as Nothing IconGen's IconPackSelector, but through
 * Shizuku's shell identity instead of a targetSdk 22 build): install with
 * `pm install`, open Nothing Launcher's icon pack picker behind our task so
 * it re-parses external packs, then write Settings.System `nothing_icon_pack`
 * to THEMED_ICONS_NOTHING and back to [PACKAGE] 500 ms later.
 */
object DevicePack {
    const val PACKAGE = "com.iconformatter.pack.device"
    const val NOTHING_LAUNCHER = "com.nothing.launcher"
    private const val SELECTOR = "nothing_icon_pack"
    private const val TEMPORARY_PACK = "THEMED_ICONS_NOTHING"
    private const val KEY_ALIAS = "iconformatter_pack"
    private const val PREFS = "device_pack"
    private const val SHIZUKU_PACKAGE = "moe.shizuku.privileged.api"
    private const val REQ_SHIZUKU = 4713

    // ---------------------------------------------------------------- Shizuku

    /** missing | stopped | denied | granted | old */
    fun shizukuState(context: Context): String {
        val installed = try {
            context.packageManager.getPackageInfo(SHIZUKU_PACKAGE, 0); true
        } catch (_: PackageManager.NameNotFoundException) {
            false
        }
        if (!Shizuku.pingBinder()) return if (installed) "stopped" else "missing"
        if (Shizuku.isPreV11()) return "old"
        return if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) "granted" else "denied"
    }

    private var askedThisRun = false

    /** Asks for Shizuku permission once per app run when Shizuku is running. */
    fun requestShizukuIfNeeded(force: Boolean = false): Boolean {
        if (!Shizuku.pingBinder() || Shizuku.isPreV11()) return false
        if (Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) return true
        if (!force && (askedThisRun || Shizuku.shouldShowRequestPermissionRationale())) return false
        askedThisRun = true
        Shizuku.requestPermission(REQ_SHIZUKU)
        return false
    }

    fun openShizuku(context: Context): Boolean {
        val i = context.packageManager.getLaunchIntentForPackage(SHIZUKU_PACKAGE) ?: return false
        context.startActivity(i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return true
    }

    /** Runs a shell command as Shizuku's user (shell/adb). */
    private fun shell(cmd: String, stdin: InputStream? = null): Pair<Int, String> {
        check(Shizuku.pingBinder()) { "Shizuku non è attivo" }
        check(Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED) { "Permesso Shizuku non concesso" }
        // newProcess is hidden in the public API since v12; reflection is the
        // documented-by-practice way for one-shot shell commands.
        val m = Shizuku::class.java.getDeclaredMethod(
            "newProcess", Array<String>::class.java, Array<String>::class.java, String::class.java,
        )
        m.isAccessible = true
        val p = m.invoke(null, arrayOf("sh", "-c", cmd), null, null) as Process
        if (stdin != null) {
            p.outputStream.use { out -> stdin.copyTo(out) }
        } else {
            p.outputStream.close()
        }
        val out = p.inputStream.bufferedReader().readText() + p.errorStream.bufferedReader().readText()
        val code = p.waitFor()
        return code to out.trim()
    }

    // ------------------------------------------------------------------ build

    /**
     * Fills the base APK with the pack in [packDir] (output of build_icon_pack:
     * PNGs in res/drawable-nodpi, res/xml/appfilter.xml, res/xml/drawable.xml,
     * mapping.json). Returns the signed APK and the number of icons.
     */
    class Built(val apk: File, val count: Int, val versionName: String)

    fun build(context: Context, packDir: String, name: String, accent: String): Built {
        val (vCode, vName) = nextVersion(context)
        val dir = File(packDir)
        val pngs = File(dir, "res/drawable-nodpi").listFiles { f -> f.name.endsWith(".png") }?.sortedBy { it.name } ?: emptyList()
        val work = File(context.cacheDir, "devicepack").apply { deleteRecursively(); mkdirs() }
        val base = File(work, "base.apk")
        val key = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset("assets/iconpack_base.apk")
        context.assets.open(key).use { inp -> base.outputStream().use { inp.copyTo(it) } }

        ZipFile(base).use { zip ->
            val slotEntries = zip.entries().asSequence().map { it.name }
                .filter { it.startsWith("res/") && it.substringAfterLast('/').startsWith("slot_") && it.endsWith(".png") }
                .associateBy { it.substringAfterLast('/').removeSuffix(".png") }
            check(pngs.size <= slotEntries.size) {
                "Il pack ha ${pngs.size} icone, il massimo sul telefono è ${slotEntries.size}"
            }
            // drawable name -> slot name
            val rename = HashMap<String, String>()
            val fileFor = HashMap<String, File>()
            pngs.forEachIndexed { i, f ->
                val slot = "slot_%04d".format(i)
                rename[f.name.removeSuffix(".png")] = slot
                fileFor[slotEntries[slot] ?: error("slot $slot mancante")] = f
            }
            val appfilter = File(dir, "res/xml/appfilter.xml").takeIf { it.exists() }?.let { compileXml(it.readText(), rename) }
            val drawableXml = File(dir, "res/xml/drawable.xml").takeIf { it.exists() }?.let { compileXml(it.readText(), rename) }
            val appfilterText = File(dir, "res/xml/appfilter.xml").takeIf { it.exists() }?.readText()?.let { renameText(it, rename) }
            val mapping = File(dir, "mapping.json").takeIf { it.exists() }?.readText()?.let { txt ->
                val arr = JSONArray(txt)
                for (k in 0 until arr.length()) {
                    val o = arr.getJSONObject(k)
                    rename[o.optString("drawable")]?.let { o.put("drawable", it) }
                }
                arr.toString()
            } ?: "[]"
            val meta = JSONObject().put("name", name).put("accent", accent).toString()

            val unsigned = File(work, "unsigned.apk")
            ZipOutputStream(unsigned.outputStream().buffered()).use { out ->
                val written = HashSet<String>()
                fun put(entryName: String, bytes: ByteArray, store: Boolean) {
                    val e = ZipEntry(entryName)
                    if (store) {
                        e.method = ZipEntry.STORED
                        e.size = bytes.size.toLong()
                        e.compressedSize = bytes.size.toLong()
                        e.crc = CRC32().apply { update(bytes) }.value
                    }
                    out.putNextEntry(e)
                    out.write(bytes)
                    out.closeEntry()
                    written.add(entryName)
                }
                for (e in zip.entries()) {
                    val n = e.name
                    if (n.startsWith("META-INF/") && (n.endsWith(".SF") || n.endsWith(".RSA") || n.endsWith(".EC") || n.endsWith("MANIFEST.MF"))) continue
                    val bytes = when {
                        fileFor.containsKey(n) -> fileFor[n]!!.readBytes()
                        n == "res/xml/appfilter.xml" && appfilter != null -> appfilter
                        n == "res/xml/drawable.xml" && drawableXml != null -> drawableXml
                        n == "assets/mapping.json" -> mapping.toByteArray()
                        n == "AndroidManifest.xml" -> patchManifest(zip.getInputStream(e).use { it.readBytes() }, vCode, vName)
                        else -> zip.getInputStream(e).use { it.readBytes() }
                    }
                    put(n, bytes, e.method == ZipEntry.STORED)
                }
                if (appfilterText != null) put("assets/appfilter.xml", appfilterText.toByteArray(), true)
                put("assets/pack.json", meta.toByteArray(), true)
            }
            val signed = File(work, "IconFormatterPack.apk")
            sign(unsigned, signed)
            unsigned.delete()
            base.delete()
            return Built(signed, pngs.size, vName)
        }
    }

    /**
     * Next pack version: the highest known versionCode + 1 (1.0, 1.1, ...).
     * "Known" includes a pack opened from another phone or replaced after a
     * signature change, so the numbering continues across devices.
     */
    fun nextVersion(context: Context): Pair<Int, String> {
        val installed = installedVersionCode(context) ?: 0
        val known = prefs(context).getInt("minVersion", 0)
        val code = maxOf(1, maxOf(installed, known) + 1)
        return code to versionName(code)
    }

    private fun prefs(context: Context) = context.getSharedPreferences("device_pack", Context.MODE_PRIVATE)

    fun installedVersionCode(context: Context): Int? = try {
        @Suppress("DEPRECATION")
        context.packageManager.getPackageInfo(PACKAGE, 0).versionCode
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    /** Remembers a version seen elsewhere (next builds continue after it). */
    fun rememberVersion(context: Context, code: Int) {
        val p = prefs(context)
        if (code > p.getInt("minVersion", 0)) p.edit().putInt("minVersion", code).apply()
    }

    /** APK of the installed pack (readable by apps), or null. */
    fun installedSource(context: Context): String? = try {
        context.packageManager.getApplicationInfo(PACKAGE, 0).sourceDir
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    /**
     * Package and versionCode of a pack APK file; a pack of this app (same
     * package) makes the next build continue its numbering.
     */
    fun archiveInfo(context: Context, path: String): Map<String, Any?> {
        @Suppress("DEPRECATION")
        val pi = context.packageManager.getPackageArchiveInfo(path, 0)
        @Suppress("DEPRECATION")
        val code = pi?.versionCode ?: 0
        if (pi?.packageName == PACKAGE) rememberVersion(context, code)
        return mapOf("package" to pi?.packageName, "version" to pi?.versionName, "code" to code)
    }

    /**
     * Removes the installed pack (Shizuku). Used only after the user agreed,
     * when it was signed on another phone and cannot be updated in place;
     * its version is remembered so the numbering goes on.
     */
    fun uninstallShizuku(context: Context) {
        installedVersionCode(context)?.let { rememberVersion(context, it) }
        val (code, out) = shell("pm uninstall $PACKAGE")
        check(code == 0 && out.contains("Success")) { "pm uninstall: $out" }
    }

    fun versionName(code: Int): String = "${1 + (code - 1) / 10}.${(code - 1) % 10}"

    /**
     * Sets android:versionCode / android:versionName in a binary
     * AndroidManifest.xml. The string pool is rebuilt (UTF-8) with the new
     * name; every other chunk is kept byte for byte.
     */
    fun patchManifest(axml: ByteArray, code: Int, name: String): ByteArray {
        val b = ByteBuffer.wrap(axml).order(ByteOrder.LITTLE_ENDIAN)
        check(b.getShort(0).toInt() == 0x0003) { "manifest non valido" }
        var pos = b.getShort(2).toInt()
        var strings = mutableListOf<String>()
        var poolStart = -1
        var poolEnd = -1
        var resIds = IntArray(0)
        val chunks = ArrayList<IntArray>() // start, size
        while (pos + 8 <= axml.size) {
            val type = b.getShort(pos).toInt() and 0xffff
            val size = b.getInt(pos + 4)
            if (size < 8) break
            when (type) {
                0x0001 -> {
                    poolStart = pos; poolEnd = pos + size
                    val count = b.getInt(pos + 8)
                    val utf8 = (b.getInt(pos + 16) and 0x100) != 0
                    val sStart = pos + b.getInt(pos + 20)
                    for (i in 0 until count) {
                        var p = sStart + b.getInt(pos + b.getShort(pos + 2) + i * 4)
                        if (utf8) {
                            fun len(): Int {
                                val a = axml[p].toInt() and 0xff
                                return if (a and 0x80 != 0) { val v = ((a and 0x7f) shl 8) or (axml[p + 1].toInt() and 0xff); p += 2; v } else { p += 1; a }
                            }
                            len(); val n = len()
                            strings.add(String(axml, p, n, Charsets.UTF_8))
                        } else {
                            var n = b.getShort(p).toInt() and 0xffff
                            p += 2
                            if (n and 0x8000 != 0) { n = ((n and 0x7fff) shl 16) or (b.getShort(p).toInt() and 0xffff); p += 2 }
                            strings.add(String(axml, p, n * 2, Charsets.UTF_16LE))
                        }
                    }
                }
                0x0180 -> resIds = IntArray((size - 8) / 4) { b.getInt(pos + 8 + it * 4) }
            }
            chunks.add(intArrayOf(pos, size))
            pos += size
        }
        val vcName = resIds.indexOf(0x0101021b)
        val vnName = resIds.indexOf(0x0101021c)
        check(vcName >= 0 && vnName >= 0) { "versionCode/versionName non trovati" }
        val body = axml.copyOf()
        val bb = ByteBuffer.wrap(body).order(ByteOrder.LITTLE_ENDIAN)
        for ((start, _) in chunks.map { it[0] to it[1] }) {
            if ((bb.getShort(start).toInt() and 0xffff) != 0x0102) continue
            val ext = start + 16
            val attrStart = bb.getShort(ext + 8).toInt()
            val attrSize = bb.getShort(ext + 10).toInt()
            val count = bb.getShort(ext + 12).toInt()
            for (k in 0 until count) {
                val a = ext + attrStart + k * attrSize
                when (bb.getInt(a + 4)) {
                    vcName -> { body[a + 15] = 0x10; bb.putInt(a + 16, code) }
                    vnName -> {
                        // new string at the end of the pool, typed reference to it
                        val idx = strings.size
                        strings.add(name)
                        bb.putInt(a + 8, idx); body[a + 15] = 0x03; bb.putInt(a + 16, idx)
                    }
                }
            }
        }
        // rebuild the string pool (UTF-8, no styles)
        val data = ByteArrayOutputStream()
        val offs = ArrayList<Int>()
        fun putLen(n: Int) {
            if (n > 0x7f) { data.write(((n shr 8) and 0x7f) or 0x80); data.write(n and 0xff) } else data.write(n)
        }
        for (s in strings) {
            offs.add(data.size())
            val bytes = s.toByteArray(Charsets.UTF_8)
            putLen(s.length); putLen(bytes.size); data.write(bytes); data.write(0)
        }
        while (data.size() % 4 != 0) data.write(0)
        val header = 28
        val sStart = header + offs.size * 4
        val pool = ByteBuffer.allocate(sStart + data.size()).order(ByteOrder.LITTLE_ENDIAN).apply {
            putShort(0x0001); putShort(header.toShort()); putInt(sStart + data.size())
            putInt(offs.size); putInt(0); putInt(0x100); putInt(sStart); putInt(0)
            offs.forEach { putInt(it) }
            put(data.toByteArray())
        }.array()
        val out = ByteArrayOutputStream()
        out.write(body, 0, poolStart)
        out.write(pool)
        out.write(body, poolEnd, body.size - poolEnd)
        val res = out.toByteArray()
        ByteBuffer.wrap(res).order(ByteOrder.LITTLE_ENDIAN).putInt(4, res.size)
        return res
    }

    private fun renameText(xml: String, rename: Map<String, String>): String =
        Regex("drawable=\"([^\"]*)\"").replace(xml) { m ->
            val v = m.groupValues[1]
            "drawable=\"${rename[v] ?: v}\""
        }

    private fun signingKey(): Pair<PrivateKey, X509Certificate> {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!ks.containsAlias(KEY_ALIAS)) {
            val gen = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore")
            gen.initialize(
                KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_SIGN)
                    .setKeySize(2048)
                    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512)
                    .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1)
                    .setCertificateSubject(javax.security.auth.x500.X500Principal("CN=Icon Formatter Pack"))
                    .setCertificateNotAfter(java.util.Date(System.currentTimeMillis() + 30L * 365 * 24 * 3600 * 1000))
                    .build(),
            )
            gen.generateKeyPair()
        }
        val entry = ks.getEntry(KEY_ALIAS, null) as KeyStore.PrivateKeyEntry
        return entry.privateKey to (entry.certificate as X509Certificate)
    }

    private fun sign(input: File, output: File) {
        val (key, cert) = signingKey()
        val signer = ApkSigner.SignerConfig.Builder("pack", key, listOf(cert)).build()
        ApkSigner.Builder(listOf(signer))
            .setInputApk(input)
            .setOutputApk(output)
            .setMinSdkVersion(24)
            .setV1SigningEnabled(false)
            .setV2SigningEnabled(true)
            .setV3SigningEnabled(true)
            .build()
            .sign()
    }

    // --------------------------------------------------------- binary XML

    /**
     * Compiles a plain XML document (elements + attributes, no namespaces)
     * into Android binary XML, renaming `drawable`-like attribute values.
     */
    fun compileXml(text: String, rename: Map<String, String>): ByteArray {
        val strings = LinkedHashMap<String, Int>()
        fun idx(s: String) = strings.getOrPut(s) { strings.size }
        class Node(val start: Boolean, val name: Int, val attrs: List<Pair<Int, Int>>, val line: Int)
        val nodes = ArrayList<Node>()
        val p = Xml.newPullParser()
        p.setFeature(XmlPullParser.FEATURE_PROCESS_NAMESPACES, false)
        p.setInput(text.reader())
        while (true) {
            when (p.next()) {
                XmlPullParser.START_TAG -> {
                    val attrs = (0 until p.attributeCount).map { i ->
                        val n = p.getAttributeName(i)
                        var v = p.getAttributeValue(i)
                        if (n != "component") v = rename[v] ?: v
                        idx(n) to idx(v)
                    }
                    nodes.add(Node(true, idx(p.name), attrs, p.lineNumber))
                }
                XmlPullParser.END_TAG -> nodes.add(Node(false, idx(p.name), emptyList(), p.lineNumber))
                XmlPullParser.END_DOCUMENT -> break
            }
        }
        // string pool (UTF-8)
        val data = ByteArrayOutputStream()
        val offsets = ArrayList<Int>()
        fun len(n: Int) {
            if (n > 0x7f) { data.write(((n shr 8) and 0x7f) or 0x80); data.write(n and 0xff) } else data.write(n)
        }
        for (s in strings.keys) {
            offsets.add(data.size())
            val b = s.toByteArray(Charsets.UTF_8)
            len(s.length)
            len(b.size)
            data.write(b)
            data.write(0)
        }
        while (data.size() % 4 != 0) data.write(0)
        val poolHeader = 28
        val stringsStart = poolHeader + offsets.size * 4
        val poolSize = stringsStart + data.size()
        val body = ByteArrayOutputStream()
        fun buf(n: Int) = ByteBuffer.allocate(n).order(ByteOrder.LITTLE_ENDIAN)
        buf(poolHeader + offsets.size * 4).apply {
            putShort(0x0001); putShort(poolHeader.toShort()); putInt(poolSize)
            putInt(offsets.size); putInt(0); putInt(0x100); putInt(stringsStart); putInt(0)
            offsets.forEach { putInt(it) }
            body.write(array())
        }
        body.write(data.toByteArray())
        for (n in nodes) {
            if (n.start) {
                val size = 16 + 20 + n.attrs.size * 20
                buf(size).apply {
                    putShort(0x0102); putShort(16); putInt(size); putInt(n.line); putInt(-1)
                    putInt(-1); putInt(n.name)
                    putShort(20); putShort(20); putShort(n.attrs.size.toShort())
                    putShort(0); putShort(0); putShort(0)
                    for ((an, av) in n.attrs) {
                        putInt(-1); putInt(an); putInt(av)
                        putShort(8); put(0); put(0x03); putInt(av)
                    }
                    body.write(array())
                }
            } else {
                buf(24).apply {
                    putShort(0x0103); putShort(16); putInt(24); putInt(n.line); putInt(-1)
                    putInt(-1); putInt(n.name)
                    body.write(array())
                }
            }
        }
        val all = body.toByteArray()
        return buf(8 + all.size).apply {
            putShort(0x0003); putShort(8); putInt(8 + all.size); put(all)
        }.array()
    }

    // ---------------------------------------------------------------- install

    fun installedVersion(context: Context): Long? = try {
        val pi = context.packageManager.getPackageInfo(PACKAGE, 0)
        pi.lastUpdateTime
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    fun installedVersionName(context: Context): String? = try {
        context.packageManager.getPackageInfo(PACKAGE, 0).versionName
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    /** Installs [apk] through Shizuku (`pm install`, no confirmation). */
    fun installShizuku(context: Context, apk: File): String {
        val before = installedVersion(context)
        val (code, out) = apk.inputStream().use { shell("pm install -r -S ${apk.length()}", it) }
        // installed pack signed with another phone's key: Android refuses the
        // update; the app asks the user before replacing it
        if (out.contains("INSTALL_FAILED_UPDATE_INCOMPATIBLE") || out.contains("signatures do not match")) {
            throw IllegalStateException("SIGNATURE_MISMATCH")
        }
        check(code == 0 && out.contains("Success")) { "pm install: $out" }
        val after = installedVersion(context)
        check(after != null && after != before) { "Il pacchetto non risulta aggiornato dopo l'installazione" }
        return out
    }

    /** Installs [apk] with the system installer (user confirms). */
    fun installSession(activity: Activity, apk: File) {
        val pi = activity.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(PACKAGE)
        val id = pi.createSession(params)
        pi.openSession(id).use { s ->
            s.openWrite("pack.apk", 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                s.fsync(out)
            }
            val intent = Intent(activity, InstallResultReceiver::class.java)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
            s.commit(PendingIntent.getBroadcast(activity, id, intent, flags).intentSender)
        }
    }

    // ------------------------------------------------------------------ apply

    fun launcherInstalled(context: Context): String? = try {
        context.packageManager.getPackageInfo(NOTHING_LAUNCHER, 0).versionName ?: "?"
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    fun currentSelector(): String? {
        val (_, out) = shell("settings get system $SELECTOR")
        return out.takeIf { it.isNotEmpty() && it != "null" }
    }

    /**
     * Selects [PACKAGE] in Nothing Launcher. Returns a report; `verified` is
     * true only when Settings reads back our package after the toggle.
     */
    fun apply(activity: Activity): Map<String, Any?> {
        check(installedVersion(activity) != null) { "Il pack non è installato" }
        val launcher = launcherInstalled(activity)
        val prefs = activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val previous = currentSelector()
        if (previous != PACKAGE && previous != TEMPORARY_PACK) {
            prefs.edit().putString("previous", previous ?: "").apply()
        }
        var prepared = false
        if (launcher != null) {
            // the picker re-parses external packs when its view is created
            val i = Intent("com.nothing.launcher.icon_pack_picker").setPackage(NOTHING_LAUNCHER)
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_NEW_DOCUMENT or
                        Intent.FLAG_ACTIVITY_MULTIPLE_TASK or Intent.FLAG_ACTIVITY_NO_HISTORY or
                        Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS or Intent.FLAG_ACTIVITY_NO_ANIMATION,
                )
            prepared = try {
                activity.runOnUiThread { activity.startActivity(i, ActivityOptions.makeTaskLaunchBehind().toBundle()) }
                true
            } catch (_: Exception) {
                false
            }
            Thread.sleep(1500)
        }
        val (c1, o1) = shell("settings put system $SELECTOR $TEMPORARY_PACK")
        check(c1 == 0) { "settings put: $o1" }
        Thread.sleep(500)
        val (c2, o2) = shell("settings put system $SELECTOR $PACKAGE")
        check(c2 == 0) { "settings put: $o2" }
        val now = currentSelector()
        return mapOf(
            "launcher" to launcher,
            "prepared" to prepared,
            "selector" to now,
            "previous" to previous,
            "verified" to (now == PACKAGE),
        )
    }

    /** Puts back the selector value found before the first apply. */
    fun restore(context: Context): String? {
        val prev = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("previous", null)
        val (c, o) = if (prev.isNullOrEmpty()) shell("settings delete system $SELECTOR") else shell("settings put system $SELECTOR $prev")
        check(c == 0) { o }
        return currentSelector()
    }

    fun openPicker(context: Context): Boolean = try {
        context.startActivity(Intent("com.nothing.launcher.icon_pack_picker").setPackage(NOTHING_LAUNCHER).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (_: Exception) {
        false
    }
}

/** System installer callback: shows the confirmation the session asks for. */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.getIntExtra(PackageInstaller.EXTRA_STATUS, -999)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT) ?: return
                context.startActivity(confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
        }
    }
}
