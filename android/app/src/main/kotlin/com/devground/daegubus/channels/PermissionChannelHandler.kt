package com.devground.daegubus.channels

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * com.devground.daegubus/permission 채널 핸들러.
 * 정확한 알람·배터리 최적화 예외·실시간(promoted) 알림 권한 조회 및 설정 화면 이동을 담당한다.
 */
class PermissionChannelHandler(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "PermissionChannel"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canScheduleExactAlarms" -> {
                // Android 12(API 31~32)에서만 회수 가능. 13+는 USE_EXACT_ALARM으로 항상 true.
                val alarmManager = activity.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
                val canExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                    alarmManager.canScheduleExactAlarms()
                result.success(canExact)
            }
            "isIgnoringBatteryOptimizations" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
                    val isIgnored = pm.isIgnoringBatteryOptimizations(activity.packageName)
                    result.success(isIgnored)
                } else {
                    result.success(true)
                }
            }
            "requestIgnoreBatteryOptimizations" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        val pm = activity.getSystemService(Context.POWER_SERVICE) as PowerManager
                        val packageName = activity.packageName
                        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            val resolveInfo = intent.resolveActivity(activity.packageManager)
                            if (resolveInfo == null) {
                                result.error("BATTERY_OPTIMIZATION_INTENT_NOT_FOUND", "요청 화면을 열 수 없습니다.", null)
                                return
                            }
                            activity.startActivity(intent)
                            result.success(true)
                        } else {
                            result.success(true)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "requestIgnoreBatteryOptimizations 실패: ${e.message}", e)
                        result.error("REQUEST_BATTERY_OPTIMIZATION_ERROR", e.message, null)
                    }
                } else {
                    result.success(false)
                }
            }
            "canPostPromotedNotifications" -> {
                if (Build.VERSION.SDK_INT >= 36) {
                    try {
                        val notificationManager =
                            activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        result.success(notificationManager.canPostPromotedNotifications())
                    } catch (e: Exception) {
                        Log.e(TAG, "canPostPromotedNotifications 실패: ${e.message}", e)
                        result.error("PROMOTED_NOTIFICATION_CHECK_ERROR", e.message, null)
                    }
                } else {
                    result.success(true)
                }
            }
            "openPromotedNotificationSettings" -> {
                if (Build.VERSION.SDK_INT >= 36) {
                    try {
                        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val resolveInfo = intent.resolveActivity(activity.packageManager)
                        if (resolveInfo == null) {
                            result.error(
                                "PROMOTED_NOTIFICATION_INTENT_NOT_FOUND",
                                "실시간 정보 설정 화면을 열 수 없습니다.",
                                null
                            )
                            return
                        }
                        activity.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "openPromotedNotificationSettings 실패: ${e.message}", e)
                        result.error("PROMOTED_NOTIFICATION_SETTINGS_ERROR", e.message, null)
                    }
                } else {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }
}
