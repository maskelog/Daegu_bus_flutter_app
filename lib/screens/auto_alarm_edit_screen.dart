import 'package:daegu_bus_app/services/api_service.dart';
import 'package:flutter/material.dart';

import '../models/auto_alarm.dart';
import '../models/bus_stop.dart';
import '../models/favorite_bus.dart';

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
      stationId: _selectedStation!.getEffectiveStationId(),
      routeId: _selectedRouteId!,
      hour: _hour,
      minute: _minute,
      repeatDays: _repeatDays,
      excludeWeekends: _excludeWeekends,
      excludeHolidays: _excludeHolidays,
      useTTS: _useTTS,
      isCommuteAlarm: _isCommuteAlarm,
      isActive: widget.autoAlarm?.isActive ?? true,
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
