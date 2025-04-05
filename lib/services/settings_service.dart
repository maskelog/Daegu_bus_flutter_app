import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../models/alarm_sound.dart';

class SettingsService extends ChangeNotifier {
  static const String _alarmSoundKey = 'alarm_sound_id';
  static const String _kThemeModeKey = 'theme_mode';
  static const String _kUseTtsKey = 'use_tts';
  static const String _kVibrateKey = 'vibrate';
  static const String _kSpeakerModeKey = 'speaker_mode';

  // 스피커 모드 상수
  static const int speakerModeHeadset = 0; // 이어폰 전용
  static const int speakerModeSpeaker = 1; // 스피커 전용
  static const int speakerModeAuto = 2; // 자동 감지 (기본값)

  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/notification');

  // 싱글톤 패턴
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  String _alarmSoundId = AlarmSound.ttsAlarm.id;
  bool _isLoading = true;

  ThemeMode _themeMode = ThemeMode.system;
  bool _useTts = false;
  bool _vibrate = true;
  int _speakerMode = speakerModeAuto; // 스피커 모드 변수 (기본값: 자동)

  // MethodChannel 추가
  final MethodChannel _ttsChannel =
      const MethodChannel('com.example.daegu_bus_app/tts');

  // Getters
  String get alarmSoundId => _alarmSoundId;
  AlarmSound get selectedAlarmSound => AlarmSound.findById(_alarmSoundId);
  bool get isLoading => _isLoading;
  ThemeMode get themeMode => _themeMode;
  bool get useTts => _useTts;
  bool get vibrate => _vibrate;
  int get speakerMode => _speakerMode; // 스피커 모드 getter

  // 설정 초기화
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _alarmSoundId = prefs.getString(_alarmSoundKey) ?? AlarmSound.ttsAlarm.id;
      await _updateNativeAlarmSound();
      await _loadSettings();
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_alarmSoundKey, soundId);
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
      final prefs = await SharedPreferences.getInstance();
      final themeModeString = prefs.getString(_kThemeModeKey) ?? 'system';
      _themeMode = _parseThemeMode(themeModeString);

      _useTts = prefs.getBool(_kUseTtsKey) ?? false;
      _vibrate = prefs.getBool(_kVibrateKey) ?? true;
      _speakerMode =
          prefs.getInt(_kSpeakerModeKey) ?? speakerModeAuto; // 스피커 모드 로드

      notifyListeners();
    } catch (e) {
      debugPrint('설정 로드 오류: $e');
    }
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;

    _themeMode = mode;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeModeKey, _themeModeToString(mode));
      notifyListeners();
    } catch (e) {
      debugPrint('테마 모드 저장 오류: $e');
    }
  }

  Future<void> updateUseTts(bool value) async {
    if (_useTts == value) return;

    _useTts = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kUseTtsKey, value);
      notifyListeners();
    } catch (e) {
      debugPrint('TTS 설정 저장 오류: $e');
    }
  }

  Future<void> updateVibrate(bool value) async {
    if (_vibrate == value) return;

    _vibrate = value;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kVibrateKey, value);
      notifyListeners();
    } catch (e) {
      debugPrint('진동 설정 저장 오류: $e');
    }
  }

  // 스피커 모드 업데이트 함수 추가
  Future<void> updateSpeakerMode(int mode) async {
    if (_speakerMode == mode) return;

    // 변경 전/후 모드 상태 기록
    final oldModeName = getSpeakerModeName(_speakerMode);
    final newModeName = getSpeakerModeName(mode);
    debugPrint(
        '🔊 스피커 모드 변경: $oldModeName -> $newModeName (값: $_speakerMode -> $mode)');

    _speakerMode = mode;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSpeakerModeKey, mode);

      // 네이티브 코드에도 설정 전달
      try {
        await _ttsChannel.invokeMethod('setAudioOutputMode', {'mode': mode});
        debugPrint(
            '🔊 네이티브 오디오 출력 모드 설정 성공: $mode (${getSpeakerModeName(mode)})');
      } catch (e) {
        debugPrint('❌ 네이티브 오디오 출력 모드 설정 오류: $e');
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
      default:
        return '자동 감지';
    }
  }
}
