package ai.domovina

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends AudioServiceActivity (not FlutterActivity) so the audio_service
// plugin can attach its FlutterEngine for background playback. Required by
// lib/services/background_audio.dart.
class MainActivity : AudioServiceActivity() {
    // Brand-neutral channel name; must match lib/services/tv_mode.dart.
    private val tvModeChannel = "app/tv_mode"

    // Push o novim epizodama; mora odgovarati lib/push/firebase_push_transport.dart.
    private val pushChannel = "app/push"

    // ID kanala obavijesti; isti kao `default_notification_channel_id` u
    // AndroidManifest.xml i `android.notification.channel_id` u Workeru.
    private val newEpisodesChannelId = "new_episodes"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, tvModeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isLeanback" -> {
                        val isTv = packageManager
                            .hasSystemFeature(PackageManager.FEATURE_LEANBACK)
                        result.success(isTv)
                    }
                    else -> result.notImplemented()
                }
            }

        createNewEpisodesChannel()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, pushChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Kanal mora postojati prije prve obavijesti, inače FCM padne na generički
    // „Miscellaneous" i korisnik ne može ugasiti samo nove epizode. Idempotentno:
    // ponovno stvaranje istog ID-a samo osvježi ime (npr. nakon promjene jezika).
    private fun createNewEpisodesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            newEpisodesChannelId,
            getString(R.string.push_channel_new_episodes),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = getString(R.string.push_channel_new_episodes_description)
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }
}
