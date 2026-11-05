package com.iconformatter.icon_formatter

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit
import java.util.zip.CRC32

/**
 * Light change detection for the icon pack (no root, no foreground service,
 * no frequent polling):
 *  - a persisted periodic JobScheduler job (6 h, flex 1 h, battery not low)
 *    that survives reboots and is deferred by Doze like any job;
 *  - an immediate one-shot job when the phone is unlocked (USER_PRESENT),
 *    registered while the app process is alive (Android 8+ does not deliver
 *    USER_PRESENT to manifest receivers);
 *  - PackageManager.getChangedPackages(sequence) to skip all work when no
 *    package changed; only changed launcher apps get their icon hashed.
 * Results (installed / removed / updated / icon changed) are stored as
 * "pending" and shown in the app; a silent notification is posted when
 * something changed.
 */
object AutoSync {
    private const val PREFS = "auto_sync"
    private const val JOB_PERIODIC = 5101
    private const val JOB_NOW = 5102
    private const val CHANNEL = "auto_sync"
    private const val NOTIF_ID = 5103

    private fun prefs(c: Context) = c.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun isEnabled(c: Context) = prefs(c).getBoolean("enabled", false)

    fun setEnabled(c: Context, on: Boolean) {
        prefs(c).edit().putBoolean("enabled", on).apply()
        if (on) {
            schedule(c)
            if (!prefs(c).contains("snapshot")) check(c, notify = false, baseline = true)
        } else {
            val js = c.getSystemService(JobScheduler::class.java)
            js.cancel(JOB_PERIODIC)
            js.cancel(JOB_NOW)
        }
    }

    fun schedule(c: Context) {
        val js = c.getSystemService(JobScheduler::class.java)
        val info = JobInfo.Builder(JOB_PERIODIC, ComponentName(c, AutoSyncJob::class.java))
            .setPeriodic(TimeUnit.HOURS.toMillis(6), TimeUnit.HOURS.toMillis(1))
            .setPersisted(true)
            .setRequiresBatteryNotLow(true)
            .build()
        js.schedule(info)
    }

    /** One-shot check as soon as the system allows it (after unlock). */
    fun scheduleNow(c: Context) {
        if (!isEnabled(c)) return
        val js = c.getSystemService(JobScheduler::class.java)
        js.schedule(
            JobInfo.Builder(JOB_NOW, ComponentName(c, AutoSyncJob::class.java))
                .setMinimumLatency(2_000)
                .setOverrideDeadline(60_000)
                .build()
        )
    }

    private var unlockReceiver: BroadcastReceiver? = null

    /** Unlock trigger, valid while the process is alive. */
    fun registerUnlock(c: Context) {
        if (unlockReceiver != null) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) = scheduleNow(ctx.applicationContext)
        }
        val f = IntentFilter(Intent.ACTION_USER_PRESENT)
        if (Build.VERSION.SDK_INT >= 33) c.applicationContext.registerReceiver(r, f, Context.RECEIVER_NOT_EXPORTED)
        else c.applicationContext.registerReceiver(r, f)
        unlockReceiver = r
    }

    private fun launcherApps(c: Context): Map<String, String> {
        val pm = c.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val infos = if (Build.VERSION.SDK_INT >= 33) pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0))
        else @Suppress("DEPRECATION") pm.queryIntentActivities(intent, 0)
        val out = LinkedHashMap<String, String>()
        for (ri in infos) {
            val ai = ri.activityInfo ?: continue
            if (ai.packageName == c.packageName) continue
            out["${ai.packageName}/${ai.name}"] = ri.loadLabel(pm).toString()
        }
        return out
    }

    private fun iconHash(c: Context, component: String): Long {
        return try {
            val (pkg, act) = component.split('/', limit = 2)
            val d = c.packageManager.getActivityIcon(ComponentName(pkg, act))
            val b = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
            d.setBounds(0, 0, 48, 48)
            d.draw(Canvas(b))
            val px = IntArray(48 * 48)
            b.getPixels(px, 0, 48, 0, 0, 48, 48)
            b.recycle()
            val crc = CRC32()
            for (v in px) crc.update(byteArrayOf((v shr 24).toByte(), (v shr 16).toByte(), (v shr 8).toByte(), v.toByte()))
            crc.value
        } catch (e: Exception) {
            0L
        }
    }

    /**
     * Compares the launcher apps with the stored snapshot. Returns the number
     * of new pending changes. [baseline] only stores the snapshot.
     */
    @Synchronized
    fun check(c: Context, notify: Boolean = true, baseline: Boolean = false): Int {
        val p = prefs(c)
        val pm = c.packageManager
        val lastSeq = p.getInt("sequence", 0)
        val changed: Set<String>? = if (Build.VERSION.SDK_INT >= 26 && p.contains("snapshot") && !baseline) {
            pm.getChangedPackages(lastSeq)?.let { ch ->
                p.edit().putInt("sequence", ch.sequenceNumber).apply()
                ch.packageNames.toSet()
            } ?: emptySet()
        } else null
        val now = System.currentTimeMillis()
        p.edit().putLong("lastCheck", now).apply()
        // nothing changed since the last check: no work at all
        if (changed != null && changed.isEmpty()) return 0

        val old = p.getString("snapshot", null)?.let { JSONObject(it) } ?: JSONObject()
        val apps = launcherApps(c)
        val snap = JSONObject()
        var pending = p.getString("pending", null)?.let { JSONArray(it) } ?: JSONArray()
        var added = 0
        fun push(component: String, label: String, kind: String) {
            if (baseline) return
            // latest change wins (e.g. uninstalled, then installed again)
            val keep = JSONArray()
            for (i in 0 until pending.length()) {
                val o = pending.getJSONObject(i)
                if (o.getString("component") == component && o.optString("change") == kind) return
                if (o.getString("component") != component) keep.put(o)
            }
            keep.put(JSONObject().put("component", component).put("label", label).put("change", kind).put("time", now))
            pending = keep
            added++
        }
        for ((comp, label) in apps) {
            val pkg = comp.substringBefore('/')
            val prev = old.optJSONObject(comp)
            val needHash = prev == null || changed == null || pkg in changed
            val hash = if (needHash) iconHash(c, comp) else prev!!.optLong("hash")
            val version = try {
                val pi = pm.getPackageInfo(pkg, 0)
                if (Build.VERSION.SDK_INT >= 28) pi.longVersionCode else @Suppress("DEPRECATION") pi.versionCode.toLong()
            } catch (e: Exception) { 0L }
            snap.put(comp, JSONObject().put("hash", hash).put("version", version).put("label", label))
            when {
                prev == null -> push(comp, label, "installata")
                prev.optLong("hash") != hash -> push(comp, label, "icona modificata")
                prev.optLong("version") != version -> push(comp, label, "aggiornata")
            }
        }
        val it = old.keys()
        while (it.hasNext()) {
            val comp = it.next()
            if (!apps.containsKey(comp)) push(comp, old.getJSONObject(comp).optString("label"), "disinstallata")
        }
        if (Build.VERSION.SDK_INT >= 26 && changed == null) {
            pm.getChangedPackages(0)?.let { p.edit().putInt("sequence", it.sequenceNumber).apply() }
        }
        p.edit().putString("snapshot", snap.toString()).putString("pending", pending.toString()).apply()
        if (notify && added > 0) notifyChanges(c, pending.length())
        return added
    }

    fun status(c: Context): Map<String, Any?> {
        val p = prefs(c)
        val pending = p.getString("pending", null)?.let { JSONArray(it) } ?: JSONArray()
        val list = ArrayList<Map<String, Any?>>()
        for (i in 0 until pending.length()) {
            val o = pending.getJSONObject(i)
            list.add(mapOf("component" to o.getString("component"), "label" to o.optString("label"), "change" to o.optString("change"), "time" to o.optLong("time")))
        }
        val js = c.getSystemService(JobScheduler::class.java)
        return mapOf(
            "enabled" to isEnabled(c),
            "scheduled" to (js.getPendingJob(JOB_PERIODIC) != null),
            "lastCheck" to p.getLong("lastCheck", 0L),
            "pending" to list,
        )
    }

    fun clearPending(c: Context, components: List<String>?) {
        val p = prefs(c)
        if (components == null) {
            p.edit().remove("pending").apply()
        } else {
            val pending = p.getString("pending", null)?.let { JSONArray(it) } ?: JSONArray()
            val keep = JSONArray()
            for (i in 0 until pending.length()) if (pending.getJSONObject(i).getString("component") !in components) keep.put(pending.get(i))
            p.edit().putString("pending", keep.toString()).apply()
        }
        c.getSystemService(NotificationManager::class.java).cancel(NOTIF_ID)
    }

    private fun notifyChanges(c: Context, n: Int) {
        if (Build.VERSION.SDK_INT >= 33 && c.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val nm = c.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Modifiche alle app", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(
            c, 0,
            Intent(c, MainActivity::class.java).putExtra("openBuilder", true).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val b = if (Build.VERSION.SDK_INT >= 26) android.app.Notification.Builder(c, CHANNEL) else @Suppress("DEPRECATION") android.app.Notification.Builder(c)
        nm.notify(
            NOTIF_ID,
            b.setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Icon pack da aggiornare")
                .setContentText("$n app installate, aggiornate o con icona cambiata")
                .setContentIntent(open)
                .setAutoCancel(true)
                .build(),
        )
    }
}

class AutoSyncJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        Thread {
            try {
                AutoSync.check(applicationContext)
            } finally {
                jobFinished(params, false)
            }
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters) = true
}

/** Reboot / app update: restore the schedule if automation is on. */
class AutoSyncBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (AutoSync.isEnabled(context)) AutoSync.schedule(context)
    }
}
