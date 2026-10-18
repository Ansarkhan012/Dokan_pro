package com.dukaanpro.dukaan_pro

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * In-app APK updates for privately distributed builds (no Play Store).
 *
 * Installs go through Android's PackageInstaller session API: Android itself
 * shows the install confirmation (always required, see setRequireUserAction),
 * checks the signature against the installed app and replaces it in place,
 * keeping its data. Nothing here uninstalls, installs silently, or touches
 * app data; it only reads the downloaded APK the Dart side has already
 * verified (size + SHA-256 from the signed manifest).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val statusAction get() = "$packageName.APP_UPDATE_STATUS"

    private val installReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
            if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
                @Suppress("DEPRECATION")
                val confirm: Intent? = if (Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(confirm)
                    report("userConfirming")
                } else {
                    report("failed")
                }
                return
            }
            report(
                when (status) {
                    PackageInstaller.STATUS_SUCCESS -> "success"
                    PackageInstaller.STATUS_FAILURE_ABORTED -> "cancelled"
                    PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
                    PackageInstaller.STATUS_FAILURE_CONFLICT -> "conflict"
                    PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "incompatible"
                    PackageInstaller.STATUS_FAILURE_STORAGE -> "storage"
                    PackageInstaller.STATUS_FAILURE_INVALID -> "invalid"
                    else -> "failed"
                }
            )
        }
    }
    private var receiverRegistered = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!receiverRegistered) {
            val filter = IntentFilter(statusAction)
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(installReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(installReceiver, filter)
            }
            receiverRegistered = true
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installedApp" -> result.success(installedApp())
                        "inspectApk" -> result.success(inspectApk(ownApk(call.argument<String>("path"))))
                        "openInstallPermissionSettings" -> {
                            openInstallPermissionSettings()
                            result.success(null)
                        }
                        "install" -> install(ownApk(call.argument<String>("path")), result)
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("app_update", e.javaClass.simpleName, null)
                }
            }
        }
    }

    override fun onDestroy() {
        if (receiverRegistered) {
            unregisterReceiver(installReceiver)
            receiverRegistered = false
        }
        super.onDestroy()
    }

    private fun report(status: String) = main.post { channel?.invokeMethod("installStatus", status) }

    /** Only APKs this feature downloaded: <cache>/app_update/dokan_pro_N.apk. */
    private fun ownApk(path: String?): File {
        val dir = File(cacheDir, "app_update").canonicalFile
        val file = File(path ?: "").canonicalFile
        require(file.parentFile == dir && Regex("""dokan_pro_\d+\.apk""").matches(file.name) && file.isFile) {
            "not an update APK"
        }
        return file
    }

    private fun sha256(sig: Signature): String =
        MessageDigest.getInstance("SHA-256").digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Pair<List<String>, List<String>> {
        if (Build.VERSION.SDK_INT >= 28) {
            val s = info.signingInfo ?: return Pair(emptyList(), emptyList())
            val current = if (s.hasMultipleSigners()) s.apkContentsSigners else s.signingCertificateHistory?.takeLast(1)?.toTypedArray()
            val history = if (s.hasMultipleSigners()) emptyArray() else s.signingCertificateHistory ?: emptyArray()
            return Pair((current ?: emptyArray()).map(::sha256), history.map(::sha256))
        }
        return Pair((info.signatures ?: emptyArray()).map(::sha256), emptyList())
    }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private val signingFlags: Int
        get() = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    @Suppress("DEPRECATION")
    private fun installedApp(): Map<String, Any?> {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(signingFlags.toLong()))
        } else {
            packageManager.getPackageInfo(packageName, signingFlags)
        }
        val (current, _) = signers(info)
        return mapOf(
            "packageName" to info.packageName,
            "versionCode" to versionCode(info),
            "versionName" to (info.versionName ?: ""),
            "signers" to current,
            "canRequestInstalls" to (Build.VERSION.SDK_INT < 26 || packageManager.canRequestPackageInstalls()),
        )
    }

    @Suppress("DEPRECATION")
    private fun inspectApk(file: File): Map<String, Any?> {
        val info = (if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageArchiveInfo(file.path, PackageManager.PackageInfoFlags.of(signingFlags.toLong()))
        } else {
            packageManager.getPackageArchiveInfo(file.path, signingFlags)
        }) ?: throw IllegalArgumentException("unreadable APK")
        val (current, history) = signers(info)
        return mapOf(
            "packageName" to info.packageName,
            "versionCode" to versionCode(info),
            "versionName" to (info.versionName ?: ""),
            "signers" to current,
            "signerHistory" to history,
        )
    }

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= 26) {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    private fun install(file: File, result: MethodChannel.Result) {
        Thread {
            try {
                val installer = packageManager.packageInstaller
                val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
                    setAppPackageName(packageName)
                    setSize(file.length())
                    if (Build.VERSION.SDK_INT >= 31) {
                        setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
                    }
                }
                val sessionId = installer.createSession(params)
                installer.openSession(sessionId).use { session ->
                    FileInputStream(file).use { input ->
                        session.openWrite("dokan_pro.apk", 0, file.length()).use { out ->
                            input.copyTo(out)
                            session.fsync(out)
                        }
                    }
                    val flags = if (Build.VERSION.SDK_INT >= 31) {
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }
                    val callback = PendingIntent.getBroadcast(
                        this, sessionId, Intent(statusAction).setPackage(packageName), flags
                    )
                    session.commit(callback.intentSender)
                }
                main.post { result.success("userConfirming") }
            } catch (e: Exception) {
                main.post { result.success(if (e is java.io.IOException) "storage" else "failed") }
            }
        }.start()
    }

    companion object {
        private const val CHANNEL = "com.dukaanpro.dukaan_pro/app_update"
    }
}
