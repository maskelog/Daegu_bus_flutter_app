import 'package:daegu_bus_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../models/bus_stop.dart';
import '../models/alarm_sound.dart';
import '../models/auto_alarm.dart';
import '../services/alarm_service.dart';
import '../services/settings_service.dart';
import '../widgets/time_picker_spinner.dart';
import 'search_screen.dart';
import '../main.dart' show logMessage, LogLevel;

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final List<AutoAlarm> _autoAlarms = [];
  final bool _isLoading = false;
  final List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  late SettingsService _settingsService;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService();
    _loadAutoAlarms();
    _initSettings();
  }

  Future<void> _initSettings() async {
    await _settingsService.initialize();
    setState(() {}); // UI 업데이트
  }

  Future<void> _loadAutoAlarms() async {
    try {
      logMessage('🔄 자동 알람 로드 시작');
      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('auto_alarms') ?? [];

      _autoAlarms.clear();

      for (var alarmJson in alarms) {
        try {
          final Map<String, dynamic> data = jsonDecode(alarmJson);
          final alarm = AutoAlarm.fromJson(data);
          _autoAlarms.add(alarm);
          logMessage('✅ 자동 알람 로드됨: ${alarm.routeNo}, ${alarm.stationName}');
        } catch (e) {
          logMessage('❌ 자동 알람 파싱 오류: $e', level: LogLevel.error);
        }
      }

      if (mounted) {
        setState(() {});
        logMessage('✅ 자동 알람 로드 완료: ${_autoAlarms.length}개');
      }
    } catch (e) {
      logMessage('❌ 자동 알람 로드 실패: $e', level: LogLevel.error);
    }
  }

  Future<void> _saveAutoAlarms() async {
    try {
      logMessage('🔄 자동 알람 저장 시작: ${_autoAlarms.length}개');
      final prefs = await SharedPreferences.getInstance();

      final List<String> alarms = _autoAlarms.map((alarm) {
        final json = alarm.toJson();
        logMessage('📝 알람 데이터 변환:');
        logMessage('  - 버스: ${alarm.routeNo}번');
        logMessage('  - 정류장: ${alarm.stationName}');
        logMessage('  - 시간: ${alarm.hour}:${alarm.minute}');
        logMessage(
            '  - 반복: ${alarm.repeatDays.map((d) => _weekdays[d - 1]).join(", ")}');
        return jsonEncode(json);
      }).toList();

      await prefs.setStringList('auto_alarms', alarms);
      logMessage('✅ 자동 알람 저장 완료');

      if (mounted) {
        final alarmService = Provider.of<AlarmService>(context, listen: false);
        await alarmService.updateAutoAlarms(_autoAlarms);
        logMessage('✅ AlarmService 업데이트 완료');
      }
    } catch (e) {
      logMessage('❌ 자동 알람 저장 오류: $e', level: LogLevel.error);
    }
  }

  void _addAutoAlarm() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchScreen()),
    );

    // 첫 번째 비동기 갭 이후에 mounted 체크 추가
    if (!mounted) return;

    if (result != null && result is BusStop) {
      final alarmResult = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AutoAlarmEditScreen(
            key: UniqueKey(),
            autoAlarm: null,
            selectedStation: result,
          ),
        ),
      );

      // 두 번째 비동기 갭 이후에 다시 mounted 체크 추가
      if (!mounted) return;

      if (alarmResult != null && alarmResult is AutoAlarm) {
        setState(() {
          _autoAlarms.add(alarmResult);
          _saveAutoAlarms();
        });
      }
    }
  }

  void _editAutoAlarm(int index) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AutoAlarmEditScreen(
          key: UniqueKey(),
          autoAlarm: _autoAlarms[index],
        ),
      ),
    );

    // 비동기 갭 이후에 mounted 체크 추가
    if (!mounted) return;

    if (result != null && result is AutoAlarm) {
      setState(() {
        _autoAlarms[index] = result;
        _saveAutoAlarms();
      });
    }
  }

  void _deleteAutoAlarm(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('자동 알림 삭제'),
        content: const Text('이 자동 알림 설정을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _autoAlarms.removeAt(index);
                _saveAutoAlarms();
              });
            },
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _toggleAutoAlarm(int index) {
    setState(() {
      _autoAlarms[index] = _autoAlarms[index].copyWith(
        isActive: !_autoAlarms[index].isActive,
      );
      _saveAutoAlarms();
    });
  }

  void _updateNotificationModeSetting(NotificationDisplayMode? value) {
    if (value != null) {
      final settingsService =
          Provider.of<SettingsService>(context, listen: false);
      if (settingsService.notificationDisplayMode != value) {
        settingsService.updateNotificationDisplayMode(value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('알림 표시 설정이 저장되었습니다.'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Widget _buildTtsOutputModeSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '일반 승차 알람 TTS 설정',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            RadioListTile<int>(
              title: const Text('이어폰 전용'),
              subtitle: const Text('이어폰으로만 TTS 알림을 출력합니다'),
              value: SettingsService.speakerModeHeadset,
              groupValue: _settingsService.speakerMode,
              onChanged: (value) {
                if (value != null) {
                  _settingsService.updateSpeakerMode(value);
                  setState(() {});
                }
              },
            ),
            RadioListTile<int>(
              title: const Text('스피커 전용'),
              subtitle: const Text('스피커로만 TTS 알림을 출력합니다'),
              value: SettingsService.speakerModeSpeaker,
              groupValue: _settingsService.speakerMode,
              onChanged: (value) {
                if (value != null) {
                  _settingsService.updateSpeakerMode(value);
                  setState(() {});
                }
              },
            ),
            RadioListTile<int>(
              title: const Text('자동 감지'),
              subtitle: const Text('연결된 오디오 장치에 따라 자동으로 선택합니다'),
              value: SettingsService.speakerModeAuto,
              groupValue: _settingsService.speakerMode,
              onChanged: (value) {
                if (value != null) {
                  _settingsService.updateSpeakerMode(value);
                  setState(() {});
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsService>(
      builder: (context, settingsService, child) {
        final currentNotificationMode = settingsService.notificationDisplayMode;

        return Scaffold(
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '자동 버스 알림',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add),
                                  onPressed: _addAutoAlarm,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // 자동 알람 볼륨 설정 추가
                            Consumer<SettingsService>(
                              builder: (context, settingsService, child) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '알람 볼륨',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        const Icon(Icons.volume_down),
                                        Expanded(
                                          child: Slider(
                                            value:
                                                settingsService.autoAlarmVolume,
                                            min: SettingsService
                                                .minAutoAlarmVolume,
                                            max: SettingsService
                                                .maxAutoAlarmVolume,
                                            divisions: 10,
                                            label:
                                                '${(settingsService.autoAlarmVolume * 100).round()}%',
                                            onChanged: (value) {
                                              settingsService
                                                  .updateAutoAlarmVolume(value);
                                            },
                                          ),
                                        ),
                                        const Icon(Icons.volume_up),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                            Text(
                              '출퇴근 시간이나 정기적으로 이용하는 버스에 대한 알림을 자동으로 설정하세요.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 알람음 설정을 간단한 선택으로 변경
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '알람음',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (context) => Container(
                                        padding: const EdgeInsets.all(16),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              '알람음 선택',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            ...AlarmSound.allSounds
                                                .map((sound) {
                                              final isSelected =
                                                  _settingsService
                                                          .alarmSoundId ==
                                                      sound.id;
                                              return ListTile(
                                                leading: Icon(
                                                  sound.icon,
                                                  color: isSelected
                                                      ? Colors.blue
                                                      : Colors.grey,
                                                ),
                                                title: Text(sound.name),
                                                trailing: isSelected
                                                    ? const Icon(
                                                        Icons.check_circle,
                                                        color: Colors.blue)
                                                    : null,
                                                onTap: () {
                                                  _settingsService
                                                      .setAlarmSound(sound.id);
                                                  Navigator.pop(context);
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                          '알람음이 "${sound.name}"으로 변경되었습니다'),
                                                      duration: const Duration(
                                                          seconds: 2),
                                                    ),
                                                  );
                                                },
                                              );
                                            }),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.volume_up),
                                  label: Text(
                                    AlarmSound.allSounds
                                        .firstWhere((s) =>
                                            s.id ==
                                            _settingsService.alarmSoundId)
                                        .name,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: _autoAlarms.isEmpty
                          ? SliverToBoxAdapter(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.notifications_off,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      '설정된 자동 알림이 없습니다',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '상단의 "알림 추가" 버튼을 눌러 새 자동 알림을 추가하세요',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final alarm = _autoAlarms[index];
                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.alarm,
                                                color: alarm.isActive
                                                    ? Colors.blue[700]
                                                    : Colors.grey[400],
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: alarm.isActive
                                                      ? Colors.black87
                                                      : Colors.grey[500],
                                                ),
                                              ),
                                              const Spacer(),
                                              Switch(
                                                value: alarm.isActive,
                                                onChanged: (_) =>
                                                    _toggleAutoAlarm(index),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.location_on,
                                                size: 16,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  alarm.stationName,
                                                  style: TextStyle(
                                                    color: Colors.grey[800],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.directions_bus,
                                                size: 16,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                alarm.routeNo,
                                                style: TextStyle(
                                                  color: Colors.grey[800],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.repeat,
                                                size: 16,
                                                color: Colors.grey[600],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                _getRepeatDaysText(alarm),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          if (alarm.excludeHolidays ||
                                              alarm.excludeWeekends)
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.event_busy,
                                                  size: 16,
                                                  color: Colors.grey[600],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _getExcludeText(alarm),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          const SizedBox(height: 12),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.end,
                                            children: [
                                              TextButton.icon(
                                                icon: const Icon(Icons.edit,
                                                    size: 16),
                                                label: const Text('수정'),
                                                onPressed: () =>
                                                    _editAutoAlarm(index),
                                              ),
                                              const SizedBox(width: 8),
                                              TextButton.icon(
                                                icon: const Icon(Icons.delete,
                                                    size: 16),
                                                label: const Text('삭제'),
                                                onPressed: () =>
                                                    _deleteAutoAlarm(index),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: Colors.red,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                                childCount: _autoAlarms.length,
                              ),
                            ),
                    ),
                    SliverToBoxAdapter(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '진행 중 알림 표시 방식',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '버스 추적 시 알림에 표시할 버스 범위',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 24),
                            RadioListTile<NotificationDisplayMode>(
                              title: const Text('알람 설정된 버스만'),
                              value: NotificationDisplayMode.alarmedOnly,
                              groupValue: currentNotificationMode,
                              onChanged: _updateNotificationModeSetting,
                              secondary:
                                  const Icon(Icons.alarm_on_outlined, size: 20),
                              contentPadding: const EdgeInsets.only(
                                  left: 32.0, right: 16.0),
                              visualDensity: VisualDensity.compact,
                              activeColor:
                                  Theme.of(context).colorScheme.primary,
                            ),
                            RadioListTile<NotificationDisplayMode>(
                              title: const Text('정류장의 모든 버스'),
                              subtitle: const Text('(가장 빨리 도착하는 버스 기준)'),
                              value: NotificationDisplayMode.allBuses,
                              groupValue: currentNotificationMode,
                              onChanged: _updateNotificationModeSetting,
                              secondary: const Icon(Icons.dynamic_feed_outlined,
                                  size: 20),
                              contentPadding: const EdgeInsets.only(
                                  left: 32.0, right: 16.0),
                              visualDensity: VisualDensity.compact,
                              activeColor:
                                  Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _buildTtsOutputModeSection(),
                    ),
                  ],
                ),
        );
      },
    );
  }

  String _getRepeatDaysText(AutoAlarm alarm) {
    if (alarm.repeatDays.isEmpty) return '반복 안함';
    if (alarm.repeatDays.length == 7) return '매일';
    if (alarm.repeatDays.length == 5 &&
        alarm.repeatDays.contains(1) &&
        alarm.repeatDays.contains(2) &&
        alarm.repeatDays.contains(3) &&
        alarm.repeatDays.contains(4) &&
        alarm.repeatDays.contains(5)) {
      return '평일 (월-금)';
    }
    if (alarm.repeatDays.length == 2 &&
        alarm.repeatDays.contains(6) &&
        alarm.repeatDays.contains(7)) {
      return '주말 (토,일)';
    }
    final days = alarm.repeatDays.map((day) => _weekdays[day - 1]).join(', ');
    return '매주 $days요일';
  }

  String _getExcludeText(AutoAlarm alarm) {
    List<String> excludes = [];
    if (alarm.excludeWeekends) excludes.add('주말 제외');
    if (alarm.excludeHolidays) excludes.add('공휴일 제외');
    return excludes.join(', ');
  }
}

class AutoAlarmEditScreen extends StatefulWidget {
  final AutoAlarm? autoAlarm;
  final BusStop? selectedStation;

  const AutoAlarmEditScreen({
    super.key,
    this.autoAlarm,
    this.selectedStation,
  });

  @override
  State<AutoAlarmEditScreen> createState() => _AutoAlarmEditScreenState();
}

class _AutoAlarmEditScreenState extends State<AutoAlarmEditScreen> {
  late int _hour;
  late int _minute;
  List<int> _repeatDays = [];
  bool _excludeWeekends = false;
  bool _excludeHolidays = false;
  bool _useTTS = true;

  late final TextEditingController _stationController;
  late final TextEditingController _routeController;

  BusStop? _selectedStation;
  String? _selectedRouteId;
  String? _selectedRouteNo;

  bool _isLoadingRoutes = false;
  List<Map<String, String>> _routeOptions = [];

  final List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  void initState() {
    super.initState();
    _stationController = TextEditingController();
    _routeController = TextEditingController();

    if (widget.autoAlarm != null) {
      final alarm = widget.autoAlarm!;
      _hour = alarm.hour;
      _minute = alarm.minute;
      _repeatDays = List.from(alarm.repeatDays);
      _excludeWeekends = alarm.excludeWeekends;
      _excludeHolidays = alarm.excludeHolidays;
      _useTTS = alarm.useTTS;
      _stationController.text = alarm.stationName;
      _routeController.text = alarm.routeNo;
      _selectedStation = BusStop(
          id: alarm.stationId, name: alarm.stationName, isFavorite: false);
      _selectedRouteId = alarm.routeId;
      _selectedRouteNo = alarm.routeNo;
      _loadRouteOptions().then((_) {
        // 노선이 하나 이상 있으면 자동으로 첫 번째 노선 선택 대신,
        // 모든 노선 목록을 표시하도록 하고 팝업은 표시하지 않음
      });
    } else {
      final now = DateTime.now();
      _hour = now.hour;
      _minute = now.minute;
      _repeatDays = [1, 2, 3, 4, 5];
      if (widget.selectedStation != null) {
        _selectedStation = widget.selectedStation;
        _stationController.text = _selectedStation!.name;
        _loadRouteOptions().then((_) {
          // 노선이 하나 이상 있으면 자동으로 첫 번째 노선 선택 대신,
          // 모든 노선 목록을 표시하도록 하고 팝업은 표시하지 않음
        });
      }
    }
  }

  @override
  void dispose() {
    _stationController.dispose();
    _routeController.dispose();
    super.dispose();
  }

  Future<void> _loadRouteOptions() async {
    if (_selectedStation == null) return;

    setState(() => _isLoadingRoutes = true);

    try {
      final stationId = _selectedStation!.id;
      debugPrint('정류장 ID: $stationId 에 대한 버스 정보 로드 시작');
      final arrivals = await ApiService.getStationInfo(stationId);
      debugPrint('정류장 정보 로드 완료: ${arrivals.length}개 버스 노선 발견');

      // 각 노선 정보 로깅
      for (var arrival in arrivals) {
        debugPrint('노선 정보: ${arrival.routeNo} (ID: ${arrival.routeId})');
      }

      // routeNo를 키로 사용하여 중복 제거 (routeId가 비어있기 때문)
      final uniqueRoutes = <String, Map<String, String>>{};
      for (var arrival in arrivals) {
        // routeNo를 키로 사용
        uniqueRoutes[arrival.routeNo] = {
          'id': arrival.routeId.isEmpty
              ? arrival.routeNo
              : arrival.routeId, // 빈 ID면 routeNo를 ID로 사용
          'routeNo': arrival.routeNo,
        };
      }

      if (mounted) {
        setState(() {
          _routeOptions = uniqueRoutes.values.toList();
          _isLoadingRoutes = false;
        });
        debugPrint('노선 옵션 설정 완료: ${_routeOptions.length}개 고유 노선');

        // 노선 목록 출력
        for (var route in _routeOptions) {
          debugPrint('노선 옵션: ${route['routeNo']} (ID: ${route['id']})');
        }
      }
    } catch (e) {
      debugPrint('노선 정보 로드 오류: $e');
      if (mounted) {
        setState(() {
          _routeOptions = [];
          _isLoadingRoutes = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('노선 정보를 불러오지 못했습니다')),
        );
      }
    }
  }

  void _selectRoute(String routeId, String routeNo) {
    if (!mounted) return;

    setState(() {
      _selectedRouteId = routeId;
      _selectedRouteNo = routeNo;
      _routeController.text = routeNo;
    });

    // 선택 피드백 제공
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$routeNo 노선이 선택되었습니다'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  void _toggleDay(int day) {
    if (!mounted) return;

    setState(() {
      if (_repeatDays.contains(day)) {
        _repeatDays.remove(day);
      } else {
        _repeatDays.add(day);
      }
    });
  }

  void _save() {
    // Validate essential fields before saving
    if (_selectedStation == null || _selectedStation!.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정류장을 먼저 선택해주세요.')),
      );
      return;
    }
    if (_selectedRouteId == null ||
        _selectedRouteId!.isEmpty ||
        _selectedRouteNo == null ||
        _selectedRouteNo!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('노선을 먼저 선택해주세요.')),
      );
      return;
    }
    if (_repeatDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 하나 이상의 반복 요일을 선택해주세요.')),
      );
      return;
    }
    // Add checks for hour and minute if necessary (though TimePickerSpinner likely handles this)
    if (_hour < 0 || _hour > 23 || _minute < 0 || _minute > 59) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('유효하지 않은 시간입니다.')),
      );
      return;
    }

    // Create the AutoAlarm object only after validation passes
    final alarm = AutoAlarm(
      id: widget.autoAlarm?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      hour: _hour,
      minute: _minute,
      stationId: _selectedStation!.id, // Ensured not null by validation
      stationName: _selectedStation!.name, // Ensured not null by validation
      routeId: _selectedRouteId!, // Ensured not null or empty by validation
      routeNo: _selectedRouteNo!, // Ensured not null or empty by validation
      repeatDays: _repeatDays, // Ensured not empty by validation
      excludeWeekends: _excludeWeekends,
      excludeHolidays: _excludeHolidays,
      isActive: widget.autoAlarm?.isActive ?? true,
      useTTS: _useTTS,
    );

    Navigator.pop(context, alarm);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.autoAlarm == null ? '자동 알림 추가' : '자동 알림 수정'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('저장'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('알림 시간',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SizedBox(
              height: 150,
              child: TimePickerSpinner(
                key: UniqueKey(),
                is24HourMode: true,
                normalTextStyle:
                    TextStyle(fontSize: 18, color: Colors.grey[500]),
                highlightedTextStyle: const TextStyle(
                    fontSize: 22,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold),
                time: DateTime(2023, 1, 1, _hour, _minute),
                onTimeChange: (time) {
                  if (mounted) {
                    setState(() {
                      _hour = time.hour;
                      _minute = time.minute;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            const Text('반복',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(7, (index) {
                final day = index + 1;
                final isSelected = _repeatDays.contains(day);
                return InkWell(
                  onTap: () => _toggleDay(day),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? Colors.blue : Colors.grey[200],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _weekdays[index],
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => _repeatDays = [1, 2, 3, 4, 5]),
                  child: const Text('평일'),
                ),
                TextButton(
                  onPressed: () => setState(() => _repeatDays = [6, 7]),
                  child: const Text('주말'),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _repeatDays = [1, 2, 3, 4, 5, 6, 7]),
                  child: const Text('매일'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('제외 설정',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            CheckboxListTile(
              title: const Text('주말 제외'),
              value: _excludeWeekends,
              onChanged: (value) =>
                  setState(() => _excludeWeekends = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              title: const Text('공휴일 제외'),
              value: _excludeHolidays,
              onChanged: (value) =>
                  setState(() => _excludeHolidays = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 24),
            const Text('정류장',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _stationController,
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'SearchScreen에서 정류장을 선택하세요',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              ),
            ),
            const SizedBox(height: 24),
            const Text('노선',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _routeController,
              readOnly: true,
              enabled: false,
              decoration: InputDecoration(
                hintText: '아래 노선 목록에서 선택하세요',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                fillColor:
                    _selectedRouteId != null ? Colors.blue.shade50 : null,
                filled: _selectedRouteId != null,
              ),
            ),
            if (_isLoadingRoutes)
              const Center(
                  child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: CircularProgressIndicator())),
            if (!_isLoadingRoutes && _routeOptions.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  const Text('노선 목록',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      )),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    height: _routeOptions.length > 4 ? 200 : null, // 높이 제한
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: _routeOptions.length > 4
                          ? const AlwaysScrollableScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: _routeOptions.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: Colors.grey.shade300),
                      itemBuilder: (context, index) {
                        final route = _routeOptions[index];
                        final isSelected = _selectedRouteId == route['id'];
                        return ListTile(
                          title: Text(route['routeNo']!),
                          selected: isSelected,
                          selectedTileColor: Colors.blue.shade50,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          textColor: isSelected ? Colors.blue.shade700 : null,
                          onTap: () =>
                              _selectRoute(route['id']!, route['routeNo']!),
                        );
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            const Text('알림 설정',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '버스 도착 정보를 알림과 음성으로 알려드립니다',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.volume_up,
                      color: _useTTS ? Colors.blue : Colors.grey,
                    ),
                    title: const Text('음성 알림'),
                    subtitle: Text(
                      '버스 도착 정보를 음성으로 알려드립니다',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    trailing: Switch(
                      value: _useTTS,
                      onChanged: (value) => setState(() => _useTTS = value),
                    ),
                  ),
                  if (_useTTS)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        '예시: "대구 101번 버스가 3분 후에 도착합니다"',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
