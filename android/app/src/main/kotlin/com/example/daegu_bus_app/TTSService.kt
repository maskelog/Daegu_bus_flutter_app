package com.example.daegu_bus_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.IBinder
import android.speech.tts.TextToSpeech
import android.speech.tts.TextToSpeech.OnUtteranceProgressListener
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Locale
import java.util.UUID

class TTSService : Service(), TextToSpeech.OnInitListener {
    private val TAG = "TTSService"
    private var tts: TextToSpeech? = null
    private var isInitialized = false
    private var busNo: String = ""
    private var stationName: String = ""
    private var routeId: String = ""
    private var stationId: String = ""
    private var isTracking = false
    private var lastSpokenTime = 0L
    private val SPEAK_INTERVAL = 30000L // 30초마다 말하기
    
    companion object {
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "tts_service_channel"
        private const val CHANNEL_NAME = "TTS Service"
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "TTS 서비스 생성")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification("TTS 서비스 실행 중"))
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "TTS 서비스 시작: ${intent?.action}")
        
        when (intent?.action) {
            "START_TTS_TRACKING" -> {
                busNo = intent.getStringExtra("busNo") ?: ""
                stationName = intent.getStringExtra("stationName") ?: ""
                routeId = intent.getStringExtra("routeId") ?: ""
                stationId = intent.getStringExtra("stationId") ?: ""
                
                Log.d(TAG, "TTS 추적 시작: $busNo 번 버스, $stationName")
                
                if (!isInitialized) {
                    initializeTTS()
                } else {
                    startTracking()
                }
            }
            "REPEAT_TTS_ALERT" -> {
                busNo = intent.getStringExtra("busNo") ?: ""
                stationName = intent.getStringExtra("stationName") ?: ""
                routeId = intent.getStringExtra("routeId") ?: ""
                stationId = intent.getStringExtra("stationId") ?: ""
                
                Log.d(TAG, "TTS 알림 반복: $busNo 번 버스, $stationName")
                
                if (isInitialized) {
                    speakBusAlert()
                }
            }
            "STOP_TTS_TRACKING" -> {
                Log.d(TAG, "TTS 추적 중지")
                stopTracking()
                stopSelf()
            }
        }
        
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    override fun onDestroy() {
        Log.d(TAG, "TTS 서비스 종료")
        stopTracking()
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
    
    private fun initializeTTS() {
        Log.d(TAG, "TTS 초기화 시작")
        tts = TextToSpeech(this, this)
    }
    
    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            Log.d(TAG, "TTS 초기화 성공")
            
            val result = tts?.setLanguage(Locale.KOREAN)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.e(TAG, "한국어가 지원되지 않습니다")
            }
            
            tts?.setOnUtteranceProgressListener(object : OnUtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    Log.d(TAG, "TTS 발화 시작: $utteranceId")
                }
                
                override fun onDone(utteranceId: String?) {
                    Log.d(TAG, "TTS 발화 완료: $utteranceId")
                }
                
                override fun onError(utteranceId: String?) {
                    Log.e(TAG, "TTS 발화 오류: $utteranceId")
                }
            })
            
            isInitialized = true
            startTracking()
        } else {
            Log.e(TAG, "TTS 초기화 실패: $status")
        }
    }
    
    private fun startTracking() {
        if (!isInitialized) {
            Log.e(TAG, "TTS가 초기화되지 않았습니다")
            return
        }
        
        isTracking = true
        speakBusAlert()
    }
    
    private fun stopTracking() {
        isTracking = false
        tts?.stop()
    }
    
    private fun speakBusAlert() {
        // 이어폰/블루투스 이어셋 연결 여부 확인, 미연결 시 TTS 건너뜀
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val isWired = audioManager.isWiredHeadsetOn
        val isBt = audioManager.isBluetoothA2dpOn
        if (!isWired && !isBt) {
            Log.d(TAG, "🎧 이어셋 미연결 - TTS 발화 스킵")
            return
        }
        if (!isTracking || !isInitialized) {
            return
        }
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastSpokenTime < SPEAK_INTERVAL) {
            Log.d(TAG, "TTS 발화 간격이 너무 짧습니다. 건너뜁니다.")
            return
        }
        lastSpokenTime = currentTime

        val utteranceId = UUID.randomUUID().toString()
        val message = "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다."

        Log.d(TAG, "TTS 발화: $message")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            tts?.speak(message, TextToSpeech.QUEUE_FLUSH, null, utteranceId)
        } else {
            @Suppress("DEPRECATION")
            tts?.speak(message, TextToSpeech.QUEUE_FLUSH, null)
        }
    }
    
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "TTS 서비스 알림"
            }
            
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }
    
    private fun createNotification(content: String): Notification {
        val notificationIntent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            PendingIntent.FLAG_IMMUTABLE
        )
        
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("대구 버스 알림")
            .setContentText(content)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .build()
    }
} 