/// 버스 API 에러 타입 정의
enum BusApiError {
  networkError('네트워크 연결을 확인해주세요'),
  serverError('서버 오류가 발생했습니다'),
  parsingError('데이터 처리 중 오류가 발생했습니다'),
  noData('데이터가 없습니다'),
  timeout('요청 시간이 초과되었습니다'),
  invalidParameter('잘못된 매개변수입니다'),
  unauthorized('인증이 필요합니다'),
  rateLimitExceeded('요청 한도를 초과했습니다');

  const BusApiError(this.message);
  final String message;
}

/// API 호출 결과를 감싸는 클래스
class BusApiResult<T> {
  final T? data;
  final BusApiError? error;
  final String? customMessage;
  final int? statusCode;
  final DateTime timestamp;

  BusApiResult._({
    this.data,
    this.error,
    this.customMessage,
    this.statusCode,
  }) : timestamp = DateTime.now();

  /// 성공 결과 생성
  factory BusApiResult.success(T data) {
    return BusApiResult._(data: data);
  }

  /// 에러 결과 생성
  factory BusApiResult.error(BusApiError error, {String? message, int? statusCode}) {
    return BusApiResult._(
      error: error,
      customMessage: message,
      statusCode: statusCode,
    );
  }

  /// 성공 여부
  bool get isSuccess => data != null && error == null;

  /// 실패 여부
  bool get isFailure => !isSuccess;

  /// 에러 메시지 가져오기
  String get errorMessage {
    if (customMessage != null) return customMessage!;
    if (error != null) return error!.message;
    return '알 수 없는 오류가 발생했습니다';
  }

  /// 데이터 가져오기 (기본값 포함)
  T dataOrDefault(T defaultValue) {
    return data ?? defaultValue;
  }

  /// 성공 시 콜백 실행
  BusApiResult<T> onSuccess(Function(T data) callback) {
    if (isSuccess && data != null) {
      callback(data!);
    }
    return this;
  }

  /// 실패 시 콜백 실행
  BusApiResult<T> onError(Function(BusApiError error, String message) callback) {
    if (isFailure && error != null) {
      callback(error!, errorMessage);
    }
    return this;
  }

  /// 데이터 변환
  BusApiResult<R> map<R>(R Function(T data) transform) {
    if (isSuccess && data != null) {
      try {
        return BusApiResult.success(transform(data!));
      } catch (e) {
        return BusApiResult.error(
          BusApiError.parsingError,
          message: '데이터 변환 중 오류: $e',
        );
      }
    }
    return BusApiResult.error(error!, message: customMessage);
  }

  @override
  String toString() {
    if (isSuccess) {
      return 'BusApiResult.success($data)';
    } else {
      return 'BusApiResult.error($error: $errorMessage)';
    }
  }
}

/// 에러 분석 및 적절한 BusApiError 반환
class ErrorAnalyzer {
  /// Exception을 분석하여 적절한 BusApiError 반환
  static BusApiError analyzeException(dynamic exception) {
    final errorMessage = exception.toString().toLowerCase();

    if (errorMessage.contains('network') ||
        errorMessage.contains('socket') ||
        errorMessage.contains('connection')) {
      return BusApiError.networkError;
    }

    if (errorMessage.contains('timeout')) {
      return BusApiError.timeout;
    }

    if (errorMessage.contains('format') ||
        errorMessage.contains('parse') ||
        errorMessage.contains('json')) {
      return BusApiError.parsingError;
    }

    if (errorMessage.contains('401') ||
        errorMessage.contains('unauthorized')) {
      return BusApiError.unauthorized;
    }

    if (errorMessage.contains('429') ||
        errorMessage.contains('rate limit')) {
      return BusApiError.rateLimitExceeded;
    }

    if (errorMessage.contains('500') ||
        errorMessage.contains('502') ||
        errorMessage.contains('503') ||
        errorMessage.contains('server')) {
      return BusApiError.serverError;
    }

    // 기본적으로 서버 오류로 분류
    return BusApiError.serverError;
  }

  /// HTTP 상태 코드를 기반으로 BusApiError 반환
  static BusApiError analyzeStatusCode(int statusCode) {
    switch (statusCode) {
      case 400:
        return BusApiError.invalidParameter;
      case 401:
        return BusApiError.unauthorized;
      case 408:
        return BusApiError.timeout;
      case 429:
        return BusApiError.rateLimitExceeded;
      case 500:
      case 502:
      case 503:
      case 504:
        return BusApiError.serverError;
      default:
        return BusApiError.serverError;
    }
  }
}