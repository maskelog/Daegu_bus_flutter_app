package com.example.daegu_bus_app.services

import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import java.util.Locale

class BusAlertTtsController(
    private val context: Context,
    private val onEngineInitStateChanged: (Boolean) -> Unit,
) {
    companion object {
        private const val TAG = "BusAlertService"
        private const val OUTPUT_MODE_HEADSET = 0
        private const val OUTPUT_MODE_SPEAKER = 1
        private const val OUTPUT_MODE_AUTO = 2
    }

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        Log.d(TAG, "Audio focus changed: $focusChange")
    }

    private var audioFocusRequest: AudioFocusRequest? = null
    private var ttsEngine: TextToSpeech? = null
    private var isTtsInitialized = false
    private val ttsInitializationLock = Any()
    private var audioOutputMode: Int = OUTPUT_MODE_AUTO
    private var useTextToSpeech: Boolean = true
    private var ttsVolume: Float = 1.0f

    fun setAudioOutputMode(mode: Int) {
        audioOutputMode = mode
    }

    fun setUseTts(useTts: Boolean) {
        useTextToSpeech = useTts
    }

    fun setTtsVolume(volume: Float) {
        ttsVolume = volume.coerceIn(0f, 1f)
    }

    fun initializeTts() {
        if (isTtsInitialized || ttsEngine != null) return
        synchronized(ttsInitializationLock) {
            if (isTtsInitialized || ttsEngine != null) return
            Log.d(TAG, "🔊 TTS 엔진 초기화 중...")
            try {
                ttsEngine = TextToSpeech(context, TextToSpeech.OnInitListener { status ->
                    if (status == TextToSpeech.SUCCESS) {
                        val result = ttsEngine?.setLanguage(Locale.KOREAN)
                        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                            Log.w(TAG, "🔊 한국어 TTS 미지원, TTS 비활성화")
                            cleanupTts()
                        } else {
                            ttsEngine?.setPitch(1.0f)
                            ttsEngine?.setSpeechRate(1.0f)
                            isTtsInitialized = true
                            onEngineInitStateChanged(true)
                            Log.i(TAG, "✅ TTS 엔진 초기화 완료")
                        }
                    } else {
                        Log.w(TAG, "🔊 TTS 초기화 실패: $status")
                        cleanupTts()
                    }
                })
            } catch (e: Exception) {
                Log.e(TAG, "❌ TTS 초기화 오류: ${e.message}")
                cleanupTts()
            }
        }
    }

    fun cleanupTts() {
        try {
            ttsEngine?.stop()
            ttsEngine?.shutdown()
            ttsEngine = null
            isTtsInitialized = false
            onEngineInitStateChanged(false)
            Log.d(TAG, "TTS 리소스 정리 완료")
        } catch (e: Exception) {
            Log.e(TAG, "TTS 정리 오류: ${e.message}")
        }
    }

    fun stopTtsServiceTracking() {
        try {
            val ttsIntent = Intent(context, TTSService::class.java).apply {
                action = "STOP_TTS_TRACKING"
            }
            context.startService(ttsIntent)
            Log.d(TAG, "Requested TTSService to stop tracking (all)")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping TTSService tracking: ${e.message}", e)
        }
    }

    fun startTtsServiceSpeak(
        busNo: String,
        stationName: String,
        routeId: String,
        stationId: String,
        remainingMinutes: Int = -1,
        forceSpeaker: Boolean = false,
        currentStation: String? = null,
    ) {
        val isHeadset = isHeadsetConnected()
        if (!forceSpeaker && audioOutputMode == OUTPUT_MODE_HEADSET && !isHeadset) {
            Log.w(TAG, "이어폰 전용 모드이나 이어폰이 연결되어 있지 않아 TTSService 호출 안함 (audioOutputMode=$audioOutputMode, isHeadset=$isHeadset)")
            return
        }

        val ttsIntent = Intent(context, TTSService::class.java).apply {
            action = "REPEAT_TTS_ALERT"
            putExtra("busNo", busNo)
            putExtra("stationName", stationName)
            putExtra("routeId", routeId)
            putExtra("stationId", stationId)
            putExtra("remainingMinutes", remainingMinutes)
            putExtra("currentStation", (currentStation ?: "").toString())
            if (forceSpeaker) putExtra("forceSpeaker", true)
        }
        context.startService(ttsIntent)
    }

    fun speakTts(text: String, earphoneOnly: Boolean = false, forceSpeaker: Boolean = false) {
        Log.d(TAG, "🎧 speakTts 이어폰 체크 시작: earphoneOnly=$earphoneOnly, audioOutputMode=$audioOutputMode, forceSpeaker=$forceSpeaker")
        val headsetConnected = isHeadsetConnected()

        if (!forceSpeaker) {
            if (audioOutputMode == OUTPUT_MODE_HEADSET && !headsetConnected) {
                Log.w(TAG, "🚫 이어폰 전용 모드이나 이어폰이 연결되어 있지 않아 TTS 실행 안함 (BusAlertService)")
                return
            }
            if (earphoneOnly && !headsetConnected) {
                Log.w(TAG, "🚫 earphoneOnly=true인데 이어폰이 연결되어 있지 않아 TTS 실행 안함 (BusAlertService)")
                return
            }
        } else {
            Log.d(TAG, "🔊 강제 스피커 모드 - 이어폰 체크 무시")
        }

        if (!isTtsInitialized || ttsEngine == null) {
            Log.e(TAG, "🔊 TTS speak failed - engine not ready")
            initializeTts()
            return
        }
        if (!useTextToSpeech) {
            Log.d(TAG, "🔊 TTS speak skipped - disabled in settings.")
            return
        }
        if (text.isBlank()) {
            Log.w(TAG, "🔊 TTS speak skipped - empty text")
            return
        }

        try {
            val latestHeadsetConnected = isHeadsetConnected()
            if (!forceSpeaker && audioOutputMode == OUTPUT_MODE_HEADSET && !latestHeadsetConnected) {
                Log.w(TAG, "🚫 [발화 직전 최종방어] 이어폰 전용 모드이나 이어폰이 연결되어 있지 않아 TTS 실행 안함")
                return
            }

            val useSpeaker = if (forceSpeaker) {
                true
            } else {
                when (audioOutputMode) {
                    OUTPUT_MODE_SPEAKER -> true
                    OUTPUT_MODE_HEADSET -> false
                    OUTPUT_MODE_AUTO -> !latestHeadsetConnected
                    else -> !latestHeadsetConnected
                }
            }

            val streamType = if (forceSpeaker) {
                AudioManager.STREAM_ALARM
            } else if (audioOutputMode == OUTPUT_MODE_HEADSET) {
                AudioManager.STREAM_MUSIC
            } else if (useSpeaker) {
                AudioManager.STREAM_ALARM
            } else {
                AudioManager.STREAM_MUSIC
            }

            Log.d(TAG, "🔊 Preparing TTS: Stream=${if (streamType == AudioManager.STREAM_ALARM) "ALARM" else "MUSIC"}, Speaker=$useSpeaker, Mode=$audioOutputMode, ForceSpeaker=$forceSpeaker")

            val utteranceId = "tts_${System.currentTimeMillis()}"
            val params = android.os.Bundle().apply {
                putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, streamType)
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, ttsVolume)
            }

            audioManager.isSpeakerphoneOn = useSpeaker

            val focusResult = requestAudioFocus(useSpeaker)
            Log.d(TAG, "🔊 Audio focus request result: $focusResult")

            if (!forceSpeaker && audioOutputMode == OUTPUT_MODE_HEADSET && !isHeadsetConnected()) {
                Log.w(TAG, "🚫 [발화 직전 최종방어-재확인] 이어폰 전용 모드이나 이어폰이 연결되어 있지 않아 TTS 발화 취소")
                audioManager.abandonAudioFocus(audioFocusListener)
                return
            }

            if (focusResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                Log.d(TAG, "🔊 Audio focus granted. Speaking.")
                ttsEngine?.setOnUtteranceProgressListener(createTtsListener())
                Log.i(TAG, "TTS 발화: $text, outputMode=$audioOutputMode, headset=${isHeadsetConnected()}, utteranceId=$utteranceId")
                ttsEngine?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
            } else {
                Log.e(TAG, "🔊 Audio focus request failed ($focusResult). Speak cancelled.")
                audioManager.abandonAudioFocus(audioFocusListener)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ TTS speak error: ${e.message}", e)
            audioManager.abandonAudioFocus(audioFocusListener)
        }
    }

    fun abandonAudioFocus() {
        try {
            audioManager.abandonAudioFocus(audioFocusListener)
        } catch (e: Exception) {
            Log.e(TAG, "오디오 포커스 해제 오류: ${e.message}")
        }
    }

    fun isHeadsetConnected(): Boolean {
        try {
            val isWired = audioManager.isWiredHeadsetOn
            val isA2dp = audioManager.isBluetoothA2dpOn
            val isSco = audioManager.isBluetoothScoOn

            var hasHeadset = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                for (device in devices) {
                    val type = device.type
                    if (type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                        type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                        type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                        type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                        type == android.media.AudioDeviceInfo.TYPE_USB_HEADSET
                    ) {
                        hasHeadset = true
                        break
                    }
                }
            }

            val isConnected = isWired || isA2dp || isSco || hasHeadset
            Log.d(TAG, "🎧 Headset status: Wired=$isWired, A2DP=$isA2dp, SCO=$isSco, Modern=$hasHeadset -> Connected=$isConnected")
            return isConnected
        } catch (e: Exception) {
            Log.e(TAG, "🎧 Error checking headset status: ${e.message}", e)
            return false
        }
    }

    private fun requestAudioFocus(useSpeaker: Boolean): Int {
        val streamType = if (useSpeaker) AudioManager.STREAM_ALARM else AudioManager.STREAM_MUSIC
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val usage = if (useSpeaker) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(usage)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(audioAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener(audioFocusListener)
                .build()
            audioManager.requestAudioFocus(audioFocusRequest!!)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(
                audioFocusListener, streamType, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            )
        }
    }

    private fun createTtsListener(): UtteranceProgressListener {
        return object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                Log.d(TAG, "TTS Start: $utteranceId")
            }

            override fun onDone(utteranceId: String?) {
                Log.d(TAG, "TTS Done: $utteranceId")
                audioManager.abandonAudioFocus(audioFocusListener)
            }

            override fun onError(utteranceId: String?) {
                Log.e(TAG, "TTS Error: $utteranceId")
                audioManager.abandonAudioFocus(audioFocusListener)
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                Log.e(TAG, "TTS Error: $utteranceId, Code: $errorCode")
                audioManager.abandonAudioFocus(audioFocusListener)
            }
        }
    }
}
