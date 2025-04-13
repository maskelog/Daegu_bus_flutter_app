import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:flutter/foundation.dart';

class DioClient {
  static final DioClient _instance = DioClient._internal();
  late final Dio dio;

  factory DioClient() => _instance;

  DioClient._internal() {
    dio = Dio();
    
    // 기본 설정
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 10);
    dio.options.sendTimeout = const Duration(seconds: 10);
    
    // 로거 추가 (디버그 모드에서만 활성화)
    if (kDebugMode) {
      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
          error: true,
          compact: true,
          maxWidth: 90,
        ),
      );
    }
  }
  
  // 로그 레벨 설정 메서드
  void setLogLevel(LogLevel level) {
    if (kDebugMode) {
      // 기존 로거 제거
      dio.interceptors.removeWhere((interceptor) => interceptor is PrettyDioLogger);
      
      // 새 로거 추가
      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: level.index >= LogLevel.verbose.index,
          requestBody: level.index >= LogLevel.debug.index,
          responseBody: level.index >= LogLevel.debug.index,
          responseHeader: level.index >= LogLevel.verbose.index,
          error: level.index >= LogLevel.error.index,
          compact: level != LogLevel.verbose,
          maxWidth: 90,
        ),
      );
    }
  }
}

// 로그 레벨 정의
enum LogLevel {
  none,    // 로깅 없음
  error,   // 오류만 로깅
  warning, // 경고 이상 로깅
  info,    // 정보 이상 로깅
  debug,   // 디버그 이상 로깅
  verbose, // 모든 것 로깅
}
