import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import '../models/alarm_sound.dart';

class SettingsService extends ChangeNotifier {
  static const String _alarmSoundKey = 'alarm_sound_id';
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/notification');

  // 싱글톤 패턴
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  String _alarmSoundId = AlarmSound.defaultSound.id;
  bool _isLoading = true;

  // Getters
  String get alarmSoundId => _alarmSoundId;
  AlarmSound get selectedAlarmSound => AlarmSound.findById(_alarmSoundId);
  bool get isLoading => _isLoading;

  // 설정 초기화
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _alarmSoundId =
          prefs.getString(_alarmSoundKey) ?? AlarmSound.defaultSound.id;
      await _updateNativeAlarmSound();
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
}
