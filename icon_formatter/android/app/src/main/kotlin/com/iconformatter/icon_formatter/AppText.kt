package com.iconformatter.icon_formatter

import android.content.Context
import android.content.res.Configuration
import java.util.Locale

/** Android-side texts in the language chosen in the app (set by Flutter). */
object AppText {
    private const val PREFS = "app_text"

    fun setLanguage(c: Context, code: String) {
        c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("lang", code).apply()
    }

    fun ctx(c: Context): Context {
        val code = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("lang", null) ?: return c
        val conf = Configuration(c.resources.configuration)
        conf.setLocale(Locale(code))
        return c.createConfigurationContext(conf)
    }

    fun get(c: Context, id: Int, vararg args: Any): String = ctx(c).getString(id, *args)
}
