import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../models/alarm_sound.dart';

// 설정 화면에서 사용할 Enum 정의
enum NotificationDisplayMode {
  alarmedOnly, // 알람 설정된 버스만
  allBuses // 해당 정류장의 모든 버스
}

class SettingsService extends ChangeNotifier {
  static const String _alarmSoundKey = 'alarm_sound';
  static const String _autoAlarmKey = 'use_auto_alarm';
  static const String _autoAlarmVolumeKey = 'auto_alarm_volume';
  static const String _useTtsKey = 'use_tts';
  static const String _kThemeModeKey = 'theme_mode';
  static const String _kVibrateKey = 'vibrate';
  static const String _kSpeakerModeKey = 'speaker_mode';
  static const String _notificationDisplayModeKey = 'notificationDisplayMode';
  static const String _autoAlarmTimeoutMsKey = 'auto_alarm_timeout_ms';
  static const String _fontSizeMultiplierKey = 'font_size_multiplier';
  static const String _earphoneAlarmVibrateKey = 'earphone_alarm_vibrate';
  static const String _customExcludeDatesKey = 'custom_exclude_dates';
  static const String _alertOnArrivalOnlyKey = 'alert_on_arrival_only';
  static const int defaultAutoAlarmTimeoutMinutes = 30; // 기본 30분
  static const int minAutoAlarmTimeoutMinutes = 5; // 최소 5분
  static const int maxAutoAlarmTimeoutMinutes = 120; // 최대 120분

  // 폰트 크기 관련 상수
  static const double defaultFontSizeMultiplier = 1.0; // 기본 크기
  static const double minFontSizeMultiplier = 0.8; // 최소 크기 (80%)
  static const double maxFontSizeMultiplier = 2.0; // 최대 크기 (200%)

  // 스피커 모드 상수
  static const int speakerModeHeadset = 0; // 이어폰 전용
  static const int speakerModeSpeaker = 1; // 스피커 전용
  static const int speakerModeAuto = 2; // 자동 감지 (기본값)

  // 자동 알람 볼륨 관련 상수
  static const double defaultAutoAlarmVolume = 0.7; // 기본 볼륨 (0.0 ~ 1.0)
  static const double minAutoAlarmVolume = 0.0; // 최소 볼륨
  static const double maxAutoAlarmVolume = 1.0; // 최대 볼륨

  late SharedPreferences _prefs;
  String _alarmSound = 'tts';
  bool _useAutoAlarm = true;
  double _autoAlarmVolume = 0.7;
  int _autoAlarmTimeoutMinutes = defaultAutoAlarmTimeoutMinutes;
  bool _useTts = true;
  double _fontSizeMultiplier = defaultFontSizeMultiplier;
  List<DateTime> _customExcludeDates = [];
  bool _alertOnArrivalOnly = false;

  // 싱글톤 패턴
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  ThemeMode _themeMode = ThemeMode.system;
  bool _vibrate = true;
  bool _earphoneAlarmVibrate = true;
  int _speakerMode = speakerModeHeadset; // 스피커 모드 변수 (기본값: 이어폰 전용)

  // MethodChannel 추가
  final MethodChannel _ttsChannel =
      const MethodChannel('com.devground.daegubus/tts');

  // 알림 표시 모드 관련
  NotificationDisplayMode _notificationDisplayMode =
      NotificationDisplayMode.alarmedOnly; // 기본값

  // Getters
  String get alarmSound => _alarmSound;
  String get alarmSoundId => _alarmSound; // 기존 코드 호환성을 위해 추가
  AlarmSound get selectedAlarmSound =>
      AlarmSound.findById(_alarmSound); // 선택된 알람음 객체 반환
  bool get isLoading => false; // 간단한 구현 (필요시 로딩 상태 관리 추가 가능)
  bool get useAutoAlarm => _useAutoAlarm;
  double get autoAlarmVolume => _autoAlarmVolume;
  bool get useTts => _useTts;
  bool get vibrate => _vibrate;
  bool get earphoneAlarmVibrate => _earphoneAlarmVibrate;
  int get speakerMode => _speakerMode;
  ThemeMode get themeMode => _themeMode;
  NotificationDisplayMode get notificationDisplayMode =>
      _notificationDisplayMode;
  int get autoAlarmTimeoutMinutes => _autoAlarmTimeoutMinutes;
  double get fontSizeMultiplier => _fontSizeMultiplier;
  List<DateTime> get customExcludeDates => _customExcludeDates;
  bool get alertOnArrivalOnly => _alertOnArrivalOnly;

  // 설정 초기화
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _alarmSound = _prefs.getString(_alarmSoundKey) ?? 'tts';
    _themeMode = _parseThemeMode(
      _prefs.getString(_kThemeModeKey) ?? 'system',
    );
    _useTts = _prefs.getBool(_useTtsKey) ?? true;
    _vibrate = _prefs.getBool(_kVibrateKey) ?? true;
    _earphoneAlarmVibrate = _prefs.getBool(_earphoneAlarmVibrateKey) ?? true;
    _useAutoAlarm = _prefs.getBool(_autoAlarmKey) ?? true;
    _speakerMode = _prefs.getInt(_kSpeakerModeKey) ?? speakerModeHeadset;
    _autoAlarmVolume =
        _prefs.getDouble(_autoAlarmVolumeKey) ?? defaultAutoAlarmVolume;
    _notificationDisplayMode = NotificationDisplayMode
        .values[_prefs.getInt(_notificationDisplayModeKey) ?? 0];
    _fontSizeMultiplier =
        _prefs.getDouble(_fontSizeMultiplierKey) ?? defaultFontSizeMultiplier;
    // 자동 알람 자동 종료 시간(분) 불러오기 (기본 30분)
    _autoAlarmTimeoutMinutes = ((_prefs.getInt(_autoAlarmTimeoutMsKey) ??
                (defaultAutoAlarmTimeoutMinutes * 60 * 1000)) ~/
            (60 * 1000))
        .clamp(minAutoAlarmTimeoutMinutes, maxAutoAlarmTimeoutMinutes);

    final excludeDatesStrs = _prefs.getStringList(_customExcludeDatesKey) ?? [];
    try {
      _customExcludeDates =
          excludeDatesStrs.map((e) => DateTime.parse(e)).toList();
    } catch (_) {
      _customExcludeDates = [];
    }

    _alertOnArrivalOnly = _prefs.getBool(_alertOnArrivalOnlyKey) ?? false;

    notifyListeners();
  }

  Future<void> updateAlertOnArrivalOnly(bool value) async {
    if (_alertOnArrivalOnly == value) return;
    _alertOnArrivalOnly = value;
    await _prefs.setBool(_alertOnArrivalOnlyKey, value);
    try {
      await _ttsChannel.invokeMethod('setAlertOnArrivalOnly', {'value': value});
    } catch (_) {}
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;
    await _prefs.setString(_kThemeModeKey, _themeModeToString(mode));
    notifyListeners();
  }

  // 알람음 변경
  Future<void> setAlarmSound(String sound) async {
    _alarmSound = sound;
    await _prefs.setString(_alarmSoundKey, sound);

    // 네이티브 코드에 알람 소리 설정 전달
    try {
      await _ttsChannel.invokeMethod('setAlarmSound', {'soundId': sound});
      debugPrint('✅ 네이티브 알람 소리 설정 성공: $sound');
    } catch (e) {
      debugPrint('❌ 네이티브 알람 소리 설정 실패: $e');
    }

    notifyListeners();
  }

  Future<void> updateUseTts(bool value) async {
    if (_useTts == value) return;

    _useTts = value;
    await _prefs.setBool(_useTtsKey, value);

    // 네이티브 코드에 TTS 사용 설정 전달
    try {
      await _ttsChannel.invokeMethod('setUseTts', {'useTts': value});
      debugPrint('✅ 네이티브 TTS 사용 설정 성공: $value');
    } catch (e) {
      debugPrint('❌ 네이티브 TTS 사용 설정 실패: $e');
    }

    notifyListeners();
  }

  Future<void> updateVibrate(bool value) async {
    if (_vibrate == value) return;

    _vibrate = value;
    await _prefs.setBool(_kVibrateKey, value);
    notifyListeners();
  }

  Future<void> updateEarphoneAlarmVibrate(bool value) async {
    if (_earphoneAlarmVibrate == value) return;

    _earphoneAlarmVibrate = value;
    await _prefs.setBool(_earphoneAlarmVibrateKey, value);
    notifyListeners();
  }

  Future<void> updateUseAutoAlarm(bool value) async {
    if (_useAutoAlarm == value) return;

    _useAutoAlarm = value;
    await _prefs.setBool(_autoAlarmKey, value);
    notifyListeners();
  }

  // 스피커 모드 업데이트 함수
  Future<void> updateSpeakerMode(int mode) async {
    if (_speakerMode == mode) return;

    // 변경 전/후 모드 상태 기록
    final oldModeName = getSpeakerModeName(_speakerMode);
    final newModeName = getSpeakerModeName(mode);
    debugPrint(
        '🔊 스피커 모드 변경: $oldModeName -> $newModeName (값: $_speakerMode -> $mode)');

    _speakerMode = mode;
    await _prefs.setInt(_kSpeakerModeKey, mode);

    // 네이티브 코드에 설정 전달
    try {
      await _ttsChannel.invokeMethod('setAudioOutputMode', {'mode': mode});
      debugPrint('✅ 네이티브 TTS 출력 모드 설정 성공: $newModeName');
    } catch (e) {
      debugPrint('❌ 네이티브 TTS 출력 모드 설정 실패: $e');
    }

    notifyListeners();
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  ThemeMode _parseThemeMode(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  // 스피커 모드 이름 반환 함수 추가
  String getSpeakerModeName(int mode) {
    switch (mode) {
      case speakerModeHeadset:
        return '이어폰 전용';
      case speakerModeSpeaker:
        return '스피커 전용';
      case speakerModeAuto:
        return '자동 감지';
      default:
        return '알 수 없음';
    }
  }

  Future<void> addCustomExcludeDate(DateTime date) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    if (!_customExcludeDates.contains(dateOnly)) {
      _customExcludeDates.add(dateOnly);
      await _saveCustomExcludeDates();
      notifyListeners();
    }
  }

  Future<void> removeCustomExcludeDate(DateTime date) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    _customExcludeDates.removeWhere((d) =>
        d.year == dateOnly.year &&
        d.month == dateOnly.month &&
        d.day == dateOnly.day);
    await _saveCustomExcludeDates();
    notifyListeners();
  }

  Future<void> _saveCustomExcludeDates() async {
    final list = _customExcludeDates.map((e) => e.toIso8601String()).toList();
    await _prefs.setStringList(_customExcludeDatesKey, list);
  }

  // Method to update Notification Display Mode
  Future<void> updateNotificationDisplayMode(
      NotificationDisplayMode mode) async {
    if (_notificationDisplayMode != mode) {
      _notificationDisplayMode = mode;
      await _prefs.setInt(_notificationDisplayModeKey, mode.index);
      notifyListeners();
      // Optionally notify native side if needed immediately
      // await _notifyNativeSettingsChanged();
    }
  }

  // 자동 알람 볼륨 업데이트 메서드 추가
  Future<void> updateAutoAlarmVolume(double volume) async {
    if (_autoAlarmVolume == volume) return;

    _autoAlarmVolume = volume.clamp(minAutoAlarmVolume, maxAutoAlarmVolume);
    await _prefs.setDouble(_autoAlarmVolumeKey, _autoAlarmVolume);

    // 네이티브 코드에 볼륨 설정 전달
    try {
      await _ttsChannel
          .invokeMethod('setAutoAlarmVolume', {'volume': _autoAlarmVolume});
      debugPrint('✅ 자동 알람 볼륨 설정 성공: $_autoAlarmVolume');
    } catch (e) {
      debugPrint('❌ 자동 알람 볼륨 설정 오류: $e');
    }

    notifyListeners();
  }

  // Optional: Method to notify native side about setting changes
  // Future<void> _notifyNativeSettingsChanged() async {
  //   // Use MethodChannel to send updated settings to BusAlertService if necessary
  // }

  // 자동 알람 자동 종료 시간(분) 업데이트
  Future<void> updateAutoAlarmTimeoutMinutes(int minutes) async {
    final clamped =
        minutes.clamp(minAutoAlarmTimeoutMinutes, maxAutoAlarmTimeoutMinutes);
    if (_autoAlarmTimeoutMinutes == clamped) return;
    _autoAlarmTimeoutMinutes = clamped;
    await _prefs.setInt(_autoAlarmTimeoutMsKey, clamped * 60 * 1000);
    notifyListeners();
  }

  // 현재 스피커 모드가 이어폰 전용인지 확인
  bool get isHeadsetMode => _speakerMode == speakerModeHeadset;

  // 현재 스피커 모드가 스피커 전용인지 확인
  bool get isSpeakerMode => _speakerMode == speakerModeSpeaker;

  // 현재 스피커 모드가 자동 감지인지 확인
  bool get isAutoMode => _speakerMode == speakerModeAuto;

  // 폰트 크기 업데이트 메서드
  Future<void> updateFontSizeMultiplier(double multiplier) async {
    final clamped =
        multiplier.clamp(minFontSizeMultiplier, maxFontSizeMultiplier);
    if (_fontSizeMultiplier == clamped) return;

    _fontSizeMultiplier = clamped;
    await _prefs.setDouble(_fontSizeMultiplierKey, clamped);
    notifyListeners();
  }
}
