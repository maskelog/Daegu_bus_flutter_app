package com.devground.daegubus.channels

import android.content.Intent
import android.util.Log
import com.devground.daegubus.MainActivity
import com.devground.daegubus.services.TTSService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** bus_api 채널의 기존 에러 응답 시맨틱을 보존하는 TTS 위임 작업. */
internal class BusApiTtsOperations(private val activity: MainActivity) {

    companion object {
        private const val TAG = "BusApiChannel"
    }

    fun startTtsTracking(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        val stationId = call.argument<String>("stationId") ?: ""
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
        if (routeId.isEmpty() || stationId.isEmpty() || busNo.isEmpty() || stationName.isEmpty()) {
            result.error("INVALID_ARGUMENT", "startTtsTracking requires routeId, stationId, busNo, stationName", null)
            return
        }
        try {
            val ttsIntent = Intent(activity, TTSService::class.java).apply {
                action = "START_TTS_TRACKING"
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("remainingMinutes", remainingMinutes)
            }
            // 포그라운드 알림 제거 요구사항에 따라 일반 Service로 실행
            activity.startService(ttsIntent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "startTtsTracking 호출 오류: ${e.message}", e)
            result.error("TTS_ERROR", "startTtsTracking 실패: ${e.message}", null)
        }
    }

    fun speakTTS(call: MethodCall, result: MethodChannel.Result) {
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

    fun setAudioOutputMode(call: MethodCall, result: MethodChannel.Result) {
        val mode = call.argument<Int>("mode") ?: 2 // Default to Auto
        try {
            Log.i(TAG, "Flutter에서 오디오 출력 모드 변경 요청: $mode")
            activity.busAlertService?.setAudioOutputMode(mode)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "오디오 출력 모드 변경 오류: ${e.message}", e)
            result.error("SET_MODE_ERROR", "오디오 출력 모드 변경 실패: ${e.message}", null)
        }
    }

    fun setVolume(call: MethodCall, result: MethodChannel.Result) {
        val volume = call.argument<Double>("volume") ?: 1.0
        try {
            Log.i(TAG, "Flutter에서 TTS 볼륨 변경 요청: $volume")
            activity.busAlertService?.setTtsVolume(volume)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "TTS 볼륨 변경 오류: ${e.message}", e)
            result.error("SET_VOLUME_ERROR", "TTS 볼륨 변경 실패: ${e.message}", null)
        }
    }

    fun stopTTS(result: MethodChannel.Result) {
        try {
            if (activity.busAlertService != null) {
                // BusAlertService의 stopTtsTracking을 호출하여 TTS 중지
                activity.busAlertService?.stopTtsTracking(forceStop = true)
            } else {
                // MainActivity TTS 중지
                activity.stopFallbackTts()
            }
            Log.d(TAG, "네이티브 TTS 중지 요청")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "TTS 중지 오류: ${e.message}", e)
            result.success(true)
        }
    }

    fun isHeadphoneConnected(result: MethodChannel.Result) {
        try {
            val isConnected = if (activity.busAlertService != null) {
                activity.busAlertService?.isHeadsetConnected() ?: false
            } else {
                // 대안: AudioManager를 사용하여 이어폰 연결 상태 확인
                activity.isHeadphoneConnectedViaAudioManager()
            }
            Log.d(TAG, "🎧 이어폰 연결 상태 확인: $isConnected")
            result.success(isConnected)
        } catch (e: Exception) {
            Log.e(TAG, "🎧 이어폰 연결 상태 확인 오류: ${e.message}")
            result.success(false)
        }
    }
}
