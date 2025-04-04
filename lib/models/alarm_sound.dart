import 'package:flutter/material.dart';

class AlarmSound {
  final String id;
  final String name;
  final String filename;
  final IconData icon;
  final bool useTts;

  const AlarmSound({
    required this.id,
    required this.name,
    required this.filename,
    required this.icon,
    this.useTts = false,
  });

  static const defaultSound = AlarmSound(
    id: 'default',
    name: '기본 알람',
    filename: 'alarm_sound',
    icon: Icons.notifications_active,
  );

  static const vibrationOnly = AlarmSound(
    id: 'vibration_only',
    name: '진동만',
    filename: '', // 빈 파일명은 소리 없음을 의미
    icon: Icons.vibration,
  );

  static const silent = AlarmSound(
    id: 'silent',
    name: '무음',
    filename: 'silent',
    icon: Icons.notifications_off,
  );

  static const ttsAlarm = AlarmSound(
    id: 'tts',
    name: 'TTS 음성 알림',
    filename: 'tts_alarm',
    icon: Icons.record_voice_over,
    useTts: true,
  );

  // 모든 알람음 목록
  static const List<AlarmSound> allSounds = [
    defaultSound,
    ttsAlarm,
    vibrationOnly,
    silent,
  ];

  // 알람음 ID로 찾기
  static AlarmSound findById(String id) {
    return allSounds.firstWhere(
      (sound) => sound.id == id,
      orElse: () => defaultSound,
    );
  }
}
