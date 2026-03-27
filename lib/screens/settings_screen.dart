import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/permission_service.dart';
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
                    onChanged: (value) => settingsService.updateThemeMode(
                      value ? ThemeMode.dark : ThemeMode.light,
                    ),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildSwitchTile(
                    context,
                    title: '진동',
                    icon: Icons.vibration,
                    value: settingsService.vibrate,
                    onChanged: (value) => settingsService.updateVibrate(value),
                  ),
                  if (Platform.isAndroid) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    const _LiveUpdatesTile(),
                  ],
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
                    onChanged: (value) => settingsService.updateUseTts(value),
                  ),
                  if (settingsService.useTts) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _buildSpeakerModeDropdown(context, settingsService),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _buildTtsTestButton(context, settingsService),
                  ],
                ],
              ),

              const SizedBox(height: 16),

              // 텍스트 크기 섹션
              _buildSectionCard(
                context,
                title: '텍스트 크기',
                icon: Icons.text_fields_outlined,
                children: [
                  _buildFontSizeSlider(context, settingsService),
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
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildCustomExcludeDateSelector(context, settingsService),
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

  Widget _buildCustomExcludeDateSelector(
      BuildContext context, SettingsService settingsService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final excludeCount = settingsService.customExcludeDates.length;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        Icons.event_busy_outlined,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
      title: Text(
        '나만의 알람 예외 날짜',
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        excludeCount > 0 ? '$excludeCount일 설정됨' : '설정된 날짜 없음',
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
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const _CustomExcludeDatesScreen(),
          ),
        );
      },
    );
  }

  /// 폰트 크기 슬라이더 + 미리보기 텍스트
  Widget _buildFontSizeSlider(
      BuildContext context, SettingsService settingsService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final multiplier = settingsService.fontSizeMultiplier;
    final percent = (multiplier * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.text_decrease,
                  color: colorScheme.onSurfaceVariant, size: 18),
              Expanded(
                child: Slider(
                  value: multiplier,
                  min: SettingsService.minFontSizeMultiplier,
                  max: SettingsService.maxFontSizeMultiplier,
                  divisions: 12,
                  label: "$percent%",
                  onChanged: (value) =>
                      settingsService.updateFontSizeMultiplier(value),
                ),
              ),
              Icon(Icons.text_increase,
                  color: colorScheme.onSurfaceVariant, size: 18),
            ],
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withAlpha(60),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant, width: 1),
            ),
            child: Text(
              "버스가 곧 도착합니다 ($percent%)",
              style: TextStyle(
                  fontSize: 14 * multiplier, color: colorScheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  /// TTS 테스트 버튼
  Widget _buildTtsTestButton(
      BuildContext context, SettingsService settingsService) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(Icons.play_circle_outline,
          color: colorScheme.onSurfaceVariant, size: 24),
      title: Text(
        'TTS 테스트',
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500, color: colorScheme.onSurface),
      ),
      subtitle: Text(
        '"버스가 곧 도착합니다" 음성 재생',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: colorScheme.onSurfaceVariant),
      ),
      trailing: OutlinedButton(
        onPressed: () async {
          try {
            final tts = FlutterTts();
            await tts.setLanguage('ko-KR');
            await tts.speak('버스가 곧 도착합니다.');
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('TTS 재생 오류: $e')));
            }
          }
        },
        child: const Text('테스트'),
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

class _CustomExcludeDatesScreen extends StatefulWidget {
  const _CustomExcludeDatesScreen();

  @override
  State<_CustomExcludeDatesScreen> createState() =>
      _CustomExcludeDatesScreenState();
}

class _CustomExcludeDatesScreenState extends State<_CustomExcludeDatesScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          '나만의 예외 날짜 관리',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<SettingsService>(
        builder: (context, settingsService, child) {
          final dates = List<DateTime>.from(settingsService.customExcludeDates);
          dates.sort(); // 오름차순 정렬

          if (dates.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.event_available_outlined,
                        size: 64, color: colorScheme.outlineVariant),
                    const SizedBox(height: 16),
                    Text(
                      '나만의 예외 날짜가 없습니다.',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '하단의 + 버튼을 눌러 연차나 휴가 등 자동 알람을 울리지 않을 날짜를 추가해보세요.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: dates.length,
            itemBuilder: (context, index) {
              final date = dates[index];
              final dateStr = '${date.year}년 ${date.month}월 ${date.day}일';
              final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
              final weekdayStr = weekdays[date.weekday - 1];

              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLowest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading:
                      Icon(Icons.calendar_today, color: colorScheme.primary),
                  title: Text(
                    '$dateStr ($weekdayStr)',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.remove_circle_outline,
                        color: colorScheme.error),
                    onPressed: () {
                      settingsService.removeCustomExcludeDate(date);
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: Consumer<SettingsService>(
        builder: (context, settingsService, child) {
          return FloatingActionButton.extended(
            onPressed: () async {
              final selectedDate = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );

              if (selectedDate != null) {
                settingsService.addCustomExcludeDate(selectedDate);
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('날짜 추가'),
          );
        },
      ),
    );
  }
}

class _LiveUpdatesTile extends StatefulWidget {
  const _LiveUpdatesTile();

  @override
  State<_LiveUpdatesTile> createState() => _LiveUpdatesTileState();
}

class _LiveUpdatesTileState extends State<_LiveUpdatesTile> {
  bool? _enabled; // null = not applicable (SDK < 36)
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 36) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final result = await PermissionService.canPostPromotedNotifications();
      if (mounted)
        setState(() {
          _enabled = result;
          _loading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _enabled == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = _enabled!;

    return ListTile(
      leading: Icon(
        Icons.update_rounded,
        color: enabled ? colorScheme.primary : colorScheme.error,
      ),
      title: const Text('실시간 정보 (Live Updates)'),
      subtitle: Text(
        enabled ? '활성화됨 - 상태바 / Now Bar에 버스 정보 표시' : '비활성화됨 - 탭하여 설정 열기',
        style: theme.textTheme.bodySmall?.copyWith(
          color: enabled ? colorScheme.onSurfaceVariant : colorScheme.error,
        ),
      ),
      trailing: enabled
          ? Icon(Icons.check_circle_outline, color: colorScheme.primary)
          : Icon(Icons.open_in_new, color: colorScheme.error),
      onTap: enabled
          ? null
          : () async {
              await PermissionService.requestPromotedNotificationPermission();
              await _check();
            },
    );
  }
}
