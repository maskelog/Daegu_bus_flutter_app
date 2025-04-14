import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../main.dart' show logMessage, LogLevel;

/// 네트워크 요청 및 응답을 처리하는 Dio 클라이언트 유틸리티 클래스
class DioClient {
  static final DioClient _instance = DioClient._internal();
  factory DioClient() => _instance;

  Dio? _dio;
  final Map<String, CancelToken> _cancelTokens = {};
  static const Duration defaultTimeout = Duration(seconds: 15);

  DioClient._internal() {
    _initDio();
  }

  /// Dio 인스턴스 초기화
  void _initDio() {
    _dio = Dio(BaseOptions(
        connectTimeout: defaultTimeout,
        receiveTimeout: defaultTimeout,
        sendTimeout: defaultTimeout,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'DaeguBusApp/1.0'
        }));

    // 인터셉터 추가
    _dio!.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (object) =>
            logMessage(object.toString(), level: LogLevel.debug)));

    // 에러 핸들링 인터셉터
    _dio!.interceptors.add(InterceptorsWrapper(
        onError: (DioException error, ErrorInterceptorHandler handler) {
      _handleDioError(error);
      handler.next(error);
    }));

    logMessage('✅ Dio 클라이언트 초기화 완료', level: LogLevel.info);
  }

  /// 에러 처리 메서드
  void _handleDioError(DioException error) {
    String errorMessage;

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        errorMessage =
            '연결 시간 초과 (${error.requestOptions.connectTimeout?.inSeconds}초)';
        break;
      case DioExceptionType.sendTimeout:
        errorMessage =
            '요청 전송 시간 초과 (${error.requestOptions.sendTimeout?.inSeconds}초)';
        break;
      case DioExceptionType.receiveTimeout:
        errorMessage =
            '응답 수신 시간 초과 (${error.requestOptions.receiveTimeout?.inSeconds}초)';
        break;
      case DioExceptionType.badResponse:
        errorMessage =
            '서버 오류 응답: ${error.response?.statusCode} ${error.response?.statusMessage}';
        break;
      case DioExceptionType.cancel:
        errorMessage = '요청 취소됨';
        break;
      case DioExceptionType.connectionError:
        errorMessage = '네트워크 연결 오류: ${error.message}';
        break;
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          errorMessage = '인터넷 연결을 확인해주세요: ${error.message}';
        } else {
          errorMessage = '알 수 없는 오류: ${error.message}';
        }
        break;
      default:
        errorMessage = '네트워크 오류: ${error.message}';
    }

    logMessage('❌ Dio 오류: $errorMessage', level: LogLevel.error);
  }

  /// GET 요청 수행
  Future<Response?> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    String? cancelTag,
    Duration? timeout,
  }) async {
    try {
      final CancelToken cancelToken = _getCancelToken(cancelTag);
      final Options requestOptions = _createOptions(options, timeout);

      final response = await _dio!.get(url,
          queryParameters: queryParameters,
          options: requestOptions,
          cancelToken: cancelToken);

      return response;
    } on DioException catch (e) {
      _handleDioError(e);
      return null;
    } catch (e) {
      logMessage('❌ GET 요청 오류: $e', level: LogLevel.error);
      return null;
    }
  }

  /// POST 요청 수행
  Future<Response?> post(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    String? cancelTag,
    Duration? timeout,
  }) async {
    try {
      final CancelToken cancelToken = _getCancelToken(cancelTag);
      final Options requestOptions = _createOptions(options, timeout);

      final response = await _dio!.post(url,
          data: data,
          queryParameters: queryParameters,
          options: requestOptions,
          cancelToken: cancelToken);

      return response;
    } on DioException catch (e) {
      _handleDioError(e);
      return null;
    } catch (e) {
      logMessage('❌ POST 요청 오류: $e', level: LogLevel.error);
      return null;
    }
  }

  /// 네이티브 메서드 호출
  Future<dynamic> callNativeMethod(
    String channel,
    String method,
    Map<String, dynamic> arguments, {
    Duration? timeout,
  }) async {
    try {
      final methodChannel = MethodChannel(channel);
      final completer = Completer<dynamic>();

      // 타임아웃 처리
      Timer? timeoutTimer;
      if (timeout != null) {
        timeoutTimer = Timer(timeout, () {
          if (!completer.isCompleted) {
            completer.completeError(
                TimeoutException('네이티브 메서드 호출 시간 초과: $method', timeout));
          }
        });
      }

      try {
        final result = await methodChannel.invokeMethod(method, arguments);
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } on PlatformException catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      } finally {
        timeoutTimer?.cancel();
      }

      return completer.future;
    } catch (e) {
      logMessage('❌ 네이티브 메서드 호출 오류: $method - $e', level: LogLevel.error);
      rethrow;
    }
  }

  /// 진행 중인 요청 취소
  void cancelRequest(String? tag) {
    if (tag != null && _cancelTokens.containsKey(tag)) {
      _cancelTokens[tag]!.cancel('사용자 요청으로 취소됨');
      _cancelTokens.remove(tag);
      logMessage('🔄 요청 취소됨: $tag', level: LogLevel.info);
    }
  }

  /// 모든 진행 중인 요청 취소
  void cancelAllRequests() {
    _cancelTokens.forEach((tag, token) {
      token.cancel('모든 요청 취소됨');
    });
    _cancelTokens.clear();
    logMessage('🔄 모든 요청 취소됨', level: LogLevel.info);
  }

  /// CancelToken 생성 또는 가져오기
  CancelToken _getCancelToken(String? tag) {
    if (tag == null) {
      return CancelToken();
    }

    if (_cancelTokens.containsKey(tag)) {
      // 기존 토큰이 이미 취소되었으면 새로 생성
      if (_cancelTokens[tag]!.isCancelled) {
        _cancelTokens[tag] = CancelToken();
      }
    } else {
      _cancelTokens[tag] = CancelToken();
    }

    return _cancelTokens[tag]!;
  }

  /// 요청 옵션 생성
  Options _createOptions(Options? baseOptions, Duration? timeout) {
    final options = baseOptions?.copyWith() ?? Options();

    if (timeout != null) {
      options.sendTimeout = timeout;
      options.receiveTimeout = timeout;
    }

    return options;
  }
}

/// Completer 확장 - isCompleted 체크 추가
extension CompleterExtension<T> on Completer<T> {
  // isCompleted 속성을 직접 사용할 수 없기 때문에 다른 방법으로 구현
  bool get isCompleted {
    try {
      // 이미 완료된 Completer에 값을 완료하면 예외 발생
      complete(null);
      return false; // 예외가 발생하지 않으면 아직 완료되지 않음
    } catch (e) {
      return true; // 예외가 발생하면 이미 완료됨
    }
  }
}
