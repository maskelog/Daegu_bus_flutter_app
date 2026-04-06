package com.devground.daegubus.services

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.devground.daegubus.R

class BusAlertAlarmSoundPlayer(private val context: Context) {
    private val TAG = "BusAlertAlarmSoundPlayer"
    private var alarmMediaPlayer: MediaPlayer? = null

    fun play() {
        try {
            stop() // 기존 재생 중인 사운드 정리

            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()

            alarmMediaPlayer = MediaPlayer().apply {
                setAudioAttributes(audioAttributes)

                // res/raw/alarm_sound.mp3 사용, 없으면 시스템 기본 알람음
                try {
                    val resUri = Uri.parse("android.resource://${context.packageName}/${R.raw.alarm_sound}")
                    setDataSource(context.applicationContext, resUri)
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ alarm_sound.mp3 로드 실패, 시스템 기본 알람음 사용", e)
                    reset()
                    setAudioAttributes(audioAttributes)
                    val defaultAlarmUri = android.media.RingtoneManager.getDefaultUri(
                        android.media.RingtoneManager.TYPE_ALARM
                    ) ?: android.media.RingtoneManager.getDefaultUri(
                        android.media.RingtoneManager.TYPE_NOTIFICATION
                    )
                    if (defaultAlarmUri != null) {
                        setDataSource(context.applicationContext, defaultAlarmUri)
                    } else {
                        Log.e(TAG, "❌ 기본 알람음도 없음")
                        return@apply
                    }
                }

                isLooping = true

                // 알람 볼륨 설정
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_ALARM)
                // 알람 스트림 볼륨이 0이면 최대의 70%로 설정
                if (currentVolume == 0) {
                    audioManager.setStreamVolume(
                        AudioManager.STREAM_ALARM,
                        (maxVolume * 0.7).toInt().coerceAtLeast(1),
                        0
                    )
                }

                prepare()
                start()
                Log.d(TAG, "🔊 알람 사운드 재생 시작 (STREAM_ALARM)")
            }

            // 60초 후 자동 정지 (무한 재생 방지)
            Handler(Looper.getMainLooper()).postDelayed({
                stop()
            }, 60000L)

        } catch (e: Exception) {
            Log.e(TAG, "❌ 알람 사운드 재생 오류: ${e.message}", e)
            stop()
        }
    }

    fun stop() {
        try {
            alarmMediaPlayer?.let { player ->
                if (player.isPlaying) {
                    player.stop()
                }
                player.reset()
                player.release()
                Log.d(TAG, "🔇 알람 사운드 정지")
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ 알람 사운드 정지 중 오류: ${e.message}")
        } finally {
            alarmMediaPlayer = null
        }
    }
}
