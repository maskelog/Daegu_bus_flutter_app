package com.example.daegu_bus_app.services

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
import com.example.daegu_bus_app.MainActivity
import com.example.daegu_bus_app.R
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
    private var lastAnnouncedMinutes: Int = -1 // 마지막으로 알린 분
    private val SPEAK_INTERVAL = 30000L // 30초마다 말하기
    private var ttsVolume: Float = 1.0f

    // 배터리 최적화를 위한 자동알람 모드
    private var isAutoAlarmMode = false
    private var autoAlarmForceSpeaker = false
    private var autoAlarmForceEarphone = false
    private var singleExecutionMode = false

    // Handler for repeating TTS announcements
    private val ttsHandler = Handler(Looper.getMainLooper())
    private val ttsRunnable = object : Runnable {
        override fun run() {
            if (isTracking && isInitialized) {
                speakBusAlert(forceSpeaker = autoAlarmForceSpeaker, forceEarphone = autoAlarmForceEarphone)
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
        // 저우선(무음) 포그라운드 알림으로 정책 충족 + 사용자 방해 최소화
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, createNotification("자동알람 음성 안내 중"))
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
                lastAnnouncedMinutes = -1 // Reset for new tracking session

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
                lastAnnouncedMinutes = -1 // Reset for new tracking session
                val isAutoAlarm = intent.getBooleanExtra("isAutoAlarm", false)
                val customMessage = intent.getStringExtra("ttsMessage")
                val isBackup = intent.getBooleanExtra("isBackup", false)
                val backupNumber = intent.getIntExtra("backupNumber", 0)
                singleExecutionMode = intent.getBooleanExtra("singleExecution", false)

                if (isBackup) {
                    Log.d(TAG, "🔊 백업 TTS 요청 ($backupNumber 번째): $busNo 번, $stationName")
                } else {
                    Log.d(TAG, "🔊 TTS 요청: $busNo 번, $stationName (자동알람: $isAutoAlarm, forceSpeaker: $forceSpeaker)")
                }

                // 자동 알람이거나 forceSpeaker인 경우 이어폰 체크 우회
                if (isAutoAlarm || forceSpeaker) {
                    Log.d(TAG, "🔊 자동 알람/강제 스피커 TTS 요청 - 이어폰 체크 우회")
                    isAutoAlarmMode = true
                    autoAlarmForceSpeaker = forceSpeaker
                    autoAlarmForceEarphone = isAutoAlarm && !forceSpeaker

                    if (isInitialized) {
                        handleAutoAlarmTTS(customMessage)
                    } else {
                        initializeTTS()
                        Handler(Looper.getMainLooper()).postDelayed({
                            if (isInitialized) {
                                handleAutoAlarmTTS(customMessage)
                            }
                        }, 1000)
                    }
                    return START_STICKY
                }

                // 일반 알람인 경우 이어폰 모드 체크
                val audioOutputMode = getAudioOutputMode()
                val headsetConnected = isHeadsetConnected()
                Log.d(TAG, "🔴 onStartCommand [REPEAT_TTS_ALERT] - audioOutputMode=$audioOutputMode, headsetConnected=$headsetConnected")
                if (audioOutputMode == BusAlertService.OUTPUT_MODE_HEADSET && !headsetConnected) {
                    Log.d(TAG, "🚫 이어폰 전용 모드($audioOutputMode), 이어폰이 연결되어 있지 않아 TTS 실행 안함")
                    return START_STICKY
                }

                if (isInitialized) {
                    speakBusAlert(customMessage = customMessage)
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
                    Log.d(TAG, "TTS 발화 완료: $utteranceId")
                }

                override fun onError(utteranceId: String?) {
                    Log.e(TAG, "TTS 발화 오류: $utteranceId")
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

        // 단일 실행 모드인 경우에만 반복 안함 (자동 알람은 반복 허용)
        if (singleExecutionMode) {
            Log.d(TAG, "🔊 단일실행 모드: 반복 TTS 없음")
            speakBusAlert(forceSpeaker = autoAlarmForceSpeaker, forceEarphone = autoAlarmForceEarphone)
            return
        }

        isTracking = true
        speakBusAlert(forceSpeaker = autoAlarmForceSpeaker, forceEarphone = autoAlarmForceEarphone) // 자동 알람 설정값 적용
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
                            device.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                            device.type == AudioDeviceInfo.TYPE_USB_DEVICE || // USB 오디오 장치 추가
                            device.type == AudioDeviceInfo.TYPE_BLE_HEADSET || // BLE 헤드셋 추가
                            device.type == AudioDeviceInfo.TYPE_HEARING_AID) { // 보청기 추가
                            hasHeadset = true
                        }
                    }
                }
                Log.d(TAG, "🎧 Modern headset check: hasHeadset=$hasHeadset")
            }

            // 하나라도 연결되어 있으면 true
            val isConnected = isWired || isA2dp || isSco || hasHeadset
            Log.d(TAG, "🎧 Headset status: Wired=$isWired, A2DP=$isA2dp, SCO=$isSco, Modern=$hasHeadset -> Connected=$isConnected")
            return isConnected
        } catch (e: Exception) {
            Log.e(TAG, "🎧 Error checking headset status: ${e.message}", e)
            // 오류 발생 시 안전하게 false 반환 (또는 true로 하여 TTS가 나오게 할 수도 있음 - 정책 결정 필요)
            return false 
        }
    }

    private fun speakBusAlert(forceSpeaker: Boolean = false, forceEarphone: Boolean = false, customMessage: String? = null) {
        // 초기화 확인
        if (!isInitialized) {
            Log.e(TAG, "❌ TTS가 초기화되지 않았습니다. 초기화 시도...")
            initializeTTS()
            return
        }

        // 자동 알람이 아닌 경우에만 이어폰 체크
        if (!forceSpeaker) {
            val audioOutputMode = getAudioOutputMode()
            val headsetConnected = isHeadsetConnected()

            // 이어폰 전용 모드인데 이어폰이 연결되어 있지 않으면 실행 안함
            if (audioOutputMode == BusAlertService.OUTPUT_MODE_HEADSET && !headsetConnected) {
                Log.d(TAG, "🚫 이어폰 전용 모드($audioOutputMode)이나 이어폰이 연결되어 있지 않아 TTS 실행 안함")
                return
            }
        } else {
            Log.d(TAG, "🔊 강제 스피커 모드로 TTS 실행 (이어폰 체크 무시)")
        }

        // 발화 간격 체크 (자동 알람은 무시)
        val currentTime = System.currentTimeMillis()
        if (!forceSpeaker && currentTime - lastSpokenTime < SPEAK_INTERVAL) {
            Log.d(TAG, "⏱️ 발화 간격이 너무 짧습니다. 무시합니다.")
            return
        }
        lastSpokenTime = currentTime

        // remainingMinutes가 변경되었을 때만 발화
        val currentRemainingMinutes = remainingMinutes // 현재 remainingMinutes 값
        if (currentRemainingMinutes == lastAnnouncedMinutes && customMessage.isNullOrEmpty()) {
            Log.d(TAG, "⏱️ remainingMinutes가 변경되지 않아 TTS 발화 무시: $currentRemainingMinutes 분")
            return
        }
        lastAnnouncedMinutes = currentRemainingMinutes // 마지막으로 알린 분 업데이트

        // 스피커 사용 여부 결정
        val useSpeaker = if (forceEarphone) false else (forceSpeaker || getAudioOutputMode() == OUTPUT_MODE_SPEAKER)

        // 오디오 설정
        val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        try {
            // 스피커 모드 설정
            audioManager.isSpeakerphoneOn = useSpeaker

            // 사용자 피드백 반영: 볼륨 강제 최대화 로직 제거
            // 사용자가 설정한 시스템 알람 볼륨 또는 앱 내 TTS 볼륨 설정을 따름
            /*
            if (forceSpeaker) {
                val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                audioManager.setStreamVolume(
                    AudioManager.STREAM_ALARM,
                    (maxVolume * 0.9).toInt(), // 최대 볼륨의 90%
                    0
                )
                Log.d(TAG, "🔊 자동 알람 볼륨 설정 (STREAM_ALARM): ${(maxVolume * 0.9).toInt()}/${maxVolume}")
            }
            */
        } catch (e: Exception) {
            Log.e(TAG, "❌ 오디오 설정 오류: ${e.message}")
        }

        // TTS 파라미터 설정
        val streamType = if (forceSpeaker) AudioManager.STREAM_ALARM else if (forceEarphone) AudioManager.STREAM_MUSIC else if (getAudioOutputMode() == OUTPUT_MODE_SPEAKER) AudioManager.STREAM_ALARM else AudioManager.STREAM_MUSIC
        val utteranceId = "tts_${System.currentTimeMillis()}"
        val volume = getTtsVolume()

        val params = android.os.Bundle().apply {
            putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
            putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, streamType)
            putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
        }

        // 메시지 생성 (커스텀 메시지가 있으면 사용, 없으면 기본 메시지)
        val message = if (!customMessage.isNullOrEmpty()) {
            customMessage
        } else if (remainingMinutes > 0) {
            "$busNo 번 버스가 약 ${remainingMinutes}분 후 도착 예정입니다."
        } else if (remainingMinutes == 0) {
            "$busNo 번 버스가 곧 도착합니다."
        } else {
            // remainingMinutes가 -1이거나 유효하지 않은 경우 (초기 상태 등)
            // "잠시 후 도착 정보를 안내합니다" 또는 아무 말도 안 하거나, 상황에 맞게 처리
            // 여기서는 일단 로그만 남기고 발화하지 않거나, "정보를 가져오는 중입니다"라고 안내
            Log.w(TAG, "⚠️ 남은 시간 정보 없음 ($remainingMinutes), 기본 메시지 사용 안함")
            return 
        }

        // TTS 발화
        val streamName = if (streamType == AudioManager.STREAM_ALARM) "ALARM" else "MUSIC"
        Log.i(TAG, "🔊 TTS 발화: $message, 스피커=$useSpeaker, 볼륨=$volume, forceSpeaker=$forceSpeaker, 스트림=$streamName")
        try {
            tts?.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
        } catch (e: Exception) {
            Log.e(TAG, "❌ TTS 발화 실패: ${e.message}", e)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_MIN // 최저 중요도
            ).apply {
                description = "자동알람 TTS 알림 (저우선)"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_SECRET
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
            .setContentTitle("자동알람 음성 안내")
            .setContentText(content)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .build()
    }

    private fun getTtsVolume(): Float {
        val prefs = getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
        return prefs.getFloat("tts_volume", 1.0f).coerceIn(0f, 1f)
    }

    /**
     * 배터리 최적화된 자동알람 TTS 처리
     * - 한 번만 발화
     * - 강제 스피커 모드
     * - 즉시 서비스 종료
     */
    private fun handleAutoAlarmTTS(customMessage: String?) {
        try {
            Log.d(TAG, "🔊 자동알람 TTS 처리 시작")

            // 자동알람 설정에 맞춰서 발화 (강요스피커/이어폰 등)
            speakBusAlert(forceSpeaker = autoAlarmForceSpeaker, forceEarphone = autoAlarmForceEarphone, customMessage = customMessage)

            // 사용자 피드백 반영: 자동 알람은 사용자가 중지할 때까지 계속되어야 하므로
            // 서비스 종료(stopSelf) 코드를 제거하고, 반복 발화가 유지되도록 함.
            
            // 반복 발화를 위해 핸들러 작동 확인
            if (!ttsHandler.hasCallbacks(ttsRunnable)) {
                Log.d(TAG, "🔊 자동알람 반복 발화 스케줄링 시작")
                ttsHandler.postDelayed(ttsRunnable, SPEAK_INTERVAL)
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ 자동알람 TTS 처리 오류: ${e.message}", e)
        }
    }
}