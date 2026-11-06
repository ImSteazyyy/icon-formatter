package com.iconformatter.icon_formatter

import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Resources
import android.graphics.drawable.Drawable
import android.provider.Settings
import android.util.Xml
import org.xmlpull.v1.XmlPullParser

/**
 * The icon pack the launcher is using right now (not necessarily the one
 * Icon Formatter generated), and its icons for given app components.
 *
 * Which pack is active is only readable for Nothing Launcher: Settings.System
 * `nothing_icon_pack` (directly when Android allows it, else through Shizuku).
 * Other launchers keep the choice in their private data: then there is no
 * active pack for us and the stock icons are shown.
 */
object ActivePack {
    private const val SELECTOR = "nothing_icon_pack"

    /** Values of the selector that are not an installed pack package. */
    private val BUILT_IN = setOf("THEMED_ICONS_NOTHING", "null", "", "default", "system")

    /** Package of the active pack, or null (stock icons / unknown). */
    fun current(context: Context): String? {
        val value = readSelector(context) ?: return null
        if (value in BUILT_IN) return null
        return try {
            context.packageManager.getApplicationInfo(value, 0)
            value
        } catch (_: PackageManager.NameNotFoundException) {
            // the selector still names a pack that was uninstalled
            null
        }
    }

    private fun readSelector(context: Context): String? {
        try {
            Settings.System.getString(context.contentResolver, SELECTOR)?.let { return it.trim() }
        } catch (_: Exception) {
            // hidden key not readable for this targetSdk: ask Shizuku below
        }
        return try {
            DevicePack.currentSelector()
        } catch (_: Exception) {
            null
        }
    }

    fun label(context: Context, pack: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pack, 0)).toString()
    } catch (_: Exception) {
        pack
    }

    private class Filter(val res: Resources, val byComponent: Map<String, String>, val byPackage: Map<String, String>)

    private var cache: Pair<String, Filter>? = null

    private fun filter(context: Context, pack: String): Filter? {
        cache?.let { if (it.first == pack) return it.second }
        val pm = context.packageManager
        val res = try {
            pm.getResourcesForApplication(pack)
        } catch (_: Exception) {
            return null
        }
        val comp = HashMap<String, String>()
        val pkg = HashMap<String, String>()
        fun add(component: String?, drawable: String?) {
            if (component.isNullOrEmpty() || drawable.isNullOrEmpty()) return
            // ComponentInfo{pkg/activity}
            val inner = component.substringAfter('{', "").substringBefore('}', "")
            if (!inner.contains('/')) return
            val p = inner.substringBefore('/')
            var a = inner.substringAfter('/')
            if (a.startsWith(".")) a = p + a
            comp.putIfAbsent("$p/$a", drawable)
            pkg.putIfAbsent(p, drawable)
        }
        fun parse(parser: XmlPullParser) {
            var ev = parser.eventType
            while (ev != XmlPullParser.END_DOCUMENT) {
                if (ev == XmlPullParser.START_TAG && parser.name == "item") {
                    add(parser.getAttributeValue(null, "component"), parser.getAttributeValue(null, "drawable"))
                }
                ev = parser.next()
            }
        }
        val xmlId = res.getIdentifier("appfilter", "xml", pack)
        if (xmlId != 0) {
            try {
                res.getXml(xmlId).use { parse(it) }
            } catch (_: Exception) {
            }
        }
        if (comp.isEmpty()) {
            try {
                res.assets.open("appfilter.xml").use { input ->
                    val parser = Xml.newPullParser()
                    parser.setInput(input, null)
                    parse(parser)
                }
            } catch (_: Exception) {
            }
        }
        if (comp.isEmpty()) return null
        val f = Filter(res, comp, pkg)
        cache = pack to f
        return f
    }

    /**
     * The pack's drawable for package/activity: exact component first, then
     * any entry of the same package (apps with several launcher activities).
     * Null when the pack has no icon for that app.
     */
    fun drawable(context: Context, pack: String, packageName: String, activity: String): Drawable? {
        val f = filter(context, pack) ?: return null
        val name = f.byComponent["$packageName/$activity"] ?: f.byPackage[packageName] ?: return null
        var id = f.res.getIdentifier(name, "drawable", pack)
        if (id == 0) id = f.res.getIdentifier(name, "mipmap", pack)
        if (id == 0) return null
        return try {
            @Suppress("DEPRECATION")
            f.res.getDrawableForDensity(id, context.resources.displayMetrics.densityDpi, null)
        } catch (_: Exception) {
            null
        }
    }

    fun invalidate() {
        cache = null
    }
}
