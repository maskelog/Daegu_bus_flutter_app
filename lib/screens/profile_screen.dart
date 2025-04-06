import 'package:daegu_bus_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../models/bus_stop.dart';
import '../models/alarm_sound.dart';
import '../services/alarm_service.dart';
import '../services/settings_service.dart';
import '../widgets/time_picker_spinner.dart';
import 'search_screen.dart';

class AutoAlarm {
  final String id;
  final int hour;
  final int minute;
  final String stationId;
  final String stationName;
  final String routeId;
  final String routeNo;
  final List<int> repeatDays;
  final bool excludeWeekends;
  final bool excludeHolidays;
  final bool isActive;
  final bool useTTS; // TTS 알림 사용 여부

  const AutoAlarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.stationId,
    required this.stationName,
    required this.routeId,
    required this.routeNo,
    required this.repeatDays,
    required this.excludeWeekends,
    required this.excludeHolidays,
    required this.isActive,
    this.useTTS = true, // 기본값은 true
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'stationId': stationId,
        'stationName': stationName,
        'routeId': routeId,
        'routeNo': routeNo,
        'repeatDays': repeatDays,
        'excludeWeekends': excludeWeekends,
        'excludeHolidays': excludeHolidays,
        'isActive': isActive,
        'useTTS': useTTS,
      };

  factory AutoAlarm.fromJson(Map<String, dynamic> json) {
    return AutoAlarm(
      id: json['id'],
      hour: json['hour'],
      minute: json['minute'],
      stationId: json['stationId'],
      stationName: json['stationName'],
      routeId: json['routeId'],
      routeNo: json['routeNo'],
      repeatDays: List<int>.from(json['repeatDays']),
      excludeWeekends: json['excludeWeekends'],
      excludeHolidays: json['excludeHolidays'],
      isActive: json['isActive'],
      useTTS: json['useTTS'] ?? true,
    );
  }

  AutoAlarm copyWith({
    String? id,
    int? hour,
    int? minute,
    String? stationId,
    String? stationName,
    String? routeId,
    String? routeNo,
    List<int>? repeatDays,
    bool? excludeWeekends,
    bool? excludeHolidays,
    bool? isActive,
    bool? useTTS,
  }) {
    return AutoAlarm(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      stationId: stationId ?? this.stationId,
      stationName: stationName ?? this.stationName,
      routeId: routeId ?? this.routeId,
      routeNo: routeNo ?? this.routeNo,
      repeatDays: repeatDays ?? this.repeatDays,
      excludeWeekends: excludeWeekends ?? this.excludeWeekends,
      excludeHolidays: excludeHolidays ?? this.excludeHolidays,
      isActive: isActive ?? this.isActive,
      useTTS: useTTS ?? this.useTTS,
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final List<AutoAlarm> _autoAlarms = [];
  bool _isLoading = false;
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
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('auto_alarms') ?? [];
      _autoAlarms.clear();
      for (var json in alarms) {
        final data = jsonDecode(json);
        _autoAlarms.add(AutoAlarm.fromJson(data));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAutoAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> alarms =
          _autoAlarms.map((alarm) => jsonEncode(alarm.toJson())).toList();
      await prefs.setStringList('auto_alarms', alarms);
      if (mounted) {
        final alarmService = Provider.of<AlarmService>(context, listen: false);
        await alarmService.updateAutoAlarms(_autoAlarms);
      }
    } catch (e) {
      debugPrint('자동 알림 설정 저장 오류: $e');
    }
  }

  void _addAutoAlarm() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SearchScreen()),
    );
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
      if (alarmResult != null && alarmResult is AutoAlarm) {
        if (mounted) {
          setState(() {
            _autoAlarms.add(alarmResult);
            _saveAutoAlarms();
          });
        }
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
    if (result != null && result is AutoAlarm && mounted) {
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

  @override
  Widget build(BuildContext context) {
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
                            TextButton.icon(
                              onPressed: _addAutoAlarm,
                              icon: const Icon(Icons.add),
                              label: const Text('알림 추가'),
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.blue.shade50,
                                foregroundColor: Colors.blue.shade700,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
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
                                        ...AlarmSound.allSounds.map((sound) {
                                          final isSelected =
                                              _settingsService.alarmSoundId ==
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
                                                ? const Icon(Icons.check_circle,
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
                                        s.id == _settingsService.alarmSoundId)
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
              ],
            ),
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
    if (_selectedStation == null || _selectedRouteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정류장과 노선을 선택해주세요')),
      );
      return;
    }
    if (_repeatDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('최소 하나 이상의 요일을 선택해주세요')),
      );
      return;
    }

    final alarm = AutoAlarm(
      id: widget.autoAlarm?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      hour: _hour,
      minute: _minute,
      stationId: _selectedStation!.id,
      stationName: _selectedStation!.name,
      routeId: _selectedRouteId!,
      routeNo: _selectedRouteNo!,
      repeatDays: _repeatDays,
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
