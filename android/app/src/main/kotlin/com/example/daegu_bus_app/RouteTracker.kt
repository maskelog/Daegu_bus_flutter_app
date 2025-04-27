package com.example.daegu_bus_app

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import kotlinx.coroutines.*
import com.example.daegu_bus_app.BusInfo

class RouteTracker(
    private val context: Context,
    private val busApiService: BusApiService,
    private val trackingInfo: BusAlertService.TrackingInfo,
    private val coroutineScope: CoroutineScope, // Use the service's scope
    private val ttsSettingsProvider: () -> Boolean, // Lambda to get current TTS setting
    private val onUpdate: suspend (BusAlertService.TrackingInfo) -> Unit, // Callback for updates
    private val onError: suspend (String, String, String, String) -> Unit, // Callback for errors
    private val onStop: suspend (String) -> Unit, // Callback when stopping this tracker
    private val calculateDelay: (Int?) -> Long // Pass the delay calculation logic
) {
    companion object {
        private const val TAG = "RouteTracker"
        private const val MAX_CONSECUTIVE_ERRORS = 3
    }

    private var isActive = true // Internal flag to control the loop

    fun startMonitoring() {
        Log.i(TAG, "[${trackingInfo.routeId}] Monitoring started.")
        coroutineScope.launch { // Launch within the provided scope
            while (isActive && coroutineContext.isActive) { // Check both flags
                try {
                    // 1. Fetch bus arrivals
                    val arrivals = busApiService.getBusArrivals(trackingInfo.stationId, trackingInfo.routeId)
                    Log.d(TAG, "[${trackingInfo.routeId}] Fetched arrivals: Count=${arrivals.size}")

                    // Reset error count on successful fetch
                    trackingInfo.consecutiveErrors = 0

                    // 2. Find the next relevant bus
                    val firstBus = arrivals.firstOrNull { !it.isOutOfService }

                    // 3. Update TrackingInfo state
                    if (firstBus != null) {
                        trackingInfo.lastBusInfo = firstBus
                        val remainingMinutes = firstBus.getRemainingMinutes()
                        Log.d(TAG, "[${trackingInfo.routeId}] Updated bus info - Remaining time: $remainingMinutes min, Current station: ${firstBus.currentStation}")

                        // 4. Trigger updates/notifications via callback
                        onUpdate(trackingInfo) // Notify BusAlertService of the update

                        // 5. Trigger TTS if needed
                        triggerTTSIfNeeded(firstBus, remainingMinutes)

                        // 6. Calculate delay and wait
                        val delayTime = calculateDelay(remainingMinutes)
                        Log.d(TAG, "[${trackingInfo.routeId}] Delaying for ${delayTime}ms")
                        delay(delayTime)
                    } else {
                        Log.w(TAG, "[${trackingInfo.routeId}] No available buses found. Continuing monitoring for now.")
                        trackingInfo.lastBusInfo = null
                        onUpdate(trackingInfo) // Update to show no available buses
                        delay(30000L) // Wait 30 seconds before next check
                    }

                } catch (e: CancellationException) {
                    Log.i(TAG, "[${trackingInfo.routeId}] Monitoring job cancelled.")
                    stopMonitoring()
                    break
                } catch (e: Exception) {
                    Log.e(TAG, "[${trackingInfo.routeId}] Error during tracking loop: ${e.message}", e)
                    trackingInfo.consecutiveErrors++
                    Log.w(TAG, "[${trackingInfo.routeId}] Consecutive errors: ${trackingInfo.consecutiveErrors}")

                    // Notify error state via callback (for immediate UI/notification update)
                    onUpdate(trackingInfo) // Send update to reflect error state

                    if (trackingInfo.consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
                        Log.e(TAG, "[${trackingInfo.routeId}] Max consecutive errors reached. Stopping monitoring.")
                        stopMonitoring()
                        // Notify about the final error and trigger stop via callbacks
                        onError(trackingInfo.routeId, trackingInfo.busNo, trackingInfo.stationName, "정보 조회 연속 실패")
                        onStop(trackingInfo.routeId) // Tell the service to stop this route formally
                        break
                    }
                    // Wait longer after an error before retrying
                    delay(30000L)
                }
            }
            Log.i(TAG, "[${trackingInfo.routeId}] Monitoring loop finished (isActive=$isActive, coroutineContext.isActive=${coroutineContext.isActive})")
            // If the loop finishes naturally and wasn't stopped externally, call onStop
            if (isActive) { // Loop finished without external cancellation or max errors
                onStop(trackingInfo.routeId)
            }
        }
    }

    private fun triggerTTSIfNeeded(busInfo: BusInfo?, currentRemainingMinutes: Int?) {
        if (busInfo != null && currentRemainingMinutes != null) {
             if (ttsSettingsProvider() && currentRemainingMinutes <= 1 && trackingInfo.lastNotifiedMinutes > 1) {
                 Log.d(TAG, "[${trackingInfo.routeId}] Bus approaching. Requesting TTS.")
                 startTTSServiceSpeak(trackingInfo.busNo, trackingInfo.stationName, trackingInfo.routeId, trackingInfo.stationId)
                 trackingInfo.lastNotifiedMinutes = currentRemainingMinutes
             } else if (currentRemainingMinutes > 1) {
                 trackingInfo.lastNotifiedMinutes = Int.MAX_VALUE // Reset notification trigger
             }
        }
    }

    // Helper to start TTSService (Copied from BusAlertService, uses context)
    private fun startTTSServiceSpeak(busNo: String, stationName: String, routeId: String, stationId: String) {
        if (!ttsSettingsProvider()) return
        Log.d(TAG, "Sending Intent to TTSService to speak for $busNo at $stationName")
        val ttsIntent = Intent(context, TTSService::class.java).apply {
            action = "REPEAT_TTS_ALERT"
            putExtra("busNo", busNo)
            putExtra("stationName", stationName)
            putExtra("routeId", routeId)
            putExtra("stationId", stationId)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(ttsIntent)
            } else {
                context.startService(ttsIntent)
            }
        } catch (e: Exception) {
             Log.e(TAG, "Error starting TTSService: ${e.message}", e)
        }
    }

    // Public method to stop this specific tracker's loop
    @Synchronized
    fun stopMonitoring() {
        Log.i(TAG, "[${trackingInfo.routeId}] External stop request received.")
        synchronized(this) {
            isActive = false
        }
        // Cancellation of the coroutine job itself should be handled by BusAlertService
    }
}