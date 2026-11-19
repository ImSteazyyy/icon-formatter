package com.iconformatter.icon_formatter

import android.content.Context
import android.net.Uri
import android.webkit.MimeTypeMap
import java.io.File

/** Copies images received from the Android share sheet into the app cache. */
object ShareIntake {
    const val MAX_FILES = 50
    private const val DIR = "shared"
    private const val KEEP_MS = 60 * 60 * 1000L

    /** Streams each URI into cacheDir/shared and returns the file paths. Call off the UI thread. */
    fun copyToCache(c: Context, uris: List<Uri>): List<String> {
        if (uris.isEmpty()) return emptyList()
        val dir = File(c.cacheDir, DIR).apply { mkdirs() }
        // files of an earlier share, already read by Dart
        val old = System.currentTimeMillis() - KEEP_MS
        dir.listFiles()?.forEach { if (it.lastModified() < old) it.delete() }
        val stamp = System.currentTimeMillis()
        val out = ArrayList<String>()
        uris.forEachIndexed { i, uri ->
            try {
                val type = c.contentResolver.getType(uri)
                val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(type) ?: "png"
                val f = File(dir, "shared_${stamp}_$i.$ext")
                val copied = c.contentResolver.openInputStream(uri)?.use { input ->
                    f.outputStream().use { input.copyTo(it) }
                }
                if (copied != null && f.length() > 0) out.add(f.absolutePath) else f.delete()
            } catch (_: Exception) {
                // unreadable item: skipped
            }
        }
        return out
    }
}
