import 'package:daegu_bus_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../models/bus_stop.dart';

import '../models/auto_alarm.dart';
import '../services/alarm_service.dart';
import '../services/settings_service.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../main.dart' show logMessage, LogLevel;

class AlarmScreen extends StatefulWidget {
  const AlarmScreen({super.key});

  @override
  State<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends State<AlarmScreen> {
  final List<AutoAlarm> _autoAlarms = [];
  final bool _isLoading = false;
  final List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  late SettingsService _settingsService;
  final Set<int> _selectedAlarms = {}; // 선택된 알람 인덱스
  bool _selectionMode = false; // 선택 모드 상태

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
        logMessage('📝 알람 데이터 변환: ${alarm.routeNo}번 버스');
        logMessage('  - ID: ${alarm.id}');
        logMessage('  - 시간: ${alarm.hour}:${alarm.minute}');
        logMessage('  - 정류장: ${alarm.stationName} (${alarm.stationId})');
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

    if (!mounted) return;

    if (result != null && result is AutoAlarm) {
      setState(() {
        _autoAlarms[index] = result;
        _saveAutoAlarms();
      });
    }
  }

  void _toggleAutoAlarm(int index) async {
    // async 추가
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final currentAlarm = _autoAlarms[index];
    final newIsActive = !currentAlarm.isActive;

    setState(() {
      _autoAlarms[index] = currentAlarm.copyWith(
        isActive: newIsActive,
      );
    });

    if (!newIsActive) {
      // 알람이 비활성화될 때만 네이티브 중지 요청
      await alarmService.stopAutoAlarm(
        currentAlarm.routeNo,
        currentAlarm.stationName,
        currentAlarm.routeId,
      );
    }
    _saveAutoAlarms(); // 상태 저장
  }

  void _toggleSelectAlarm(int index) {
    setState(() {
      if (_selectedAlarms.contains(index)) {
        _selectedAlarms.remove(index);
        if (_selectedAlarms.isEmpty) _selectionMode = false;
      } else {
        _selectedAlarms.add(index);
      }
    });
  }

  void _clearSelectedAlarms() {
    setState(() {
      _selectedAlarms.clear();
      _selectionMode = false;
    });
  }

  void _onLongPressAlarm(int index) {
    setState(() {
      _selectionMode = true;
      _selectedAlarms.add(index);
    });
  }

  void _activateSelectedAlarms() {
    setState(() {
      for (var idx in _selectedAlarms) {
        _autoAlarms[idx] = _autoAlarms[idx].copyWith(isActive: true);
      }
      _saveAutoAlarms();
      _selectedAlarms.clear();
      _selectionMode = false;
    });
  }

  void _deleteSelectedAlarms() async {
    // async 추가
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final alarmsToDelete = _autoAlarms
        .where((alarm) => _selectedAlarms.contains(_autoAlarms.indexOf(alarm)))
        .toList();

    for (var alarm in alarmsToDelete) {
      await alarmService.stopAutoAlarm(
        alarm.routeNo,
        alarm.stationName,
        alarm.routeId,
      );
    }

    setState(() {
      _autoAlarms.removeWhere(
          (alarm) => _selectedAlarms.contains(_autoAlarms.indexOf(alarm)));
      _saveAutoAlarms();
      _selectedAlarms.clear();
      _selectionMode = false;
    });
  }

  String _getRepeatDaysText(AutoAlarm alarm) {
    if (alarm.repeatDays.isEmpty) return '반복 안함';
    if (alarm.repeatDays.length == 7) return '매일';
    if (alarm.repeatDays.length == 5 &&
        alarm.repeatDays.every((day) => [1, 2, 3, 4, 5].contains(day))) {
      return '평일 (월-금)';
    }
    if (alarm.repeatDays.length == 2 &&
        alarm.repeatDays.every((day) => [6, 7].contains(day))) {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Consumer<SettingsService>(
      builder: (context, settingsService, child) {
        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: Column(
            children: [
              // 상단 설정/제목/추가 버튼
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Text(
                        '버스 알람',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.add, color: colorScheme.primary),
                        onPressed: _addAutoAlarm,
                        tooltip: '알람 추가',
                      ),
                      IconButton.filledTonal(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const SettingsScreen()),
                          );
                        },
                        icon: Icon(Icons.settings_outlined,
                            color: colorScheme.onSurface),
                        tooltip: '설정',
                      ),
                    ],
                  ),
                ),
              ),
              // 메인 콘텐츠
              Expanded(
                child: _isLoading
                    ? Center(
                        child: CircularProgressIndicator(
                            color: colorScheme.primary))
                    : Stack(
                        children: [
                          CustomScrollView(
                            slivers: [
                              SliverToBoxAdapter(
                                child: Container(
                                  padding: const EdgeInsets.all(24),
                                  color: colorScheme.surface,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 상단 Row에서 이미 제목과 추가 버튼을 제공하므로 여기서는 제거
                                      const SizedBox(height: 0),
                                      // 자동 알람 볼륨 설정 추가
                                      Consumer<SettingsService>(
                                        builder:
                                            (context, settingsService, child) {
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '알람 볼륨',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  color: colorScheme.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(Icons.volume_down,
                                                      color: colorScheme
                                                          .onSurfaceVariant),
                                                  Expanded(
                                                    child: Slider(
                                                      value: settingsService
                                                          .autoAlarmVolume,
                                                      min: SettingsService
                                                          .minAutoAlarmVolume,
                                                      max: SettingsService
                                                          .maxAutoAlarmVolume,
                                                      divisions: 10,
                                                      label:
                                                          '${(settingsService.autoAlarmVolume * 100).round()}%',
                                                      onChanged: (value) {
                                                        settingsService
                                                            .updateAutoAlarmVolume(
                                                                value);
                                                      },
                                                    ),
                                                  ),
                                                  Icon(Icons.volume_up,
                                                      color: colorScheme
                                                          .onSurfaceVariant),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                            ],
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 24),
                                    ],
                                  ),
                                ),
                              ),
                              SliverPadding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                sliver: _autoAlarms.isEmpty
                                    ? SliverToBoxAdapter(
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.notifications_off,
                                                size: 64,
                                                color: colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                '설정된 자동 알림이 없습니다',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: colorScheme.onSurface,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '상단의 "알림 추가" 버튼을 눌러 새 자동 알림을 추가하세요',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: colorScheme
                                                      .onSurfaceVariant,
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
                                            return GestureDetector(
                                              onLongPress: () =>
                                                  _onLongPressAlarm(index),
                                              onTap: _selectionMode
                                                  ? () =>
                                                      _toggleSelectAlarm(index)
                                                  : () => _editAutoAlarm(index),
                                              child: Card(
                                                margin: const EdgeInsets.only(
                                                    bottom: 8),
                                                color: colorScheme.surface,
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      if (_selectionMode)
                                                        Checkbox(
                                                          value: _selectedAlarms
                                                              .contains(index),
                                                          onChanged: (_) =>
                                                              _toggleSelectAlarm(
                                                                  index),
                                                          activeColor:
                                                              colorScheme
                                                                  .primary,
                                                        ),
                                                      Container(
                                                        margin: const EdgeInsets
                                                            .only(right: 12),
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 4),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: colorScheme
                                                              .primaryContainer,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Icon(
                                                                Icons
                                                                    .directions_bus,
                                                                size: 18,
                                                                color: colorScheme
                                                                    .primary),
                                                            const SizedBox(
                                                                width: 4),
                                                            Text(
                                                              alarm.routeNo,
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color:
                                                                    colorScheme
                                                                        .primary,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment:
                                                              CrossAxisAlignment
                                                                  .start,
                                                          children: [
                                                            Text(
                                                              alarm.stationName,
                                                              style: TextStyle(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                color: colorScheme
                                                                    .onSurface,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                height: 2),
                                                            Row(
                                                              children: [
                                                                Icon(
                                                                    Icons.alarm,
                                                                    size: 14,
                                                                    color: colorScheme
                                                                        .onSurfaceVariant),
                                                                const SizedBox(
                                                                    width: 2),
                                                                Text(
                                                                  '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          13,
                                                                      color: colorScheme
                                                                          .onSurfaceVariant),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Icon(
                                                                    Icons
                                                                        .repeat,
                                                                    size: 14,
                                                                    color: colorScheme
                                                                        .onSurfaceVariant),
                                                                const SizedBox(
                                                                    width: 2),
                                                                Text(
                                                                    _getRepeatDaysText(
                                                                        alarm),
                                                                    style: TextStyle(
                                                                        fontSize:
                                                                            12,
                                                                        color: colorScheme
                                                                            .onSurfaceVariant)),
                                                                if (alarm
                                                                        .excludeHolidays ||
                                                                    alarm
                                                                        .excludeWeekends) ...[
                                                                  const SizedBox(
                                                                      width: 8),
                                                                  Icon(
                                                                      Icons
                                                                          .event_busy,
                                                                      size: 14,
                                                                      color: colorScheme
                                                                          .onSurfaceVariant),
                                                                  const SizedBox(
                                                                      width: 2),
                                                                  Text(
                                                                      _getExcludeText(
                                                                          alarm),
                                                                      style: TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                          color:
                                                                              colorScheme.onSurfaceVariant)),
                                                                ],
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Switch(
                                                        value: alarm.isActive,
                                                        onChanged: (_) =>
                                                            _toggleAutoAlarm(
                                                                index),
                                                        materialTapTargetSize:
                                                            MaterialTapTargetSize
                                                                .shrinkWrap,
                                                      ),
                                                    ],
                                                  ),
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
                          if (_selectionMode && _selectedAlarms.isNotEmpty)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                color: colorScheme.surface,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 16),
                                child: Row(
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: _activateSelectedAlarms,
                                      icon: const Icon(
                                          Icons.notifications_active),
                                      label: const Text('알람 켜기'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colorScheme.primary,
                                        foregroundColor: colorScheme.onPrimary,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    ElevatedButton.icon(
                                      onPressed: _deleteSelectedAlarms,
                                      icon: const Icon(Icons.delete),
                                      label: const Text('삭제'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: colorScheme.error,
                                        foregroundColor: colorScheme.onError,
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: _clearSelectedAlarms,
                                      child: Text('선택 해제',
                                          style: TextStyle(
                                              color: colorScheme.primary)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
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
      // 분 값을 5분 단위로 조정
      _minute = (alarm.minute ~/ 5) * 5;
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
      _loadRouteOptions();
    } else {
      final now = DateTime.now();
      _hour = now.hour;
      // 현재 분을 5분 단위로 조정
      _minute = (now.minute ~/ 5) * 5;
      _repeatDays = [1, 2, 3, 4, 5];
      if (widget.selectedStation != null) {
        _selectedStation = widget.selectedStation;
        _stationController.text = _selectedStation!.name;
        _loadRouteOptions();
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
      final arrivals = await ApiService.getStationInfo(stationId);

      final uniqueRoutes = <String, Map<String, String>>{};
      for (var arrival in arrivals) {
        uniqueRoutes[arrival.routeNo] = {
          'id': arrival.routeId.isEmpty ? arrival.routeNo : arrival.routeId,
          'routeNo': arrival.routeNo,
        };
      }

      if (mounted) {
        setState(() {
          _routeOptions = uniqueRoutes.values.toList();
          _isLoadingRoutes = false;
        });
      }
    } catch (e) {
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$routeNo 노선이 선택되었습니다'),
        duration: const Duration(seconds: 1),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
    );
  }

  void _saveAlarm() {
    if (_selectedStation == null || _selectedRouteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정류장과 노선을 모두 선택해주세요')),
      );
      return;
    }

    if (_repeatDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('반복 요일을 하나 이상 선택해주세요')),
      );
      return;
    }

    final alarm = AutoAlarm(
      id: widget.autoAlarm?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      routeNo: _selectedRouteNo!,
      stationName: _selectedStation!.name,
      stationId: _selectedStation!.id,
      routeId: _selectedRouteId!,
      hour: _hour,
      minute: _minute,
      repeatDays: _repeatDays,
      excludeWeekends: _excludeWeekends,
      excludeHolidays: _excludeHolidays,
      useTTS: _useTTS,
      isActive: true,
    );

    Navigator.pop(context, alarm);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          widget.autoAlarm == null ? '자동 알림 추가' : '자동 알림 편집',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saveAlarm,
            child: Text('저장', style: TextStyle(color: colorScheme.primary)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('알림 시간',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                      color: colorScheme.surfaceContainerLowest,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _hour,
                        items: List.generate(24, (index) {
                          return DropdownMenuItem(
                            value: index,
                            child: Text('${index.toString().padLeft(2, '0')}시',
                                style: TextStyle(color: colorScheme.onSurface)),
                          );
                        }),
                        onChanged: (value) =>
                            setState(() => _hour = value ?? _hour),
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        dropdownColor: colorScheme.surfaceContainer,
                        iconEnabledColor: colorScheme.onSurfaceVariant,
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                      color: colorScheme.surfaceContainerLowest,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _minute,
                        items: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
                            .map((minute) {
                          return DropdownMenuItem(
                            value: minute,
                            child: Text('${minute.toString().padLeft(2, '0')}분',
                                style: TextStyle(color: colorScheme.onSurface)),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setState(() => _minute = value ?? _minute),
                        isExpanded: true,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        dropdownColor: colorScheme.surfaceContainer,
                        iconEnabledColor: colorScheme.onSurfaceVariant,
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('반복 요일',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(7, (index) {
                final isSelected = _repeatDays.contains(index + 1);
                return FilterChip(
                  label: Text(
                    _weekdays[index],
                    style: TextStyle(
                      color: isSelected
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onSurfaceVariant,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _repeatDays.add(index + 1);
                      } else {
                        _repeatDays.remove(index + 1);
                      }
                    });
                  },
                  backgroundColor: colorScheme.surface,
                  selectedColor: colorScheme.secondaryContainer,
                  checkmarkColor: colorScheme.onSecondaryContainer,
                  side: BorderSide(
                    color: isSelected
                        ? colorScheme.secondary
                        : colorScheme.outline,
                    width: isSelected ? 2 : 1,
                  ),
                  elevation: isSelected ? 2 : 0,
                  shadowColor: colorScheme.shadow,
                  surfaceTintColor: colorScheme.surfaceTint,
                  showCheckmark: true,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.comfortable,
                );
              }),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => _repeatDays = [1, 2, 3, 4, 5]),
                  child:
                      Text('평일', style: TextStyle(color: colorScheme.primary)),
                ),
                TextButton(
                  onPressed: () => setState(() => _repeatDays = [6, 7]),
                  child:
                      Text('주말', style: TextStyle(color: colorScheme.primary)),
                ),
                TextButton(
                  onPressed: () =>
                      setState(() => _repeatDays = [1, 2, 3, 4, 5, 6, 7]),
                  child:
                      Text('매일', style: TextStyle(color: colorScheme.primary)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('제외 설정',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            CheckboxListTile(
              title:
                  Text('주말 제외', style: TextStyle(color: colorScheme.onSurface)),
              value: _excludeWeekends,
              onChanged: (value) =>
                  setState(() => _excludeWeekends = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: colorScheme.primary,
              checkColor: colorScheme.onPrimary,
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return colorScheme.primary;
                }
                return colorScheme.outline;
              }),
            ),
            CheckboxListTile(
              title: Text('공휴일 제외',
                  style: TextStyle(color: colorScheme.onSurface)),
              value: _excludeHolidays,
              onChanged: (value) =>
                  setState(() => _excludeHolidays = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: colorScheme.primary,
              checkColor: colorScheme.onPrimary,
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return colorScheme.primary;
                }
                return colorScheme.outline;
              }),
            ),
            const SizedBox(height: 24),
            Text('정류장',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: _stationController,
              readOnly: true,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'SearchScreen에서 정류장을 선택하세요',
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerLowest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),
            Text('노선',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            TextField(
              controller: _routeController,
              readOnly: true,
              enabled: false,
              style: TextStyle(
                color: _selectedRouteId != null
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
              decoration: InputDecoration(
                hintText: '아래 노선 목록에서 선택하세요',
                hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: _selectedRouteId != null
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: _selectedRouteId != null
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                ),
                filled: true,
                fillColor: _selectedRouteId != null
                    ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                    : colorScheme.surfaceContainerLowest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
            if (_isLoadingRoutes)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(color: colorScheme.primary),
                ),
              ),
            if (!_isLoadingRoutes && _routeOptions.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text('노선 목록',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.primary,
                      )),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                      color: colorScheme.surfaceContainerLowest,
                    ),
                    height: _routeOptions.length > 4 ? 200 : null,
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: _routeOptions.length > 4
                          ? const AlwaysScrollableScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: _routeOptions.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: colorScheme.outlineVariant),
                      itemBuilder: (context, index) {
                        final route = _routeOptions[index];
                        final isSelected = _selectedRouteId == route['id'];
                        return ListTile(
                          title: Text(route['routeNo']!,
                              style: TextStyle(
                                color: isSelected
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurface,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              )),
                          selected: isSelected,
                          selectedTileColor: colorScheme.primaryContainer,
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          onTap: () =>
                              _selectRoute(route['id']!, route['routeNo']!),
                        );
                      },
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
            Text('알림 설정',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface)),
            const SizedBox(height: 8),
            Text(
              '버스 도착 정보를 알림과 음성으로 알려드립니다',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.surfaceContainerLowest,
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.volume_up,
                      color: _useTTS
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: Text('음성 알림',
                        style: TextStyle(color: colorScheme.onSurface)),
                    subtitle: Text(
                      '버스 도착 정보를 음성으로 알려드립니다',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Switch(
                      value: _useTTS,
                      onChanged: (value) => setState(() => _useTTS = value),
                      activeColor: colorScheme.primary,
                      activeTrackColor: colorScheme.primaryContainer,
                      inactiveThumbColor: colorScheme.outline,
                      inactiveTrackColor: colorScheme.surfaceContainerHighest,
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
                          color: colorScheme.onSurfaceVariant,
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
