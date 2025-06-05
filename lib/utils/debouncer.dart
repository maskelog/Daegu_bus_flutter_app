import 'dart:async';

/// API 호출 중복 방지를 위한 디바운서
class Debouncer {
  final Duration delay;
  Timer? _timer;

  Debouncer({required this.delay});

  /// 디바운싱된 실행
  void call(Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// 즉시 실행 (디바운싱 취소)
  void callNow(Function() action) {
    _timer?.cancel();
    action();
  }

  /// 디바운서 정리
  void dispose() {
    _timer?.cancel();
  }
}

/// 전역 디바운서 인스턴스들
class DebounceManager {
  static final Map<String, Debouncer> _debouncers = {};

  /// 키별 디바운서 가져오기/생성
  static Debouncer getDebouncer(String key,
      {Duration delay = const Duration(milliseconds: 500)}) {
    if (!_debouncers.containsKey(key)) {
      _debouncers[key] = Debouncer(delay: delay);
    }
    return _debouncers[key]!;
  }

  /// 특정 디바운서 제거
  static void removeDebouncer(String key) {
    _debouncers[key]?.dispose();
    _debouncers.remove(key);
  }

  /// 모든 디바운서 정리
  static void dispose() {
    for (var debouncer in _debouncers.values) {
      debouncer.dispose();
    }
    _debouncers.clear();
  }
}
