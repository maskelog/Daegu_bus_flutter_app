import 'package:daegu_bus_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../models/bus_stop.dart';

import '../models/auto_alarm.dart';
import '../models/favorite_bus.dart';
import '../services/alarm_service.dart';
import '../services/settings_service.dart';
import 'search_screen.dart';
import '../main.dart' show logMessage, LogLevel;
import '../utils/favorite_bus_store.dart';

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
    final favorites = await FavoriteBusStore.load();
    if (!mounted) return;

    // 이미 알람이 설정된 즐겨찾기 버스의 키 세트
    final existingAlarmKeys = _autoAlarms
        .map((a) => '${a.stationId}|${a.routeId}')
        .toSet();

    final result = await showModalBottomSheet<dynamic>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Text(
                  '알람 추가',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),

                // 즐겨찾기 섹션
                if (favorites.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.star_rounded,
                          size: 18, color: Colors.amber.shade700),
                      const SizedBox(width: 6),
                      Text(
                        '즐겨찾기 버스',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: favorites.length > 4 ? 240 : double.infinity,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: favorites.length > 4
                          ? const AlwaysScrollableScrollPhysics()
                          : const NeverScrollableScrollPhysics(),
                      itemCount: favorites.length,
                      itemBuilder: (context, index) {
                        final bus = favorites[index];
                        final alreadySet =
                            existingAlarmKeys.contains(bus.key);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Material(
                            color: alreadySet
                                ? colorScheme.surfaceContainerHighest
                                : colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: alreadySet
                                  ? null
                                  : () => Navigator.pop(context, bus),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                                child: Row(
                                  children: [
                                    // 버스 뱃지
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: alreadySet
                                            ? colorScheme.outlineVariant
                                            : colorScheme.primary,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.directions_bus,
                                            size: 16,
                                            color: alreadySet
                                                ? colorScheme
                                                    .onSurfaceVariant
                                                : colorScheme.onPrimary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            bus.routeNo,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: alreadySet
                                                  ? colorScheme
                                                      .onSurfaceVariant
                                                  : colorScheme.onPrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    // 정류장명
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            bus.stationName,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: alreadySet
                                                  ? colorScheme
                                                      .onSurfaceVariant
                                                  : colorScheme.onSurface,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (alreadySet)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: colorScheme
                                              .secondaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '설정됨',
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: colorScheme
                                                .onSecondaryContainer,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      )
                                    else
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        color:
                                            colorScheme.onSurfaceVariant,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: colorScheme.outlineVariant.withAlpha(128)),
                  const SizedBox(height: 4),
                ],

                // 검색 버튼
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context, 'search'),
                    icon: const Icon(Icons.search_rounded, size: 20),
                    label: const Text('정류장 검색으로 추가'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || result == null) return;

    BusStop? selectedStation;
    FavoriteBus? selectedFavoriteBus;

    if (result == 'search') {
      // 정류장 검색 경로
      final searchResult = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SearchScreen()),
      );
      if (!mounted || searchResult == null || searchResult is! BusStop) return;
      selectedStation = searchResult;
    } else if (result is FavoriteBus) {
      // 즐겨찾기 버스 선택 경로
      selectedFavoriteBus = result;
      selectedStation = BusStop(
        id: result.stationId,
        name: result.stationName,
        isFavorite: true,
      );
    } else {
      return;
    }

    final alarmResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AutoAlarmEditScreen(
          key: UniqueKey(),
          autoAlarm: null,
          selectedStation: selectedStation,
          selectedFavoriteBus: selectedFavoriteBus,
        ),
      ),
    );

    if (!mounted) return;

    if (alarmResult != null && alarmResult is AutoAlarm) {
      setState(() {
        _autoAlarms.add(alarmResult);
        _saveAutoAlarms();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('${alarmResult.routeNo}번 버스 알람이 추가되었습니다.'),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text('${result.routeNo}번 버스 알람이 수정되었습니다.'),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                newIsActive ? Icons.notifications_active : Icons.notifications_off,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(newIsActive
                  ? '${currentAlarm.routeNo}번 알람이 켜졌습니다.'
                  : '${currentAlarm.routeNo}번 알람이 꺼졌습니다.'),
            ],
          ),
          backgroundColor: newIsActive
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.onSurfaceVariant,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    // 인덱스로 삭제 대상을 먼저 수집 (역순 정렬로 인덱스 밀림 방지)
    final sortedIndices = _selectedAlarms.toList()..sort((a, b) => b.compareTo(a));
    final alarmsToDelete = sortedIndices
        .where((i) => i < _autoAlarms.length)
        .map((i) => _autoAlarms[i])
        .toList();

    for (var alarm in alarmsToDelete) {
      await alarmService.stopAutoAlarm(
        alarm.routeNo,
        alarm.stationName,
        alarm.routeId,
      );
    }

    setState(() {
      for (var index in sortedIndices) {
        if (index < _autoAlarms.length) {
          _autoAlarms.removeAt(index);
        }
      }
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

  /// 다음 발동 시각 미리보기 문자열
  String _getNextAlarmTimeText(AutoAlarm alarm) {
    if (!alarm.isActive) return '';
    if (alarm.repeatDays.isEmpty) return '';
    try {
      final next = alarm.getNextAlarmTime();
      if (next == null) return '';
      final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final wd = weekdays[next.weekday - 1];
      final mm = next.month.toString().padLeft(2, '0');
      final dd = next.day.toString().padLeft(2, '0');
      final hh = next.hour.toString().padLeft(2, '0');
      final mn = next.minute.toString().padLeft(2, '0');
      return '다음: $mm/$dd($wd) $hh:$mn';
    } catch (_) {
      return '';
    }
  }

  /// AlarmService가 해당 자동 알람 경로/정류장을 추적 중인지 확인
  bool _isTracking(AutoAlarm alarm, AlarmService alarmService) {
    // AlarmService에 activeAlarms getter가 없으므로 현재 항상 false 반환
    // 추후 Native 상태 노출 시 실제 구현으로 교체 예정
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const floatingNavHeight = 68.0;
    const floatingNavBottom = 24.0;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final toolbarBottom = floatingNavHeight + floatingNavBottom + bottomInset;

    return Consumer<SettingsService>(
      builder: (context, settingsService, child) {
        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: Column(
            children: [
              // 상단 설정/제목/추가 버튼
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 20, 16), // More padding
                  child: Row(
                    children: [
                      Text(
                        '버스 알람',
                        style: TextStyle(
                          fontSize: 32, // Much larger
                          fontWeight: FontWeight.w900, // Bolder
                          color: colorScheme.onSurface,
                          letterSpacing: -1.0,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton.filledTonal(
                          icon: Icon(Icons.add_rounded, color: colorScheme.onSurface, size: 28), // Larger icon
                          onPressed: _addAutoAlarm,
                          tooltip: '알람 추가',
                          style: IconButton.styleFrom(
                            backgroundColor: colorScheme.surfaceContainerHighest,
                            padding: const EdgeInsets.all(16),
                          ),
                        ),
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
                                            return Consumer<AlarmService>(
                                              builder: (context, alarmService, _) {
                                                final tracking = _isTracking(alarm, alarmService);
                                                final nextTimeText = _getNextAlarmTimeText(alarm);
                                                return Container(
                                              margin: const EdgeInsets.only(bottom: 16), // More spacing
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(32), // Very rounded
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: Colors.black.withAlpha(20),
                                                    blurRadius: 16,
                                                    offset: const Offset(0, 4),
                                                  ),
                                                ],
                                              ),
                                              child: Material(
                                                color: colorScheme.surface,
                                                borderRadius: BorderRadius.circular(32),
                                                child: InkWell(
                                                  onLongPress: () => _onLongPressAlarm(index),
                                                  onTap: _selectionMode
                                                      ? () => _toggleSelectAlarm(index)
                                                      : () => _editAutoAlarm(index),
                                                  borderRadius: BorderRadius.circular(32),
                                                  child: Padding(
                                                  padding: const EdgeInsets.all(20), // Generous padding
                                                  child: Row(
                                                    crossAxisAlignment: CrossAxisAlignment.center,
                                                    children: [
                                                      if (_selectionMode)
                                                        Padding(
                                                          padding: const EdgeInsets.only(right: 16),
                                                          child: Checkbox(
                                                            value: _selectedAlarms.contains(index),
                                                            onChanged: (_) => _toggleSelectAlarm(index),
                                                            activeColor: colorScheme.primary,
                                                          ),
                                                        ),
                                                      // 버스 번호 뱃지 — 활성/비활성 색상 구분
                                                      Container(
                                                        margin: const EdgeInsets.only(right: 16),
                                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            colors: alarm.isActive
                                                                ? [colorScheme.primary, colorScheme.primary.withAlpha(204)]
                                                                : [colorScheme.onSurfaceVariant.withAlpha(100), colorScheme.onSurfaceVariant.withAlpha(70)],
                                                            begin: Alignment.topLeft,
                                                            end: Alignment.bottomRight,
                                                          ),
                                                          borderRadius: BorderRadius.circular(20),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: (alarm.isActive && tracking ? colorScheme.primary : colorScheme.onSurfaceVariant).withAlpha(60),
                                                              blurRadius: 8,
                                                              offset: const Offset(0, 2),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.directions_bus, size: 20, color: Colors.white),
                                                            const SizedBox(width: 6),
                                                            Text(
                                                              alarm.routeNo,
                                                              style: const TextStyle(
                                                                fontSize: 18,
                                                                fontWeight: FontWeight.w900,
                                                                color: Colors.white,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                           children: [
                                                             // 정류장명 + 추적 중 뱃지
                                                             Row(
                                                               children: [
                                                                 Expanded(
                                                                   child: Text(
                                                                     alarm.stationName,
                                                                     style: TextStyle(
                                                                       fontSize: 17,
                                                                       fontWeight: FontWeight.w700,
                                                                       color: colorScheme.onSurface,
                                                                     ),
                                                                     maxLines: 1,
                                                                     overflow: TextOverflow.ellipsis,
                                                                   ),
                                                                 ),
                                                                 if (tracking) ...[  
                                                                   const SizedBox(width: 6),
                                                                   Container(
                                                                     padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                                     decoration: BoxDecoration(
                                                                       color: colorScheme.tertiary.withAlpha(30),
                                                                       borderRadius: BorderRadius.circular(20),
                                                                       border: Border.all(color: colorScheme.tertiary.withAlpha(120), width: 1),
                                                                     ),
                                                                     child: Row(
                                                                       mainAxisSize: MainAxisSize.min,
                                                                       children: [
                                                                         Icon(Icons.radio_button_checked, size: 10, color: colorScheme.tertiary),
                                                                         const SizedBox(width: 3),
                                                                         Text('추적 중', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: colorScheme.tertiary)),
                                                                       ],
                                                                     ),
                                                                   ),
                                                                 ],
                                                               ],
                                                             ),
                                                             const SizedBox(height: 6),
                                                             Row(
                                                               children: [
                                                                 Icon(Icons.alarm, size: 16, color: colorScheme.onSurfaceVariant),
                                                                 const SizedBox(width: 4),
                                                                 Text(
                                                                   '${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}',
                                                                   style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                                                                 ),
                                                                 const SizedBox(width: 12),
                                                                 Icon(Icons.repeat, size: 16, color: colorScheme.onSurfaceVariant),
                                                                 const SizedBox(width: 4),
                                                                 Flexible(
                                                                   child: Text(
                                                                     _getRepeatDaysText(alarm),
                                                                     style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                                                                     overflow: TextOverflow.ellipsis,
                                                                   ),
                                                                 ),
                                                               ],
                                                             ),
                                                             const SizedBox(height: 6),
                                                             Row(
                                                               children: [
                                                                 Icon(
                                                                   alarm.isCommuteAlarm ? Icons.volume_up_rounded : Icons.headphones_rounded,
                                                                   size: 14,
                                                                   color: alarm.isCommuteAlarm ? colorScheme.primary : colorScheme.tertiary,
                                                                 ),
                                                                 const SizedBox(width: 4),
                                                                 Text(
                                                                   alarm.isCommuteAlarm ? '출근 (스피커)' : '퇴근 (이어폰)',
                                                                   style: TextStyle(
                                                                     fontSize: 12,
                                                                     fontWeight: FontWeight.w500,
                                                                     color: alarm.isCommuteAlarm ? colorScheme.primary : colorScheme.tertiary,
                                                                   ),
                                                                 ),
                                                               ],
                                                             ),
                                                             if (alarm.excludeHolidays || alarm.excludeWeekends) ...[
                                                               const SizedBox(height: 4),
                                                               Row(
                                                                 children: [
                                                                   Icon(Icons.event_busy, size: 14, color: colorScheme.onSurfaceVariant),
                                                                   const SizedBox(width: 4),
                                                                   Text(_getExcludeText(alarm), style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                                                                 ],
                                                               ),
                                                             ],
                                                             // 다음 발동 시각
                                                             if (nextTimeText.isNotEmpty) ...[
                                                               const SizedBox(height: 6),
                                                               Row(
                                                                 children: [
                                                                   Icon(Icons.schedule_rounded, size: 13, color: colorScheme.primary.withAlpha(180)),
                                                                   const SizedBox(width: 4),
                                                                   Text(
                                                                     nextTimeText,
                                                                     style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.primary.withAlpha(180)),
                                                                   ),
                                                                 ],
                                                               ),
                                                             ],
                                                           ],
                                                        ),
                                                      ),
                                                      Switch(
                                                        value: alarm.isActive,
                                                        onChanged: (_) => _toggleAutoAlarm(index),
                                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                 ),
                                               ),
                                             );
                                              },
                                            );
                                           },
                                           childCount: _autoAlarms.length,
                                        ),
                                      ),
                              ),
                              SliverToBoxAdapter(
                                child: SizedBox(height: toolbarBottom + 16), // Bottom padding for floating toolbar
                              ),
                            ],
                          ),
                          if (_selectionMode && _selectedAlarms.isNotEmpty)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: toolbarBottom,
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
  final FavoriteBus? selectedFavoriteBus;

  const AutoAlarmEditScreen({
    super.key,
    this.autoAlarm,
    this.selectedStation,
    this.selectedFavoriteBus,
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
  bool _isCommuteAlarm = true;

  BusStop? _selectedStation;
  String? _selectedRouteId;
  String? _selectedRouteNo;

  bool _isLoadingRoutes = false;
  List<Map<String, String>> _routeOptions = [];

  final List<String> _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  /// 즐겨찾기에서 진입한 경우 (노선이 이미 결정됨)
  bool get _isFromFavorite => widget.selectedFavoriteBus != null;

  @override
  void initState() {
    super.initState();

    if (widget.autoAlarm != null) {
      final alarm = widget.autoAlarm!;
      _hour = alarm.hour;
      _minute = alarm.minute;
      _repeatDays = List.from(alarm.repeatDays);
      _excludeWeekends = alarm.excludeWeekends;
      _excludeHolidays = alarm.excludeHolidays;
      _useTTS = alarm.useTTS;
      _isCommuteAlarm = alarm.isCommuteAlarm;
      _selectedStation = BusStop(
          id: alarm.stationId, name: alarm.stationName, isFavorite: false);
      _selectedRouteId = alarm.routeId;
      _selectedRouteNo = alarm.routeNo;
      _loadRouteOptions();
    } else {
      final now = DateTime.now();
      _hour = now.hour;
      _minute = now.minute;
      _repeatDays = [1, 2, 3, 4, 5];
      if (widget.selectedFavoriteBus != null) {
        final favorite = widget.selectedFavoriteBus!;
        _selectedStation = BusStop(
          id: favorite.stationId,
          name: favorite.stationName,
          isFavorite: true,
        );
        _selectedRouteId = favorite.routeId;
        _selectedRouteNo = favorite.routeNo;
        _routeOptions = [
          {'id': favorite.routeId, 'routeNo': favorite.routeNo},
        ];
        _loadRouteOptions();
      } else if (widget.selectedStation != null) {
        _selectedStation = widget.selectedStation;
        _loadRouteOptions();
      }
    }
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
          if (_routeOptions.isNotEmpty) {
            final hasSelected = _selectedRouteId != null &&
                _routeOptions.any((route) => route['id'] == _selectedRouteId);
            if (!hasSelected) {
              final first = _routeOptions.first;
              _selectedRouteId = first['id'];
              _selectedRouteNo = first['routeNo'];
            }
          }
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
    });
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
      isCommuteAlarm: _isCommuteAlarm,
      isActive: true,
    );

    Navigator.pop(context, alarm);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _hour, minute: _minute),
    );
    if (picked != null && mounted) {
      setState(() {
        _hour = picked.hour;
        _minute = picked.minute;
      });
    }
  }

  void _setPresetDays(List<int> days) {
    setState(() => _repeatDays = days);
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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saveAlarm,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: const Text('저장'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1) 버스 정보 카드
            if (_selectedStation != null) _buildBusInfoCard(colorScheme),
            const SizedBox(height: 24),

            // 2) 시간 표시 (큰 폰트, 중앙)
            _buildTimeDisplay(colorScheme),
            const SizedBox(height: 32),

            // 3) 요일 선택 (원형 토글)
            _buildDaySelector(theme, colorScheme),
            const SizedBox(height: 28),

            // 4) 추가 설정 카드
            _buildSettingsCard(theme, colorScheme),
            const SizedBox(height: 28),

            // 5) 알람 유형 선택 (출근/퇴근)
            _buildAlarmTypeSelector(colorScheme),
            const SizedBox(height: 28),

            // 6) 노선 선택 (검색 진입 시만)
            if (!_isFromFavorite && widget.autoAlarm == null)
              _buildRouteSelector(theme, colorScheme),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  /// 버스 정보 카드 — 버스 뱃지 + 정류장명
  Widget _buildBusInfoCard(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // 버스 뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.directions_bus, size: 18, color: colorScheme.onPrimary),
                const SizedBox(width: 4),
                Text(
                  _selectedRouteNo ?? '?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 정류장명
          Expanded(
            child: Text(
              _selectedStation!.name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colorScheme.onPrimaryContainer,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmTypeSelector(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '알람 유형',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment<bool>(
              value: true,
              icon: Icon(Icons.volume_up_rounded),
              label: Text('출근 (스피커)'),
            ),
            ButtonSegment<bool>(
              value: false,
              icon: Icon(Icons.headphones_rounded),
              label: Text('퇴근 (이어폰)'),
            ),
          ],
          selected: {_isCommuteAlarm},
          onSelectionChanged: (selected) {
            setState(() => _isCommuteAlarm = selected.first);
          },
        ),
        const SizedBox(height: 4),
        Text(
          _isCommuteAlarm
              ? '이어폰 연결 여부와 관계없이 스피커로 알림'
              : '이어폰 연결 시 TTS 알림, 미연결 시 진동',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// 시간 표시 — 큰 폰트 중앙 배치, 탭하면 TimePicker
  Widget _buildTimeDisplay(ColorScheme colorScheme) {
    final hourStr = _hour.toString().padLeft(2, '0');
    final minuteStr = _minute.toString().padLeft(2, '0');

    return Center(
      child: InkWell(
        onTap: _pickTime,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    hourStr,
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                      letterSpacing: 2,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      ':',
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.w400,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    minuteStr,
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '탭해서 변경',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 요일 선택 — 원형 토글 + 프리셋 칩
  Widget _buildDaySelector(ThemeData theme, ColorScheme colorScheme) {
    // 현재 프리셋 상태 확인
    final isWeekdays = _repeatDays.length == 5 &&
        _repeatDays.every((d) => [1, 2, 3, 4, 5].contains(d));
    final isWeekend = _repeatDays.length == 2 &&
        _repeatDays.every((d) => [6, 7].contains(d));
    final isEveryDay = _repeatDays.length == 7;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '반복 요일',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        // 원형 토글 버튼
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(7, (index) {
            final dayNum = index + 1;
            final isSelected = _repeatDays.contains(dayNum);
            final isWeekendDay = dayNum == 6 || dayNum == 7;

            return GestureDetector(
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _repeatDays.remove(dayNum);
                  } else {
                    _repeatDays.add(dayNum);
                    _repeatDays.sort();
                  }
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest,
                ),
                alignment: Alignment.center,
                child: Text(
                  _weekdays[index],
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isSelected
                        ? colorScheme.onPrimary
                        : isWeekendDay
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 12),
        // 프리셋 칩
        Row(
          children: [
            _buildPresetChip('평일', isWeekdays, () => _setPresetDays([1, 2, 3, 4, 5]), colorScheme),
            const SizedBox(width: 8),
            _buildPresetChip('주말', isWeekend, () => _setPresetDays([6, 7]), colorScheme),
            const SizedBox(width: 8),
            _buildPresetChip('매일', isEveryDay, () => _setPresetDays([1, 2, 3, 4, 5, 6, 7]), colorScheme),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetChip(String label, bool isActive, VoidCallback onTap, ColorScheme colorScheme) {
    return ActionChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
          color: isActive ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
        ),
      ),
      onPressed: onTap,
      backgroundColor: isActive ? colorScheme.secondaryContainer : null,
      side: BorderSide(
        color: isActive ? colorScheme.secondary : colorScheme.outlineVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  /// 추가 설정 카드 — 공휴일 제외 + 음성 알림
  Widget _buildSettingsCard(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '추가 설정',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              // 공휴일 제외
              SwitchListTile(
                secondary: Icon(
                  Icons.event_busy_rounded,
                  color: _excludeHolidays
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                title: Text(
                  '공휴일 제외',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                value: _excludeHolidays,
                onChanged: (value) => setState(() => _excludeHolidays = value),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Divider(
                height: 1,
                indent: 56,
                color: colorScheme.outlineVariant.withAlpha(128),
              ),
              // 음성 알림
              SwitchListTile(
                secondary: Icon(
                  Icons.volume_up_rounded,
                  color: _useTTS
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                title: Text(
                  '음성 알림',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                subtitle: _useTTS
                    ? Text(
                        '버스 도착 정보를 음성으로 안내',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : null,
                value: _useTTS,
                onChanged: (value) => setState(() => _useTTS = value),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 노선 선택 — 검색에서 진입한 경우만 표시
  Widget _buildRouteSelector(ThemeData theme, ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '노선 선택',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        if (_isLoadingRoutes)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_routeOptions.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _routeOptions.map((route) {
              final isSelected = _selectedRouteId == route['id'];
              return ChoiceChip(
                label: Text(
                  route['routeNo']!,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.onPrimaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                selected: isSelected,
                onSelected: (_) => _selectRoute(route['id']!, route['routeNo']!),
                selectedColor: colorScheme.primaryContainer,
                backgroundColor: colorScheme.surfaceContainerLow,
                side: BorderSide(
                  color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              );
            }).toList(),
          )
        else
          Text(
            '노선 정보를 불러오는 중...',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
