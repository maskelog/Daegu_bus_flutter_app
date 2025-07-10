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
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        // SettingsService에서 직접 값을 가져와 groupValue에 사용
        _selectedNotificationMode = settingsService.notificationDisplayMode;

        return Scaffold(
          backgroundColor: colorScheme.surface,
          appBar: AppBar(
            title: Text(
              '설정',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            backgroundColor: colorScheme.surface,
            surfaceTintColor: colorScheme.surfaceTint,
            elevation: 0,
            centerTitle: true,
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(
                Icons.arrow_back,
                color: colorScheme.onSurface,
              ),
            ),
          ),
          body: Consumer<SettingsService>(
            builder: (context, settingsService, child) {
              if (settingsService.isLoading) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        '설정을 불러오는 중...',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  // 알림 설정 섹션
                  _buildSectionCard(
                    context,
                    title: '알림 설정',
                    icon: Icons.notifications_outlined,
                    children: [
                      _buildAlarmSoundSelector(context, settingsService),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _buildSwitchTile(
                        context,
                        title: '진동 사용',
                        subtitle: '알림 시 진동을 사용합니다',
                        icon: Icons.vibration,
                        value: settingsService.vibrate,
                        onChanged: (value) =>
                            settingsService.updateVibrate(value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // TTS 설정 섹션
                  _buildSectionCard(
                    context,
                    title: 'TTS 설정',
                    icon: Icons.record_voice_over_outlined,
                    children: [
                      _buildSwitchTile(
                        context,
                        title: '음성 안내 사용',
                        subtitle: '버스 도착 정보를 음성으로 안내합니다',
                        icon: Icons.volume_up_outlined,
                        value: settingsService.useTts,
                        onChanged: (value) =>
                            settingsService.updateUseTts(value),
                      ),
                      if (settingsService.useTts) ...[
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        _buildSpeakerModeSelector(context, settingsService),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 자동 알람 설정 섹션
                  _buildSectionCard(
                    context,
                    title: '자동 알람 설정',
                    icon: Icons.schedule_outlined,
                    children: [
                      _buildSwitchTile(
                        context,
                        title: '자동 알람 사용',
                        subtitle: '설정된 시간에 자동으로 버스 도착 알림 (항상 스피커 출력)',
                        icon: Icons.alarm_outlined,
                        value: settingsService.useAutoAlarm,
                        onChanged: (value) =>
                            settingsService.updateUseAutoAlarm(value),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 테마 설정 섹션
                  _buildSectionCard(
                    context,
                    title: '테마 설정',
                    icon: Icons.palette_outlined,
                    children: [
                      _buildThemeModeSelector(context, settingsService),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      _buildColorSchemeSelector(context, settingsService),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 알림 표시 방식 설정 섹션
                  _buildSectionCard(
                    context,
                    title: '알림 표시 방식',
                    icon: Icons.notifications_active_outlined,
                    children: [
                      _buildNotificationModeSelector(context, settingsService),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        icon,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: colorScheme.primary,
        activeTrackColor: colorScheme.primaryContainer,
        inactiveThumbColor: colorScheme.outline,
        inactiveTrackColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }

  Widget _buildAlarmSoundSelector(
      BuildContext context, SettingsService settingsService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        Icons.music_note_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
      title: Text(
        '알람 소리',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        settingsService.selectedAlarmSound.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withAlpha(77),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.chevron_right,
          color: colorScheme.onSecondaryContainer,
          size: 20,
        ),
      ),
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

  Widget _buildNotificationModeSelector(
      BuildContext context, SettingsService settingsService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '버스 추적 시 알림에 표시할 버스 범위',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildRadioTile<NotificationDisplayMode>(
          context,
          title: '알람 설정된 버스만 표시',
          icon: Icons.alarm_on_outlined,
          value: NotificationDisplayMode.alarmedOnly,
          groupValue: _selectedNotificationMode,
          onChanged: _updateNotificationModeSetting,
        ),
        _buildRadioTile<NotificationDisplayMode>(
          context,
          title: '정류장의 모든 버스 표시',
          subtitle: '가장 빨리 도착하는 버스 기준 정보',
          icon: Icons.dynamic_feed_outlined,
          value: NotificationDisplayMode.allBuses,
          groupValue: _selectedNotificationMode,
          onChanged: _updateNotificationModeSetting,
        ),
      ],
    );
  }

  Widget _buildSpeakerModeSelector(
      BuildContext context, SettingsService settingsService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.volume_up_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                '음성 출력 모드',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _buildRadioTile<int>(
          context,
          title: '이어폰 전용',
          subtitle: '이어폰이 연결된 경우에만 음성 안내',
          icon: Icons.headphones_outlined,
          value: SettingsService.speakerModeHeadset,
          groupValue: settingsService.speakerMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateSpeakerMode(value);
            }
          },
        ),
        _buildRadioTile<int>(
          context,
          title: '스피커 전용',
          subtitle: '항상 스피커로 음성 안내',
          icon: Icons.speaker_outlined,
          value: SettingsService.speakerModeSpeaker,
          groupValue: settingsService.speakerMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateSpeakerMode(value);
            }
          },
        ),
        _buildRadioTile<int>(
          context,
          title: '자동 감지 (기본값)',
          subtitle: '시스템이 적절한 출력 장치 자동 선택',
          icon: Icons.auto_mode_outlined,
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

  Widget _buildThemeModeSelector(
      BuildContext context, SettingsService settingsService) {
    return Column(
      children: [
        _buildRadioTile<ThemeMode>(
          context,
          title: '라이트 모드',
          icon: Icons.light_mode_outlined,
          value: ThemeMode.light,
          groupValue: settingsService.themeMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateThemeMode(value);
            }
          },
        ),
        _buildRadioTile<ThemeMode>(
          context,
          title: '다크 모드',
          icon: Icons.dark_mode_outlined,
          value: ThemeMode.dark,
          groupValue: settingsService.themeMode,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateThemeMode(value);
            }
          },
        ),
        _buildRadioTile<ThemeMode>(
          context,
          title: '시스템 설정 따름',
          icon: Icons.settings_system_daydream_outlined,
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

  Widget _buildColorSchemeSelector(
      BuildContext context, SettingsService settingsService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.palette_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                '색상 테마',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        _buildRadioTile<ColorSchemeType>(
          context,
          title: '블루',
          icon: Icons.palette_outlined,
          value: ColorSchemeType.blue,
          groupValue: settingsService.colorScheme,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateColorScheme(value);
            }
          },
        ),
        _buildRadioTile<ColorSchemeType>(
          context,
          title: '그린',
          icon: Icons.palette_outlined,
          value: ColorSchemeType.green,
          groupValue: settingsService.colorScheme,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateColorScheme(value);
            }
          },
        ),
        _buildRadioTile<ColorSchemeType>(
          context,
          title: '퍼플',
          icon: Icons.palette_outlined,
          value: ColorSchemeType.purple,
          groupValue: settingsService.colorScheme,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateColorScheme(value);
            }
          },
        ),
        _buildRadioTile<ColorSchemeType>(
          context,
          title: '오렌지',
          icon: Icons.palette_outlined,
          value: ColorSchemeType.orange,
          groupValue: settingsService.colorScheme,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateColorScheme(value);
            }
          },
        ),
        _buildRadioTile<ColorSchemeType>(
          context,
          title: '핑크',
          icon: Icons.palette_outlined,
          value: ColorSchemeType.pink,
          groupValue: settingsService.colorScheme,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateColorScheme(value);
            }
          },
        ),
        _buildRadioTile<ColorSchemeType>(
          context,
          title: '레드',
          icon: Icons.palette_outlined,
          value: ColorSchemeType.red,
          groupValue: settingsService.colorScheme,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateColorScheme(value);
            }
          },
        ),
        _buildRadioTile<ColorSchemeType>(
          context,
          title: '틸',
          icon: Icons.palette_outlined,
          value: ColorSchemeType.teal,
          groupValue: settingsService.colorScheme,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateColorScheme(value);
            }
          },
        ),
        _buildRadioTile<ColorSchemeType>(
          context,
          title: '인디고',
          icon: Icons.palette_outlined,
          value: ColorSchemeType.indigo,
          groupValue: settingsService.colorScheme,
          onChanged: (value) {
            if (value != null) {
              settingsService.updateColorScheme(value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildRadioTile<T>(
    BuildContext context, {
    required String title,
    String? subtitle,
    required IconData icon,
    required T value,
    required T? groupValue,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = value == groupValue;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primaryContainer.withAlpha(77)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: RadioListTile<T>(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurface,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isSelected
                      ? colorScheme.onPrimaryContainer.withAlpha(204)
                      : colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        secondary: Icon(
          icon,
          color: isSelected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
          size: 20,
        ),
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        activeColor: colorScheme.primary,
        visualDensity: VisualDensity.compact,
      ),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Get all sound options from AlarmSound class
    final allSounds = [
      AlarmSound.ttsAlarm,
      AlarmSound.defaultSound,
      AlarmSound.silent,
    ];

    return AlertDialog(
      backgroundColor: colorScheme.surface,
      title: Text(
        '알람 소리 선택',
        style: theme.textTheme.headlineSmall?.copyWith(
          color: colorScheme.onSurface,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: allSounds
              .map(
                (sound) => RadioListTile<String>(
                  title: Text(
                    sound.name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  value: sound.id,
                  groupValue: selectedId,
                  activeColor: colorScheme.primary,
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
          child: Text(
            '취소',
            style: TextStyle(
              color: colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
