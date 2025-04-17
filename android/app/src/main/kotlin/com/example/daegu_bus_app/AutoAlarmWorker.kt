package com.example.daegu_bus_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.example.daegu_bus_app.BusAlertService
import com.example.daegu_bus_app.TTSService
import org.json.JSONObject
import java.util.Calendar
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.os.Bundle
import java.util.Locale
import android.app.NotificationManager
import androidx.core.app.NotificationCompat
import android.media.AudioManager
import android.media.AudioFocusRequest
import android.media.AudioAttributes
import android.media.AudioManager.OnAudioFocusChangeListener

// ... BackgroundWorker ...

// --- Worker for Auto Alarms ---
class AutoAlarmWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams), TextToSpeech.OnInitListener {
    private val TAG = "AutoAlarmWorker"
    private val ALARM_NOTIFICATION_CHANNEL_ID = "bus_alarm_channel"
    private lateinit var tts: TextToSpeech
    private var ttsInitialized = false
    private val ttsInitializationLock = Object() // Lock for synchronization
    private lateinit var audioManager: AudioManager // AudioManager 추가
    private var audioFocusRequest: AudioFocusRequest? = null // AudioFocusRequest 추가

    // 오디오 포커스 리스너 추가
    private val audioFocusChangeListener = OnAudioFocusChangeListener { focusChange ->
        when (focusChange) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                Log.d(TAG, "🔊 [Worker] 오디오 포커스 잃음 (LOSS). TTS 중지 시도.")
                shutdownTTS() // 포커스 잃으면 TTS 중지 및 정리
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                Log.d(TAG, "🔊 [Worker] 오디오 포커스 일시적 잃음. TTS 중지.")
                tts.stop()
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                 Log.d(TAG, "🔊 [Worker] 오디오 포커스 얻음 (GAIN).")
                 // Worker는 짧은 시간 실행되므로 재개 로직은 불필요할 수 있음
            }
        }
    }

    // Store data for TTS, as initialization is async
    private var pendingAlarmId: Int = 0
    private var pendingBusNo: String = ""
    private var pendingStationName: String = ""
    private var pendingUseTTS: Boolean = true // useTTS 상태 저장

    override fun doWork(): Result {
        Log.d(TAG, "⏰ AutoAlarmWorker 실행 시작")
        pendingAlarmId = inputData.getInt("alarmId", 0)
        pendingBusNo = inputData.getString("busNo") ?: ""
        pendingStationName = inputData.getString("stationName") ?: ""
        pendingUseTTS = inputData.getBoolean("useTTS", true)

        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager // AudioManager 초기화

        Log.d(TAG, "⏰ Executing AutoAlarmWorker: ID=$pendingAlarmId, Bus=$pendingBusNo, Station=$pendingStationName, TTS=$pendingUseTTS")

        if (pendingBusNo.isEmpty() || pendingStationName.isEmpty()) {
            Log.e(TAG, "❌ Missing busNo or stationName in inputData")
            return Result.failure()
        }

        // Show Notification (can be done immediately)
        showNotification(pendingAlarmId, pendingBusNo, pendingStationName)

        // TTS 사용 설정 시 TTS 초기화
        if (pendingUseTTS) {
            Log.d(TAG, "🔊 TTS 사용 설정됨. 초기화 시작...")
            tts = TextToSpeech(applicationContext, this)
            // TTS speaking은 onInit에서 처리됨
            Log.d(TAG, "⏳ TTS 초기화 대기 중...")
        } else {
             Log.d(TAG, "🔊 TTS 사용 안 함 설정됨.")
             // TTS 사용 안하면 즉시 성공 처리 가능
             return Result.success()
        }

        // Worker 결과는 초기 설정 성공 여부에 따라 결정됨 (TTS는 비동기)
        Log.d(TAG, "✅ Worker 초기 설정 완료: ID=$pendingAlarmId. TTS 초기화는 비동기 진행.")
        // TTS 초기화 및 발화 완료를 기다리지 않고 성공 반환 (WorkManager의 비동기 처리)
        return Result.success()
    }

    // ... showNotification method ...
     private fun showNotification(alarmId: Int, busNo: String, stationName: String) {
        // ... 기존 showNotification 구현 유지 ...
        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = intent?.let {
            PendingIntent.getActivity(applicationContext, alarmId, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        // Full-screen intent
        val fullScreenIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("alarmId", alarmId)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            applicationContext, alarmId, fullScreenIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(applicationContext, ALARM_NOTIFICATION_CHANNEL_ID)
            .setContentTitle("$busNo 버스 알람")
            .setContentText("$stationName 정류장에 곧 도착합니다")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()

        try {
            notificationManager.notify(alarmId, notification)
            Log.d(TAG, "✅ Notification shown with lockscreen support for alarm ID: $alarmId")
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ Notification permission possibly denied: ${e.message}")
        } catch (e: Exception) {
             Log.e(TAG, "❌ Error showing notification: ${e.message}")
        }
    }

    override fun onInit(status: Int) {
        synchronized(ttsInitializationLock) {
            if (status == TextToSpeech.SUCCESS) {
                val result = tts.setLanguage(Locale.KOREAN)
                if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                     Log.e(TAG, "❌ Korean language is not supported for TTS")
                     ttsInitialized = false
                } else {
                    tts.setSpeechRate(1.2f)
                    tts.setPitch(1.1f)
                    ttsInitialized = true
                    Log.d(TAG, "✅ TTS 초기화 성공 in AutoAlarmWorker. Speaking pending message.")
                    // TTS 준비 완료, 저장된 데이터로 발화 시도
                    if(pendingUseTTS && pendingBusNo.isNotEmpty() && pendingStationName.isNotEmpty()){ // 데이터 유효성 재확인
                        speakTTS(pendingAlarmId, pendingBusNo, pendingStationName)
                    } else {
                         Log.w(TAG, "TTS 발화 데이터 누락 또는 TTS 비활성화됨.")
                    }
                }
            } else {
                Log.e(TAG, "❌ TTS 초기화 실패 in AutoAlarmWorker: $status")
                ttsInitialized = false
            }
        }
    }

    private fun speakTTS(alarmId: Int, busNo: String, stationName: String) {
         if (!ttsInitialized || !::tts.isInitialized) {
            Log.e(TAG, "TTS not ready or not initialized when trying to speak.")
            return
        }

        // --- 오디오 포커스 요청 ---
        val focusResult = requestAudioFocus()
        if (focusResult != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            Log.w(TAG, "🔊 [Worker] 오디오 포커스 획득 실패 ($focusResult). TTS 발화 취소.")
            return
        }
        Log.d(TAG, "🔊 [Worker] 오디오 포커스 획득 성공.")
        // --- 오디오 포커스 획득 성공 ---

        val utteranceId = "auto_alarm_$alarmId"
        val params = Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
            putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_ALARM) // 스피커 출력을 위해 ALARM 스트림 사용
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
        }
        val message = "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다"

        // 오디오 포커스 해제를 위한 리스너 설정 *Speak 호출 전*
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                Log.d(TAG, "🔊 [Worker] TTS 발화 시작: $utteranceId")
            }
            override fun onDone(utteranceId: String?) {
                if (utteranceId == "auto_alarm_$alarmId") {
                    Log.d(TAG, "✅ [Worker] TTS 발화 완료, 자원 해제 시도: $alarmId")
                    shutdownTTS() // 완료 시 자원 해제
                }
            }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) {
                Log.e(TAG, "❌ [Worker] TTS Error (deprecated) for utteranceId: $utteranceId")
                shutdownTTS() // 오류 시 자원 해제
            }
             override fun onError(utteranceId: String?, errorCode: Int) {
                 Log.e(TAG, "❌ [Worker] TTS Error ($errorCode) for utteranceId: $utteranceId")
                 shutdownTTS() // 오류 시 자원 해제
             }
        })

        val result = tts.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        if (result == TextToSpeech.ERROR) {
             Log.e(TAG, "❌ TTS speak() failed for alarm ID: $alarmId")
             shutdownTTS() // Speak 호출 실패 시 즉시 자원 해제
        } else {
            Log.d(TAG, "✅ TTS 발화 요청됨: ID=$alarmId, Result=$result")
            // 포커스 해제는 UtteranceProgressListener에서 처리됨
        }
    }

    // 오디오 포커스 요청 함수 (Worker용)
    private fun requestAudioFocus(): Int {
        val focusGain = AudioManager.AUDIOFOCUS_GAIN_TRANSIENT // 알람은 짧으므로 TRANSIENT
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            audioFocusRequest = AudioFocusRequest.Builder(focusGain)
                .setAudioAttributes(attributes)
                .setAcceptsDelayedFocusGain(false)
                .setOnAudioFocusChangeListener(audioFocusChangeListener)
                .build()
            audioManager.requestAudioFocus(audioFocusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(audioFocusChangeListener, AudioManager.STREAM_ALARM, focusGain)
        }
    }

    // 오디오 포커스 해제 함수 (Worker용)
    private fun abandonAudioFocus() {
        Log.d(TAG, "🔊 [Worker] 오디오 포커스 해제 시도.")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(audioFocusChangeListener)
        }
    }

    private fun shutdownTTS() {
         // Ensure TTS shutdown happens only once and safely
        synchronized(ttsInitializationLock) {
            if (::tts.isInitialized) {
                 try {
                     // 오디오 포커스 해제
                     abandonAudioFocus()

                     // TTS 중지 및 종료
                     tts.stop()
                     tts.shutdown()
                     ttsInitialized = false // 초기화 상태 업데이트
                     Log.d(TAG, "✅ [Worker] TTS 자원 완전 해제됨.")
                 } catch (e: Exception) {
                     Log.e(TAG, "❌ [Worker] TTS 자원 해제 중 오류: ${e.message}")
                 }
            }
        }
    }

    override fun onStopped() {
        Log.d(TAG, "AutoAlarmWorker stopped. Cleaning up TTS.")
        shutdownTTS() // Worker 중지 시 TTS 자원 정리
        super.onStopped()
    }
} 