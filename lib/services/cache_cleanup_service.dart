import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/bus_cache_manager.dart';
import '../main.dart' show logMessage, LogLevel;

/// 캐시 정리 및 관리 서비스
class CacheCleanupService {
  static CacheCleanupService? _instance;
  static CacheCleanupService get instance => _instance ??= CacheCleanupService._();
  
  CacheCleanupService._();

  Timer? _cleanupTimer;
  final _cacheManager = BusCacheManager.instance;
  bool _isInitialized = false;

  /// 서비스 초기화 및 자동 정리 시작
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _cacheManager.initialize();
      _startAutoCleanup();
      _isInitialized = true;
      
      logMessage('캐시 정리 서비스 초기화 완료', level: LogLevel.info);
      
      // 초기 캐시 상태 로깅
      final stats = await _cacheManager.getCacheStats();
      logMessage('현재 캐시 상태: $stats', level: LogLevel.debug);
    } catch (e) {
      logMessage('캐시 정리 서비스 초기화 실패: $e', level: LogLevel.error);
    }
  }

  /// 자동 캐시 정리 시작 (30분마다)
  void _startAutoCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      _performScheduledCleanup();
    });
    
    logMessage('자동 캐시 정리 시작 (30분 간격)', level: LogLevel.debug);
  }

  /// 예약된 캐시 정리 수행
  Future<void> _performScheduledCleanup() async {
    try {
      logMessage('자동 캐시 정리 시작', level: LogLevel.debug);
      
      final statsBefore = await _cacheManager.getCacheStats();
      await _cacheManager.cleanExpiredCache();
      final statsAfter = await _cacheManager.getCacheStats();
      
      final removed = statsBefore.expiredEntries;
      if (removed > 0) {
        logMessage('캐시 정리 완료: ${removed}개 항목 제거', level: LogLevel.info);
      }
      
      // 캐시 사용량이 높으면 경고
      if (statsAfter.totalEntries > 40) {
        logMessage('캐시 사용량 높음: ${statsAfter.totalEntries}개 항목', level: LogLevel.warning);
      }
    } catch (e) {
      logMessage('자동 캐시 정리 실패: $e', level: LogLevel.error);
    }
  }

  /// 수동 캐시 정리
  Future<CacheCleanupResult> performManualCleanup() async {
    try {
      logMessage('수동 캐시 정리 시작', level: LogLevel.info);
      
      final statsBefore = await _cacheManager.getCacheStats();
      await _cacheManager.cleanExpiredCache();
      final statsAfter = await _cacheManager.getCacheStats();
      
      final removedCount = statsBefore.expiredEntries;
      final result = CacheCleanupResult(
        removedEntries: removedCount,
        remainingEntries: statsAfter.totalEntries,
        cacheHitRate: statsAfter.hitRate,
        success: true,
      );
      
      logMessage('수동 캐시 정리 완료: $result', level: LogLevel.info);
      return result;
    } catch (e) {
      logMessage('수동 캐시 정리 실패: $e', level: LogLevel.error);
      return CacheCleanupResult(
        removedEntries: 0,
        remainingEntries: 0,
        cacheHitRate: 0.0,
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 전체 캐시 삭제
  Future<bool> clearAllCache() async {
    try {
      logMessage('전체 캐시 삭제 시작', level: LogLevel.warning);
      
      await _cacheManager.clearAllCache();
      
      logMessage('전체 캐시 삭제 완료', level: LogLevel.info);
      return true;
    } catch (e) {
      logMessage('전체 캐시 삭제 실패: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 캐시 통계 조회
  Future<CacheStats> getCacheStats() async {
    try {
      return await _cacheManager.getCacheStats();
    } catch (e) {
      logMessage('캐시 통계 조회 실패: $e', level: LogLevel.error);
      return CacheStats(totalEntries: 0, validEntries: 0, expiredEntries: 0);
    }
  }

  /// 특정 정류장 캐시 삭제
  Future<bool> removeStationCache(String stationId) async {
    try {
      await _cacheManager.removeCachedBusArrivals(stationId);
      logMessage('정류장 캐시 삭제 완료: $stationId', level: LogLevel.debug);
      return true;
    } catch (e) {
      logMessage('정류장 캐시 삭제 실패: $stationId, $e', level: LogLevel.error);
      return false;
    }
  }

  /// 앱 종료 시 정리
  void dispose() {
    _cleanupTimer?.cancel();
    _isInitialized = false;
    logMessage('캐시 정리 서비스 종료', level: LogLevel.debug);
  }

  /// 메모리 압박 상황 처리
  Future<void> handleMemoryPressure() async {
    try {
      logMessage('메모리 압박 상황 - 캐시 정리 수행', level: LogLevel.warning);
      
      // 즉시 만료된 캐시 정리
      await _cacheManager.cleanExpiredCache();
      
      // 캐시가 여전히 많으면 강제로 오래된 항목 제거
      final stats = await _cacheManager.getCacheStats();
      if (stats.totalEntries > 30) {
        // 절반 정도 제거
        await _forceRemoveOldEntries(stats.totalEntries ~/ 2);
      }
      
      logMessage('메모리 압박 상황 처리 완료', level: LogLevel.info);
    } catch (e) {
      logMessage('메모리 압박 상황 처리 실패: $e', level: LogLevel.error);
    }
  }

  /// 강제로 오래된 캐시 항목 제거
  Future<void> _forceRemoveOldEntries(int countToRemove) async {
    // 현재 구현에서는 전체 정리만 지원
    // 향후 개선 시 더 정교한 제거 로직 구현 가능
    await _cacheManager.cleanExpiredCache();
  }
}

/// 캐시 정리 결과
class CacheCleanupResult {
  final int removedEntries;
  final int remainingEntries;
  final double cacheHitRate;
  final bool success;
  final String? errorMessage;

  CacheCleanupResult({
    required this.removedEntries,
    required this.remainingEntries,
    required this.cacheHitRate,
    required this.success,
    this.errorMessage,
  });

  @override
  String toString() {
    if (success) {
      return 'CacheCleanupResult{removed: $removedEntries, remaining: $remainingEntries, hitRate: ${(cacheHitRate * 100).toStringAsFixed(1)}%}';
    } else {
      return 'CacheCleanupResult{failed: $errorMessage}';
    }
  }
}