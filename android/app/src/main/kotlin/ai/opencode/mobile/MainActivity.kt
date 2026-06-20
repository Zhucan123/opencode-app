package ai.opencode.mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAiCompleteChannel()
    }

    private fun createAiCompleteChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            val channelId = "ai_complete_native"
            // 只在渠道不存在时创建，避免覆盖用户手动调整的设置
            if (manager.getNotificationChannel(channelId) != null) return
            val channel = NotificationChannel(
                channelId,
                "AI 回复完成",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "opencode AI 完成回复时弹出横幅并振动"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 300, 100, 300)
                enableLights(true)
            }
            manager.createNotificationChannel(channel)
        }
    }
}
