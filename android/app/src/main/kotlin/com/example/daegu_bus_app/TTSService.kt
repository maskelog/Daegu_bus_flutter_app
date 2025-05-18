package com.example.daegu_bus_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.AudioDeviceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
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
    private var remainingMinutes: Int = 0
    private var isTracking = false
    private var lastSpokenTime = 0L
    private val SPEAK_INTERVAL = 30000L // 30초마다 말하기
    
    // Handler for repeating TTS announcements
    private val ttsHandler = Handler(Looper.getMainLooper())
    private val ttsRunnable = object : Runnable {
        override fun run() {
            if (isTracking && isInitialized) {
                speakBusAlert()
                ttsHandler.postDelayed(this, SPEAK_INTERVAL)
            }
        }
    }
    
    companion object {
        private const val NOTIFICATION_ID = 1002
        private const val CHANNEL_ID = "tts_service_channel"
        private const val CHANNEL_NAME = "TTS Service"
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "[TTSService] onCreate 호출됨")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification("TTS 서비스 실행 중"))
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "[TTSService] onStartCommand: action=${intent?.action}, busNo=${intent?.getStringExtra("busNo")}, stationName=${intent?.getStringExtra("stationName")}, routeId=${intent?.getStringExtra("routeId")}, stationId=${intent?.getStringExtra("stationId")}")
        
        when (intent?.action) {
            "START_TTS_TRACKING" -> {
                busNo = intent.getStringExtra("busNo") ?: ""
                stationName = intent.getStringExtra("stationName") ?: ""
                routeId = intent.getStringExtra("routeId") ?: ""
                stationId = intent.getStringExtra("stationId") ?: ""
                remainingMinutes = intent.getIntExtra("remainingMinutes", remainingMinutes)
                
                Log.d(TAG, "TTS 추적 시작: $busNo 번 버스, $stationName, 남은시간=${remainingMinutes}분")
                
                isTracking = true
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
                remainingMinutes = intent.getIntExtra("remainingMinutes", remainingMinutes)
                
                Log.d(TAG, "TTS 알림 반복: $busNo 번 버스, $stationName, 남은시간=${remainingMinutes}분")
                
                if (isInitialized) {
                    speakBusAlert()
                }
            }
            "STOP_TTS_TRACKING" -> {
                Log.d(TAG, "TTS 추적 중지")
                isTracking = false
                // Stop periodic announcements
                ttsHandler.removeCallbacks(ttsRunnable)
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
        // Clean up handler callbacks
        isTracking = false
        ttsHandler.removeCallbacks(ttsRunnable)
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
            
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
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
        // schedule periodic announcements
        ttsHandler.removeCallbacks(ttsRunnable)
        ttsHandler.postDelayed(ttsRunnable, SPEAK_INTERVAL)
    }
    
    private fun stopTracking() {
        isTracking = false
        tts?.stop()
    }
    
    private fun getAudioOutputMode(): Int {
        val prefs = getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
        return prefs.getInt("speaker_mode", 0)
    }

    fun isHeadsetConnected(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            // 1. 기본 방식으로 체크 (이전 방식 - 안정성을 위해 유지)
            val isWired = audioManager.isWiredHeadsetOn
            val isA2dp = audioManager.isBluetoothA2dpOn
            val isSco = audioManager.isBluetoothScoOn
            
            // 2. Android 6 이상의 경우 AudioDeviceInfo로 더 정확하게 체크 (추가)
            var hasHeadset = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                if (devices != null) {
                    for (device in devices) {
                        val type = device.type
                        if (type == AudioDeviceInfo.TYPE_WIRED_HEADSET || 
                            type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                            type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                            type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            type == AudioDeviceInfo.TYPE_USB_HEADSET) {
                                hasHeadset = true
                                break
                        }
                    }
                }
                Log.d(TAG, "🎧 Modern headset check: hasHeadset=$hasHeadset")
            }
            
            // 두 방식 중 하나라도 헤드셋 연결을 감지하면 true 반환
            val isConnected = isWired || isA2dp || isSco || hasHeadset
            Log.d(TAG, "🎧 Headset status: Wired=$isWired, A2DP=$isA2dp, SCO=$isSco, Modern=$hasHeadset -> Connected=$isConnected")
            return isConnected
        } catch (e: Exception) {
            Log.e(TAG, "🎧 Error checking headset status: ${e.message}", e)
            return false
        }
    }
    
    private fun speakBusAlert() {
        val audioOutputMode = getAudioOutputMode()
        val headsetConnected = isHeadsetConnected()
        Log.d(TAG, "speakBusAlert() - 🎧 이어폰 체크: audioOutputMode=$audioOutputMode, headsetConnected=$headsetConnected, isTracking=$isTracking, isInitialized=$isInitialized")

        // Check if we should actually speak based on audio output mode and headset connection state
        if (audioOutputMode == 0 && !headsetConnected) { // 이어폰 전용 모드 & 이어폰 미연결
            Log.d(TAG, "🚫 이어폰 전용 모드, 이어폰이 연결되어 있지 않아 TTS 실행 안함")
            return
        } else if (audioOutputMode > 2) { // 알 수 없는 모드
            Log.d(TAG, "🚫 알 수 없는 오디오 출력 모드: $audioOutputMode, TTS 실행 안함")
            return
        }

        if (!isTracking || !isInitialized) {
            Log.w(TAG, "[TTSService] speakBusAlert: isTracking=$isTracking, isInitialized=$isInitialized. 발화 중단.")
            return
        }
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastSpokenTime < SPEAK_INTERVAL) {
            Log.d(TAG, "[TTSService] TTS 발화 간격이 너무 짧음. 건너뜀.")
            return
        }
        lastSpokenTime = currentTime

        val utteranceId = UUID.randomUUID().toString()
        val message = if (remainingMinutes > 0) {
            "$busNo 번 버스가 약 \\${remainingMinutes}분 후 도착 예정입니다."
        } else {
            "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다."
        }

        Log.d(TAG, "[TTSService] TTS 발화: $message, utteranceId=$utteranceId")

        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                val params = android.os.Bundle().apply {
                    putInt(android.speech.tts.TextToSpeech.Engine.KEY_PARAM_STREAM, android.media.AudioManager.STREAM_MUSIC)
                }
                tts?.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            } else {
                val params = HashMap<String, String>()
                params[android.speech.tts.TextToSpeech.Engine.KEY_PARAM_STREAM] = android.media.AudioManager.STREAM_MUSIC.toString()
                @Suppress("DEPRECATION")
                tts?.speak(message, TextToSpeech.QUEUE_FLUSH, params)
            }
        } catch (e: Exception) {
            Log.e(TAG, "[TTSService] TTS 발화 실패: \\${e.message}", e)
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