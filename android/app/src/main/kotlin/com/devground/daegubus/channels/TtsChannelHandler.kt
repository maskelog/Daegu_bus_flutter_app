package com.devground.daegubus.channels

import android.content.Context
import android.util.Log
import com.devground.daegubus.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * com.devground.daegubus/tts 채널 핸들러.
 * TTS 발화·오디오 출력 모드·볼륨·알람 소리 설정을 BusAlertService로 전달한다.
 * BusAlertService가 아직 바인딩되지 않은 경우 MainActivity의 폴백 TTS를 사용한다.
 */
class TtsChannelHandler(private val activity: MainActivity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "TtsChannel"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "speakTTS" -> {
                val message = call.argument<String>("message") ?: ""
                val isHeadphoneMode = call.argument<Boolean>("isHeadphoneMode") ?: false
                val forceSpeaker = call.argument<Boolean>("forceSpeaker") ?: false
                if (message.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "메시지가 비어있습니다", null)
                    return
                }
                try {
                    val busAlertService = activity.busAlertService
                    if (busAlertService != null) {
                        // 강제 스피커 모드인 경우 이어폰 체크 무시
                        if (forceSpeaker) {
                            Log.d(TAG, "🔊 강제 스피커 모드로 TTS 발화: $message")
                            busAlertService.speakTts(message, earphoneOnly = false, forceSpeaker = true)
                        } else {
                            // BusAlertService의 speakTts 호출 (오디오 포커스 관리 포함)
                            busAlertService.speakTts(message, earphoneOnly = isHeadphoneMode, forceSpeaker = false)
                        }
                    } else {
                        // BusAlertService가 null인 경우 MainActivity의 TTS 사용
                        activity.speakFallbackTts(message)
                    }
                    result.success(true) // 비동기 호출이므로 일단 성공으로 응답
                } catch (e: Exception) {
                    Log.e(TAG, "TTS 발화 오류: ${e.message}", e)
                    result.success(true) // TTS 실패도 성공으로 처리
                }
            }
            "setAudioOutputMode" -> {
                val mode = call.argument<Int>("mode") ?: 2
                try {
                    if (activity.busAlertService != null) {
                        activity.busAlertService?.setAudioOutputMode(mode)
                    } else {
                        Log.d(TAG, "오디오 출력 모드 설정 요청 (대안): $mode")
                    }
                    Log.d(TAG, "오디오 출력 모드 설정 요청: $mode")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "오디오 모드 설정 오류: ${e.message}", e)
                    result.success(true)
                }
            }
            "setVolume" -> {
                val volume = call.argument<Double>("volume") ?: 1.0
                try {
                    if (activity.busAlertService != null) {
                        activity.busAlertService?.setTtsVolume(volume)
                    } else {
                        Log.d(TAG, "TTS 볼륨 설정 (대안): ${volume * 100}%")
                    }
                    Log.d(TAG, "TTS 볼륨 설정: ${volume * 100}%")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "볼륨 설정 오류: ${e.message}")
                    result.success(true)
                }
            }
            "setUseTts" -> {
                val useTts = call.argument<Boolean>("useTts") ?: true
                try {
                    if (activity.busAlertService != null) {
                        // Flutter가 FlutterSharedPreferences에 이미 저장했으므로 loadSettings()로 재읽기
                        val flutterPrefs = activity.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        val currentSound = flutterPrefs.getString("flutter.alarm_sound", "tts") ?: "tts"
                        activity.busAlertService?.setAlarmSound(currentSound, useTts)
                    }
                    Log.d(TAG, "TTS 사용 설정: $useTts")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "TTS 사용 설정 오류: ${e.message}")
                    result.success(true)
                }
            }
            "setAlarmSound" -> {
                val soundId = call.argument<String>("soundId") ?: "tts"
                try {
                    val useTts = soundId == "tts"
                    if (activity.busAlertService != null) {
                        activity.busAlertService?.setAlarmSound(soundId, useTts)
                    }
                    Log.d(TAG, "알람 소리 설정: $soundId (TTS: $useTts)")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "알람 소리 설정 오류: ${e.message}")
                    result.success(true)
                }
            }
            "setAlertOnArrivalOnly" -> {
                val value = call.argument<Boolean>("value") ?: false
                try {
                    activity.busAlertService?.setAlertOnArrivalOnly(value)
                    Log.d(TAG, "도착 임박 시에만 알림 설정: $value")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "도착 임박 알림 설정 오류: ${e.message}")
                    result.success(true)
                }
            }
            else -> result.notImplemented()
        }
    }
}
