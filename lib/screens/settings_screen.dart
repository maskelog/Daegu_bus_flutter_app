import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../models/alarm_sound.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 선택된 값을 관리할 변수 (초기값은 SettingsService에서 로드)
  NotificationDisplayMode _selectedNotificationMode =
      NotificationDisplayMode.alarmedOnly;

  @override
  void initState() {
    super.initState();
    // 위젯이 빌드된 후 SettingsService에서 값을 로드
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  // 설정 서비스에서 현재 설정 값 로드
  void _loadSettings() {
    final settingsService =
        Provider.of<SettingsService>(context, listen: false);
    setState(() {
      _selectedNotificationMode = settingsService.notificationDisplayMode;
      // Load other settings if needed for this screen
    });
  }

  // 선택된 알림 모드를 설정 서비스에 저장하는 함수
  void _updateNotificationModeSetting(NotificationDisplayMode? value) {
    if (value != null && value != _selectedNotificationMode) {
      final settingsService =
          Provider.of<SettingsService>(context, listen: false);
      settingsService.updateNotificationDisplayMode(value);
      setState(() {
        _selectedNotificationMode = value;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('알림 표시 설정이 저장되었습니다.'),
        duration: Duration(seconds: 1),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Consumer를 사용하여 SettingsService의 변경사항을 감지하고 UI 업데이트
    return Consumer<SettingsService>(
      builder: (context, settingsService, child) {
        // SettingsService에서 직접 값을 가져와 groupValue에 사용
        _selectedNotificationMode = settingsService.notificationDisplayMode;
        // 다른 설정 값들도 필요하면 여기서 가져옴
        // final currentAlarmSoundId = settingsService.alarmSoundId;
        // final useTts = settingsService.useTts;

        return Scaffold(
          appBar: AppBar(
            title: const Text('설정'),
            elevation: 0,
          ),
          body: Consumer<SettingsService>(
            builder: (context, settingsService, child) {
              if (settingsService.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              return ListView(
                children: [
                  _buildSectionHeader(context, '알림 설정'),
                  _buildAlarmSoundSelector(context, settingsService),

                  _buildSectionHeader(context, 'TTS 설정'),
                  SwitchListTile(
                    title: const Text('음성 안내 사용'),
                    subtitle: const Text('버스 도착 정보를 음성으로 안내합니다'),
                    value: settingsService.useTts,
                    onChanged: (value) => settingsService.updateUseTts(value),
                  ),

                  // 스피커 모드 선택 UI 추가
                  _buildSpeakerModeSelector(context, settingsService),

                  _buildSectionHeader(context, '진동 설정'),
                  SwitchListTile(
                    title: const Text('진동 사용'),
                    subtitle: const Text('알림 시 진동을 사용합니다'),
                    value: settingsService.vibrate,
                    onChanged: (value) => settingsService.updateVibrate(value),
                  ),

                  _buildSectionHeader(context, '테마 설정'),
                  _buildThemeModeSelector(context, settingsService),

                  // --- 신규: 추적 알림 표시 방식 설정 ---
                  const ListTile(
                    leading: Icon(Icons.notifications_active_outlined),
                    title: Text('진행 중 알림 표시 방식'),
                    subtitle: Text('버스 추적 시 알림에 표시할 버스 범위'),
                  ),
                  RadioListTile<NotificationDisplayMode>(
                    title: const Text('알람 설정된 버스만 표시'),
                    value: NotificationDisplayMode.alarmedOnly,
                    groupValue: _selectedNotificationMode, // 상태 변수 사용
                    onChanged: _updateNotificationModeSetting, // 업데이트 함수 호출
                    secondary: const Icon(Icons.alarm_on_outlined), // 아이콘 변경
                    contentPadding:
                        const EdgeInsets.only(left: 32.0, right: 16.0), // 들여쓰기
                    visualDensity: VisualDensity.compact, // 좀 더 컴팩트하게
                  ),
                  RadioListTile<NotificationDisplayMode>(
                    title: const Text('정류장의 모든 버스 표시'),
                    subtitle: const Text('가장 빨리 도착하는 버스 기준 정보'), // 부제 수정
                    value: NotificationDisplayMode.allBuses,
                    groupValue: _selectedNotificationMode, // 상태 변수 사용
                    onChanged: _updateNotificationModeSetting, // 업데이트 함수 호출
                    secondary:
                        const Icon(Icons.dynamic_feed_outlined), // 아이콘 변경
                    contentPadding:
                        const EdgeInsets.only(left: 32.0, right: 16.0), // 들여쓰기
                    visualDensity: VisualDensity.compact, // 좀 더 컴팩트하게
                  ),
                  // --- 끝: 추적 알림 표시 방식 설정 ---
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildAlarmSoundSelector(
      BuildContext context, SettingsService settingsService) {
    return ListTile(
      title: const Text('알람 소리'),
      subtitle: Text(settingsService.selectedAlarmSound.name),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final result = await showDialog<String>(
          context: context,
          builder: (context) => _AlarmSoundDialog(
            selectedId: settingsService.alarmSoundId,
          ),
        );

        if (result != null) {
          settingsService.setAlarmSound(result);
        }
      },
    );
  }

  // 스피커 모드 선택 UI 구현
  Widget _buildSpeakerModeSelector(
      BuildContext context, SettingsService settingsService) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '음성 출력 모드',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
        RadioListTile<int>(
          title: const Text('이어폰 전용'),
          subtitle: const Text('이어폰이 연결된 경우에만 음성 안내'),
          value: SettingsService.speakerModeHeadset,
          groupValue: settingsService.speakerMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateSpeakerMode(value);
            }
          },
        ),
        RadioListTile<int>(
          title: const Text('스피커 전용'),
          subtitle: const Text('항상 스피커로 음성 안내'),
          value: SettingsService.speakerModeSpeaker,
          groupValue: settingsService.speakerMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateSpeakerMode(value);
            }
          },
        ),
        RadioListTile<int>(
          title: const Text('자동 감지 (기본값)'),
          subtitle: const Text('시스템이 적절한 출력 장치 자동 선택'),
          value: SettingsService.speakerModeAuto,
          groupValue: settingsService.speakerMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateSpeakerMode(value);
            }
          },
        ),
      ],
    );
  }

  // 테마 모드 선택 UI 구현
  Widget _buildThemeModeSelector(
      BuildContext context, SettingsService settingsService) {
    return Column(
      children: [
        RadioListTile<ThemeMode>(
          title: const Text('라이트 모드'),
          value: ThemeMode.light,
          groupValue: settingsService.themeMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateThemeMode(value);
            }
          },
        ),
        RadioListTile<ThemeMode>(
          title: const Text('다크 모드'),
          value: ThemeMode.dark,
          groupValue: settingsService.themeMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateThemeMode(value);
            }
          },
        ),
        RadioListTile<ThemeMode>(
          title: const Text('시스템 설정 따르기 (기본값)'),
          value: ThemeMode.system,
          groupValue: settingsService.themeMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateThemeMode(value);
            }
          },
        ),
      ],
    );
  }
}

class _AlarmSoundDialog extends StatelessWidget {
  final String selectedId;

  const _AlarmSoundDialog({
    required this.selectedId,
  });

  @override
  Widget build(BuildContext context) {
    // Get all sound options from AlarmSound class
    final allSounds = [
      AlarmSound.ttsAlarm,
      AlarmSound.defaultSound,
      AlarmSound.silent,
    ];

    return AlertDialog(
      title: const Text('알람 소리 선택'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: allSounds
              .map(
                (sound) => RadioListTile<String>(
                  title: Text(sound.name),
                  value: sound.id,
                  groupValue: selectedId,
                  onChanged: (value) {
                    Navigator.of(context).pop(value);
                  },
                ),
              )
              .toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
      ],
    );
  }
}
