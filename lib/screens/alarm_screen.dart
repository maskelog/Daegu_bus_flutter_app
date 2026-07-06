import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../models/bus_stop.dart';

import '../models/auto_alarm.dart';
import '../models/favorite_bus.dart';
import '../services/alarm_service.dart';
import '../services/alarm/holiday_service.dart';
import '../services/settings_service.dart';
import 'auto_alarm_edit_screen.dart';
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
  List<DateTime> _holidays = [];

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService();
    _loadAutoAlarms();
    _initSettings();
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    final now = DateTime.now();
    final svc = HolidayService();
    final thisMonth = await svc.fetchHolidays(now.year, now.month);
    final next = DateTime(now.year, now.month + 1);
    final nextMonth = await svc.fetchHolidays(next.year, next.month);
    if (mounted) {
      setState(() => _holidays = [...thisMonth, ...nextMonth]);
    }
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
      await alarmService.cancelScheduledAutoAlarm(currentAlarm.id);
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
      await alarmService.cancelScheduledAutoAlarm(alarm.id);
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
      final next = alarm.getNextAlarmTime(
        holidays: alarm.excludeHolidays ? _holidays : null,
      );
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
    // 네비 바 높이: 아이콘(24) + 간격(2) + 텍스트 + 내부 패딩(18) + 컨테이너 패딩(10)
    // 텍스트 접근성 스케일 반영
    final textScaler = MediaQuery.textScalerOf(context);
    final scaledNavLabel = textScaler.scale(12.0); // 선택된 탭 레이블 최대 크기
    final floatingNavHeight = 24.0 + 2.0 + scaledNavLabel + 18.0 + 10.0;
    const floatingNavBottom = 58.0; // bannerHeight(50) + gap(8) from home_screen
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
                                  child: const Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // 상단 Row에서 이미 제목과 추가 버튼을 제공하므로 여기서는 제거
                                      SizedBox(height: 0),
                                      SizedBox(height: 24),
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

