import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/settings_service.dart';
import '../models/alarm_sound.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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
              // 일반 섹션
              _buildSectionCard(
                context,
                title: '일반',
                icon: Icons.settings_outlined,
                children: [
                  _buildSwitchTile(
                    context,
                    title: '다크 모드',
                    icon: Icons.dark_mode_outlined,
                    value: settingsService.themeMode == ThemeMode.dark,
                    onChanged: (value) {
                      settingsService.updateThemeMode(
                        value ? ThemeMode.dark : ThemeMode.light,
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildSwitchTile(
                    context,
                    title: '진동',
                    icon: Icons.vibration,
                    value: settingsService.vibrate,
                    onChanged: (value) =>
                        settingsService.updateVibrate(value),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 음성 안내 섹션
              _buildSectionCard(
                context,
                title: '음성 안내',
                icon: Icons.record_voice_over_outlined,
                children: [
                  _buildSwitchTile(
                    context,
                    title: '음성 안내 사용',
                    icon: Icons.volume_up_outlined,
                    value: settingsService.useTts,
                    onChanged: (value) =>
                        settingsService.updateUseTts(value),
                  ),
                  if (settingsService.useTts) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _buildSpeakerModeDropdown(context, settingsService),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // 알람 섹션
              _buildSectionCard(
                context,
                title: '알람',
                icon: Icons.alarm_outlined,
                children: [
                  _buildAlarmSoundSelector(context, settingsService),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildAutoAlarmTimeoutDropdown(context, settingsService),
                ],
              ),
            ],
          );
        },
      ),
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
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: colorScheme.primary,
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

  Widget _buildSpeakerModeDropdown(
      BuildContext context, SettingsService settingsService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final modes = <int, String>{
      SettingsService.speakerModeHeadset: '이어폰 전용',
      SettingsService.speakerModeSpeaker: '스피커 전용',
      SettingsService.speakerModeAuto: '자동 감지',
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        Icons.headphones_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
      title: Text(
        '출력 모드',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
      trailing: DropdownButton<int>(
        value: settingsService.speakerMode,
        underline: const SizedBox.shrink(),
        onChanged: (value) {
          if (value != null) {
            settingsService.updateSpeakerMode(value);
          }
        },
        items: modes.entries
            .map((e) => DropdownMenuItem<int>(
                  value: e.key,
                  child: Text(
                    e.value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildAutoAlarmTimeoutDropdown(
      BuildContext context, SettingsService settingsService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    const options = <int>[5, 10, 15, 30, 45, 60, 90, 120];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        Icons.timer_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
      title: Text(
        '자동알람 종료시간',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
      trailing: DropdownButton<int>(
        value: settingsService.autoAlarmTimeoutMinutes,
        underline: const SizedBox.shrink(),
        onChanged: (value) {
          if (value != null) {
            settingsService.updateAutoAlarmTimeoutMinutes(value);
          }
        },
        items: options
            .map((m) => DropdownMenuItem<int>(
                  value: m,
                  child: Text(
                    '$m분',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ))
            .toList(),
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
        child: RadioGroup<String>(
          groupValue: selectedId,
          onChanged: (value) {
            Navigator.of(context).pop(value);
          },
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
                    toggleable: true,
                  ),
                )
                .toList(),
          ),
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
