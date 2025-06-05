package com.example.daegu_bus_app.core

import android.util.Log
import android.util.LruCache
import com.example.daegu_bus_app.models.BusInfo
import java.util.concurrent.ConcurrentHashMap

/**
 * 메모리 효율적인 캐시 관리자
 * LRU 캐시를 사용하여 메모리 사용량 제한
 */
class CacheManager private constructor() {
    companion object {
        private const val TAG = "CacheManager"
        private const val MAX_CACHE_SIZE = 50 // 최대 50개 버스 정보만 캐시
        private const val CACHE_EXPIRE_MS = 60_000L // 1분 후 만료
        
        @Volatile
        private var INSTANCE: CacheManager? = null
        
        fun getInstance(): CacheManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: CacheManager().also { INSTANCE = it }
            }
        }
    }
    
    // LRU 캐시로 메모리 사용량 제한
    private val busInfoCache = LruCache<String, CachedBusInfo>(MAX_CACHE_SIZE)
    private val cacheTimestamps = ConcurrentHashMap<String, Long>()
    
    data class CachedBusInfo(
        val busInfo: BusInfo,
        val timestamp: Long = System.currentTimeMillis()
    )
    
    /**
     * 버스 정보 캐시 저장 (메모리 효율적)
     */
    fun putBusInfo(key: String, busInfo: BusInfo) {
        try {
            val cachedInfo = CachedBusInfo(busInfo)
            busInfoCache.put(key, cachedInfo)
            cacheTimestamps[key] = System.currentTimeMillis()
            
            // 주기적으로 만료된 캐시 정리
            cleanExpiredCache()
        } catch (e: Exception) {
            Log.e(TAG, "캐시 저장 오류: ${e.message}")
        }
    }
    
    /**
     * 버스 정보 캐시 조회
     */
    fun getBusInfo(key: String): BusInfo? {
        return try {
            val cached = busInfoCache.get(key)
            val timestamp = cacheTimestamps[key]
            
            if (cached != null && timestamp != null) {
                if (System.currentTimeMillis() - timestamp < CACHE_EXPIRE_MS) {
                    cached.busInfo
                } else {
                    // 만료된 캐시 제거
                    removeBusInfo(key)
                    null
                }
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "캐시 조회 오류: ${e.message}")
            null
        }
    }
    
    /**
     * 특정 캐시 제거
     */
    fun removeBusInfo(key: String) {
        try {
            busInfoCache.remove(key)
            cacheTimestamps.remove(key)
        } catch (e: Exception) {
            Log.e(TAG, "캐시 제거 오류: ${e.message}")
        }
    }
    
    /**
     * 만료된 캐시 정리 (메모리 절약)
     */
    private fun cleanExpiredCache() {
        try {
            val currentTime = System.currentTimeMillis()
            val expiredKeys = mutableListOf<String>()
            
            cacheTimestamps.entries.forEach { (key, timestamp) ->
                if (currentTime - timestamp > CACHE_EXPIRE_MS) {
                    expiredKeys.add(key)
                }
            }
            
            expiredKeys.forEach { key ->
                removeBusInfo(key)
            }
            
            if (expiredKeys.isNotEmpty()) {
                Log.d(TAG, "만료된 캐시 ${expiredKeys.size}개 정리 완료")
            }
        } catch (e: Exception) {
            Log.e(TAG, "캐시 정리 오류: ${e.message}")
        }
    }
    
    /**
     * 모든 캐시 정리
     */
    fun clearAll() {
        try {
            busInfoCache.evictAll()
            cacheTimestamps.clear()
            Log.d(TAG, "모든 캐시 정리 완료")
        } catch (e: Exception) {
            Log.e(TAG, "캐시 전체 정리 오류: ${e.message}")
        }
    }
    
    /**
     * 캐시 상태 정보
     */
    fun getCacheStats(): String {
        return try {
            "캐시 크기: ${busInfoCache.size()}/$MAX_CACHE_SIZE, " +
            "타임스탬프: ${cacheTimestamps.size}"
        } catch (e: Exception) {
            "캐시 상태 조회 오류: ${e.message}"
        }
    }
} 