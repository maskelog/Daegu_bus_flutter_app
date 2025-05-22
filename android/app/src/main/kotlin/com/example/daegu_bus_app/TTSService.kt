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
    private var ttsVolume: Float = 1.0f
    
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
        private const val OUTPUT_MODE_HEADSET = 0
        private const val OUTPUT_MODE_SPEAKER = 1
        private const val OUTPUT_MODE_AUTO = 2
    }
    
    override fun onCreate() {
        super.onCreate()
        Log.e(TAG, "🔴 [중요] AppSettings 확인: speaker_mode=${getAudioOutputMode()}, TTSService_HEADSET_MODE=$OUTPUT_MODE_HEADSET, BusService_HEADSET_MODE=${BusAlertService.OUTPUT_MODE_HEADSET}")
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification("TTS 서비스 실행 중"))
    }
    
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Log.d(TAG, "[TTSService] onStartCommand: action=${intent?.action}, busNo=${intent?.getStringExtra("busNo")}, stationName=${intent?.getStringExtra("stationName")}, routeId=${intent?.getStringExtra("routeId")}, stationId=${intent?.getStringExtra("stationId")}")
        
        val forceSpeaker = intent?.getBooleanExtra("forceSpeaker", false) ?: false
        when (intent?.action) {
            "START_TTS_TRACKING" -> {
                busNo = intent.getStringExtra("busNo") ?: ""
                stationName = intent.getStringExtra("stationName") ?: ""
                routeId = intent.getStringExtra("routeId") ?: ""
                stationId = intent.getStringExtra("stationId") ?: ""
                remainingMinutes = intent.getIntExtra("remainingMinutes", remainingMinutes)
                
                // 이어폰 전용 모드 & 이어폰 미연결 시 TTS 실행 금지
                val audioOutputMode = getAudioOutputMode()
                val headsetConnected = isHeadsetConnected()
                Log.e(TAG, "🔴 onStartCommand [START_TTS_TRACKING] - audioOutputMode=$audioOutputMode, headsetConnected=$headsetConnected, OUTPUT_MODE_HEADSET=$OUTPUT_MODE_HEADSET, BusAlertService.OUTPUT_MODE_HEADSET=${BusAlertService.OUTPUT_MODE_HEADSET}")
                if (audioOutputMode == BusAlertService.OUTPUT_MODE_HEADSET && !headsetConnected) {
                    Log.e(TAG, "🚫 [정책 로깅] 이어폰 전용 모드($audioOutputMode), 이어폰이 연결되어 있지 않아 TTS 실행 안함 (onStartCommand: START_TTS_TRACKING)")
                    return START_STICKY
                }
                
                // Log.d(TAG, "TTS 추적 시작: $busNo 번 버스, $stationName, 남은시간=${remainingMinutes}분")
                
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
                
                // 이어폰 전용 모드 & 이어폰 미연결 시 TTS 실행 금지
                val audioOutputMode = getAudioOutputMode()
                val headsetConnected = isHeadsetConnected()
                Log.e(TAG, "🔴 onStartCommand [REPEAT_TTS_ALERT] - audioOutputMode=$audioOutputMode, headsetConnected=$headsetConnected, OUTPUT_MODE_HEADSET=$OUTPUT_MODE_HEADSET, BusAlertService.OUTPUT_MODE_HEADSET=${BusAlertService.OUTPUT_MODE_HEADSET}")
                if (audioOutputMode == BusAlertService.OUTPUT_MODE_HEADSET && !headsetConnected) {
                    Log.e(TAG, "🚫 [정책 로깅] 이어폰 전용 모드($audioOutputMode), 이어폰이 연결되어 있지 않아 TTS 실행 안함 (onStartCommand: REPEAT_TTS_ALERT)")
                    return START_STICKY
                }
                
                // Log.d(TAG, "TTS 알림 반복: $busNo 번 버스, $stationName, 남은시간=${remainingMinutes}분")
                
                if (isInitialized) {
                    speakBusAlert()
                }
            }
            "STOP_TTS_TRACKING" -> {
                // Log.d(TAG, "TTS 추적 중지")
                isTracking = false
                // Stop periodic announcements
                ttsHandler.removeCallbacks(ttsRunnable)
                stopTracking()
                stopSelf()
            }
        }
        
        if (forceSpeaker) {
            // 이어폰 체크 무시, 무조건 스피커로 발화
            isTracking = true
            if (!isInitialized) {
                initializeTTS()
            } else {
                speakBusAlert(forceSpeaker = true)
            }
            return START_STICKY
        }
        
        return START_STICKY
    }
    
    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    override fun onDestroy() {
        // Log.d(TAG, "TTS 서비스 종료")
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
        // Log.d(TAG, "TTS 초기화 시작")
        tts = TextToSpeech(this, this)
    }
    
    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            // Log.d(TAG, "TTS 초기화 성공")
            
            val result = tts?.setLanguage(Locale.KOREAN)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                // Log.e(TAG, "한국어가 지원되지 않습니다")
            }
            
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    // Log.d(TAG, "TTS 발화 시작: $utteranceId")
                }
                
                override fun onDone(utteranceId: String?) {
                    // Log.d(TAG, "TTS 발화 완료: $utteranceId")
                }

                override fun onError(utteranceId: String?) {
                    // Log.e(TAG, "TTS 발화 오류: $utteranceId")
                }
            })
            
            isInitialized = true
            startTracking()
        } else {
            // Log.e(TAG, "TTS 초기화 실패: $status")
        }
    }
    
    private fun startTracking() {
        if (!isInitialized) {
            // Log.e(TAG, "TTS가 초기화되지 않았습니다")
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
        val mode = prefs.getInt("speaker_mode", 0)
        Log.e(TAG, "🔴 getAudioOutputMode: AppSettings:speaker_mode=$mode, OUTPUT_MODE_HEADSET=$OUTPUT_MODE_HEADSET, BusService.OUTPUT_MODE_HEADSET=${BusAlertService.OUTPUT_MODE_HEADSET}")
        // 상수 불일치 문제 수정: BusAlertService에서는 OUTPUT_MODE_HEADSET=2, 여기서는 OUTPUT_MODE_HEADSET=2
        // 이어폰 전용모드인지 확인
        return mode
    }

    fun isHeadsetConnected(): Boolean {
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            val isWired = audioManager.isWiredHeadsetOn
            val isA2dp = audioManager.isBluetoothA2dpOn
            val isSco = audioManager.isBluetoothScoOn

            var hasHeadset = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                if (devices != null) {
                    Log.d(TAG, "[DEBUG] AudioDeviceInfo 목록:")
                    for (device in devices) {
                        Log.d(TAG, "[DEBUG] AudioDeviceInfo: type=${device.type}, productName=${device.productName}, id=${device.id}, isSink=${device.isSink}")
                        if (device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                            device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            device.type == AudioDeviceInfo.TYPE_USB_HEADSET) {
                            hasHeadset = true
                        }
                    }
                }
                Log.d(TAG, "🎧 Modern headset check: hasHeadset=$hasHeadset")
            }

            val isConnected = isWired || isA2dp || isSco || hasHeadset
            Log.d(TAG, "🎧 Headset status: Wired=$isWired, A2DP=$isA2dp, SCO=$isSco, Modern=$hasHeadset -> Connected=$isConnected")
            return isConnected
        } catch (e: Exception) {
            Log.e(TAG, "🎧 Error checking headset status: ${e.message}", e)
            return false
        }
    }
    
    private fun speakBusAlert(forceSpeaker: Boolean = false) {
        val audioOutputMode = getAudioOutputMode()
        val headsetConnected = isHeadsetConnected()
        // forceSpeaker가 true면 이어폰 체크 및 방어 로직 무시
        if (!forceSpeaker && audioOutputMode == BusAlertService.OUTPUT_MODE_HEADSET && !headsetConnected) {
            Log.e(TAG, "🚫 [최종방어] 이어폰 전용 모드($audioOutputMode)이나 이어폰이 연결되어 있지 않아 TTS 실행 안함 (speakBusAlert 마지막)");
            return;
        }
        if (!isTracking || !isInitialized) {
            return
        }
        val currentTime = System.currentTimeMillis()
        if (currentTime - lastSpokenTime < SPEAK_INTERVAL) {
            return
        }
        lastSpokenTime = currentTime
        val useSpeaker = if (forceSpeaker) true else when (audioOutputMode) {
            OUTPUT_MODE_SPEAKER -> true
            OUTPUT_MODE_HEADSET -> false
            OUTPUT_MODE_AUTO -> !isHeadsetConnected()
            else -> !isHeadsetConnected()
        }
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager.isSpeakerphoneOn = useSpeaker
        val streamType = if (useSpeaker) android.media.AudioManager.STREAM_ALARM else android.media.AudioManager.STREAM_MUSIC
        val utteranceId = "tts_${System.currentTimeMillis()}"
        val volume = getTtsVolume()
        val params = android.os.Bundle().apply {
            putString(android.speech.tts.TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
            putInt(android.speech.tts.TextToSpeech.Engine.KEY_PARAM_STREAM, streamType)
            putFloat(android.speech.tts.TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
        }
        val message = if (remainingMinutes > 0) {
            "$busNo 번 버스가 약 ${remainingMinutes}분 후 도착 예정입니다."
        } else {
            "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다."
        }
        if (!forceSpeaker && audioOutputMode == BusAlertService.OUTPUT_MODE_HEADSET && !isHeadsetConnected()) {
            Log.e(TAG, "🚫 [발화 직전 최종방어] 이어폰 전용 모드($audioOutputMode)이나 이어폰이 연결되어 있지 않아 TTS 발화 취소");
            return;
        }
        Log.i(TAG, "TTS 발화: $message, outputMode=$audioOutputMode, headset=${isHeadsetConnected()}, utteranceId=$utteranceId, forceSpeaker=$forceSpeaker")
        try {
            tts?.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        } catch (e: Exception) {
            Log.e(TAG, "[TTSService] TTS 발화 실패: ${e.message}", e)
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

    private fun getTtsVolume(): Float {
        val prefs = getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
        return prefs.getFloat("tts_volume", 1.0f).coerceIn(0f, 1f)
    }
} 