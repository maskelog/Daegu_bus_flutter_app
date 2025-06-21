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
  static const String _alarmSoundKey = 'alarm_sound_id';
  static const String _kThemeModeKey = 'theme_mode';
  static const String _kUseTtsKey = 'use_tts';
  static const String _kVibrateKey = 'vibrate';
  static const String _kSpeakerModeKey = 'speaker_mode';
  static const String _notificationDisplayModeKey = 'notificationDisplayMode';
  static const String _kAutoAlarmVolumeKey = 'auto_alarm_volume';
  static const String _kUseAutoAlarmKey = 'use_auto_alarm';

  // 스피커 모드 상수
  static const int speakerModeHeadset = 0; // 이어폰 전용
  static const int speakerModeSpeaker = 1; // 스피커 전용
  static const int speakerModeAuto = 2; // 자동 감지 (기본값)

  // 자동 알람 볼륨 관련 상수
  static const double defaultAutoAlarmVolume = 0.7; // 기본 볼륨 (0.0 ~ 1.0)
  static const double minAutoAlarmVolume = 0.0; // 최소 볼륨
  static const double maxAutoAlarmVolume = 1.0; // 최대 볼륨

  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/notification');

  // 싱글톤 패턴
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  String _alarmSoundId = AlarmSound.ttsAlarm.id;
  bool _isLoading = true;
  double _autoAlarmVolume = defaultAutoAlarmVolume;

  ThemeMode _themeMode = ThemeMode.system;
  bool _useTts = true;
  bool _vibrate = true;
  bool _useAutoAlarm = true; // 자동 알람 사용 여부 (기본값: 사용)
  int _speakerMode = speakerModeHeadset; // 스피커 모드 변수 (기본값: 이어폰 전용)

  // MethodChannel 추가
  final MethodChannel _ttsChannel =
      const MethodChannel('com.example.daegu_bus_app/tts');

  // 알림 표시 모드 관련
  NotificationDisplayMode _notificationDisplayMode =
      NotificationDisplayMode.alarmedOnly; // 기본값

  late SharedPreferences _prefs;

  // Getters
  String get alarmSoundId => _alarmSoundId;
  AlarmSound get selectedAlarmSound => AlarmSound.findById(_alarmSoundId);
  bool get isLoading => _isLoading;
  ThemeMode get themeMode => _themeMode;
  bool get useTts => _useTts;
  bool get vibrate => _vibrate;
  bool get useAutoAlarm => _useAutoAlarm;
  int get speakerMode => _speakerMode;
  double get autoAlarmVolume => _autoAlarmVolume;
  NotificationDisplayMode get notificationDisplayMode =>
      _notificationDisplayMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  // 설정 초기화
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _isLoading = true;
    notifyListeners();

    try {
      _alarmSoundId =
          _prefs.getString(_alarmSoundKey) ?? AlarmSound.ttsAlarm.id;
      await _updateNativeAlarmSound();
      await _loadSettings();

      // Load Notification Display Mode
      final modeIndex = _prefs.getInt(_notificationDisplayModeKey) ??
          NotificationDisplayMode.alarmedOnly.index;
      _notificationDisplayMode = NotificationDisplayMode.values[modeIndex];

      // 자동 알람 볼륨 로드
      _autoAlarmVolume =
          _prefs.getDouble(_kAutoAlarmVolumeKey) ?? defaultAutoAlarmVolume;
    } catch (e) {
      debugPrint('설정 초기화 오류: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 알람음 변경
  Future<void> setAlarmSound(String soundId) async {
    try {
      await _prefs.setString(_alarmSoundKey, soundId);
      _alarmSoundId = soundId;

      await _updateNativeAlarmSound();
      notifyListeners();
    } catch (e) {
      debugPrint('알람음 설정 오류: $e');
    }
  }

  // 네이티브 코드에 알람음 설정 전달
  Future<void> _updateNativeAlarmSound() async {
    try {
      final sound = selectedAlarmSound;
      await _channel.invokeMethod('setAlarmSound', {
        'filename': sound.filename,
        'soundId': sound.id,
        'useTts': sound.useTts,
      });
      debugPrint('네이티브 알람음 설정 성공: ${sound.name}, TTS 사용: ${sound.useTts}');
    } catch (e) {
      debugPrint('네이티브 알람음 설정 오류: $e');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final themeModeString = _prefs.getString(_kThemeModeKey) ?? 'system';
      _themeMode = _parseThemeMode(themeModeString);

      _useTts = _prefs.getBool(_kUseTtsKey) ?? true;
      _vibrate = _prefs.getBool(_kVibrateKey) ?? true;
      _useAutoAlarm = _prefs.getBool(_kUseAutoAlarmKey) ?? true;
      _speakerMode = _prefs.getInt(_kSpeakerModeKey) ??
          speakerModeHeadset; // 스피커 모드 로드 (기본 이어폰 전용)

      notifyListeners();
    } catch (e) {
      debugPrint('설정 로드 오류: $e');
    }
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;

    try {
      await _prefs.setString(_kThemeModeKey, _themeModeToString(mode));
      notifyListeners();
    } catch (e) {
      debugPrint('테마 모드 저장 오류: $e');
    }
  }

  Future<void> updateUseTts(bool value) async {
    if (_useTts == value) return;

    _useTts = value;

    try {
      await _prefs.setBool(_kUseTtsKey, value);
      notifyListeners();
    } catch (e) {
      debugPrint('TTS 설정 저장 오류: $e');
    }
  }

  Future<void> updateVibrate(bool value) async {
    if (_vibrate == value) return;

    _vibrate = value;

    try {
      await _prefs.setBool(_kVibrateKey, value);
      notifyListeners();
    } catch (e) {
      debugPrint('진동 설정 저장 오류: $e');
    }
  }

  Future<void> updateUseAutoAlarm(bool value) async {
    if (_useAutoAlarm == value) return;

    _useAutoAlarm = value;

    try {
      await _prefs.setBool(_kUseAutoAlarmKey, value);
      notifyListeners();
    } catch (e) {
      debugPrint('자동 알람 설정 저장 오류: $e');
    }
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

    try {
      await _prefs.setInt(_kSpeakerModeKey, mode);

      // 네이티브 코드에 설정 전달
      try {
        await _ttsChannel.invokeMethod('setAudioOutputMode', {'mode': mode});
        debugPrint('✅ 네이티브 TTS 출력 모드 설정 성공: $newModeName');
      } catch (e) {
        debugPrint('❌ 네이티브 TTS 출력 모드 설정 실패: $e');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ 스피커 모드 설정 저장 오류: $e');
    }
  }

  // 테마 모드 문자열 변환 헬퍼 함수
  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      default:
        return 'system';
    }
  }

  // 테마 모드 파싱 헬퍼 함수
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

    try {
      await _prefs.setDouble(_kAutoAlarmVolumeKey, _autoAlarmVolume);

      // 네이티브 코드에 볼륨 설정 전달
      try {
        await _ttsChannel
            .invokeMethod('setAutoAlarmVolume', {'volume': _autoAlarmVolume});
        debugPrint('🔊 자동 알람 볼륨 설정 성공: $_autoAlarmVolume');
      } catch (e) {
        debugPrint('❌ 자동 알람 볼륨 설정 오류: $e');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('자동 알람 볼륨 설정 저장 오류: $e');
    }
  }

  // Optional: Method to notify native side about setting changes
  // Future<void> _notifyNativeSettingsChanged() async {
  //   // Use MethodChannel to send updated settings to BusAlertService if necessary
  // }

  // 현재 스피커 모드가 이어폰 전용인지 확인
  bool get isHeadsetMode => _speakerMode == speakerModeHeadset;

  // 현재 스피커 모드가 스피커 전용인지 확인
  bool get isSpeakerMode => _speakerMode == speakerModeSpeaker;

  // 현재 스피커 모드가 자동 감지인지 확인
  bool get isAutoMode => _speakerMode == speakerModeAuto;
}
