import 'dart:async';

import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/widgets/bus_card.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;

import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../widgets/compact_bus_card.dart';
import '../widgets/station_item.dart';

class FavoritesScreen extends StatefulWidget {
  final List<BusStop> favoriteStops;
  final Function(BusStop) onStopSelected;
  final Function(BusStop) onFavoriteToggle;

  const FavoritesScreen({
    super.key,
    required this.favoriteStops,
    required this.onStopSelected,
    required this.onFavoriteToggle,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final Map<String, List<BusArrival>> _stationArrivals = {};
  final Map<String, bool> _isLoadingMap = {};
  final Map<String, String?> _errorMap = {};
  BusStop? _selectedStop;
  dynamic _refreshTimer;
  final Map<String, bool> _stationTrackingStatus = {};

  static const _stationTrackingChannel =
      MethodChannel('com.example.daegu_bus_app/station_tracking');

  @override
  void initState() {
    super.initState();
    if (widget.favoriteStops.isNotEmpty) {
      _loadAllFavoriteArrivals();
    }
    _refreshTimer = Future.delayed(const Duration(minutes: 1), () {
      if (mounted) {
        if (_selectedStop != null) {
          _loadStationArrivals(_selectedStop!);
        } else if (widget.favoriteStops.isNotEmpty) {
          _loadAllFavoriteArrivals();
        }
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    // 화면 종료 시 모든 추적 중지 (선택적) <-- 이 라인을 제거합니다.
    // _stopAllStationTracking();
    super.dispose();
  }

  /// 즐겨찾는 모든 정류장의 도착 정보 불러오기
  Future<void> _loadAllFavoriteArrivals() async {
    for (final station in widget.favoriteStops) {
      await _loadStationArrivals(station);
    }
  }

  Future<void> _loadStationArrivals(BusStop station) async {
    setState(() {
      _isLoadingMap[station.id] = true;
      _errorMap[station.id] = null;
    });

    try {
      final arrivals = await ApiService.getStationInfo(station.id);
      if (!mounted) return;

      setState(() {
        _stationArrivals[station.id] = arrivals;
        _isLoadingMap[station.id] = false;
      });
      _updateAlarmServiceCache(arrivals, station.name);
    } catch (e) {
      logMessage('Error loading arrivals for station ${station.id}: $e',
          level: LogLevel.error);
      if (!mounted) return;

      setState(() {
        _errorMap[station.id] = '도착 정보를 불러오지 못했습니다';
        _isLoadingMap[station.id] = false;
      });
    }
  }

  void _updateAlarmServiceCache(
      List<BusArrival> busArrivals, String stationName) {
    if (busArrivals.isEmpty || !mounted) return;

    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final Set<String> updatedBuses = {};

    for (var busArrival in busArrivals) {
      if (busArrival.buses.isNotEmpty) {
        final firstBus = busArrival.buses.first;
        final remainingTime = firstBus.getRemainingMinutes();
        final busKey = "${busArrival.routeNo}:${busArrival.routeId}";
        if (updatedBuses.contains(busKey)) continue;
        updatedBuses.add(busKey);

        alarmService.updateBusInfoCache(
          busArrival.routeNo,
          busArrival.routeId,
          firstBus,
          remainingTime,
        );
        logMessage(
            '즐겨찾기 화면에서 캐시 업데이트: ${busArrival.routeNo}, 남은 시간: $remainingTime분',
            level: LogLevel.debug);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.favoriteStops.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_border, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              '즐겨찾는 정류장이 없습니다',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              '정류장 검색 후 별표 아이콘을 눌러 추가하세요',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.favoriteStops.length,
      itemBuilder: (context, index) {
        final station = widget.favoriteStops[index];
        final isSelected = _selectedStop?.id == station.id;
        final stationArrivals = _stationArrivals[station.id] ?? [];
        final isLoading = _isLoadingMap[station.id] ?? false;
        final error = _errorMap[station.id];
        final isTracking = _stationTrackingStatus[station.id] ?? false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StationItem(
              station: station,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  if (_selectedStop?.id == station.id) {
                    _selectedStop = null;
                  } else {
                    _selectedStop = station;
                    if (stationArrivals.isEmpty && !isLoading) {
                      _loadStationArrivals(station);
                    }
                  }
                });
                widget.onStopSelected(station);
              },
              onFavoriteToggle: () => widget.onFavoriteToggle(station),
            ),
            // --- 정류장 추적 버튼을 StationItem 외부에 추가 --- (임시 방편)
            // 이상적으로는 StationItem 위젯 자체를 수정하는 것이 좋음
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    isTracking
                        ? Icons.notifications_active
                        : Icons.notifications_none_outlined,
                    color: isTracking
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  tooltip:
                      isTracking ? '정류장 전체 도착 정보 추적 중지' : '정류장 전체 도착 정보 추적 시작',
                  onPressed: () {
                    if (isTracking) {
                      _stopStationTracking(station);
                    } else {
                      _startStationTracking(station);
                    }
                  },
                ),
              ],
            ),
            // --- 버튼 추가 끝 ---
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8, bottom: 16),
                child: SizedBox(
                  height: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (error != null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Icon(Icons.error_outline,
                                    size: 32, color: Colors.red[300]),
                                const SizedBox(height: 8),
                                Text(error,
                                    style: TextStyle(color: Colors.red[700])),
                                TextButton(
                                  onPressed: () =>
                                      _loadStationArrivals(station),
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (stationArrivals.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('도착 예정 버스가 없습니다'),
                          ),
                        )
                      else
                        Expanded(
                          child: Scrollbar(
                            thickness: 6.0,
                            radius: const Radius.circular(10),
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: stationArrivals.length,
                              itemBuilder: (context, idx) {
                                final busArrival = stationArrivals[idx];
                                return CompactBusCard(
                                  busArrival: busArrival,
                                  stationName: station.name,
                                  onTap: () => _showBusDetailModal(
                                      context, station, busArrival),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (index < widget.favoriteStops.length - 1)
              const Divider(height: 24),
          ],
        );
      },
    );
  }

  void _showFavoriteAlarmModal(
      BuildContext context, BusStop station, BusArrival busArrival) {
    int selectedAlarmTime = 3;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '알람 설정',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            int remainingTime = 0;
                            if (busArrival.buses.isNotEmpty) {
                              remainingTime =
                                  busArrival.buses.first.getRemainingMinutes();
                            }
                            if (remainingTime > selectedAlarmTime) {
                              final alarmService = Provider.of<AlarmService>(
                                  context,
                                  listen: false);
                              bool success = await alarmService.setOneTimeAlarm(
                                busArrival.routeNo,
                                station.name,
                                remainingTime,
                                routeId: busArrival.routeId,
                                useTTS: true,
                              );
                              if (!mounted) return;

                              // 알람 설정 결과 로그
                              logMessage(
                                  '${busArrival.routeNo}번 도착 알림 설정 ${success ? '성공' : '실패'}',
                                  level:
                                      success ? LogLevel.info : LogLevel.error);

                              if (mounted) {
                                if (success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${busArrival.routeNo}번 도착 알림이 설정되었습니다'),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${busArrival.routeNo}번 도착 알림 설정에 실패했습니다'),
                                      backgroundColor: Colors.red[700],
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }

                                // 모달 닫기
                                Navigator.pop(context);
                              }
                            }
                          },
                          child: const Text('확인'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showBusDetailModal(
      BuildContext context, BusStop station, BusArrival busArrival) {
    final alarmService = Provider.of<AlarmService>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final bool hasActiveAlarm = alarmService.hasAlarm(
                busArrival.routeNo, station.name, busArrival.routeId);

            return DraggableScrollableSheet(
              initialChildSize: 0.5, // 처음에는 50%만 표시
              minChildSize: 0.5,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // 드래그 핸들
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        height: 4,
                        width: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // 헤더 정보
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${busArrival.routeNo}번 버스',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${station.name} → ${busArrival.destination}',
                                  style: TextStyle(
                                      fontSize: 14, color: Colors.grey[800]),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          children: [
                            // 첫 번째 버스 카드
                            BusCard(
                              busArrival: BusArrival(
                                routeNo: busArrival.routeNo,
                                destination: busArrival.destination,
                                routeId: busArrival.routeId,
                                buses: busArrival.buses.isNotEmpty
                                    ? [busArrival.buses.first]
                                    : [],
                                stationId: '',
                              ),
                              onTap: () {},
                              stationName: station.name,
                              stationId: station.id,
                            ),

                            // 다음 버스 정보 안내 (다음 버스가 있는 경우만)
                            if (busArrival.buses.length > 1) ...[
                              const SizedBox(height: 12),
                              // Center(
                              //   child: Container(
                              //     margin: const EdgeInsets.only(bottom: 8),
                              //     padding: const EdgeInsets.symmetric(
                              //         horizontal: 12, vertical: 6),
                              //     decoration: BoxDecoration(
                              //       color: Colors.blue[50],
                              //       borderRadius: BorderRadius.circular(12),
                              //     ),
                              //     child: Row(
                              //       mainAxisSize: MainAxisSize.min,
                              //       children: [
                              //         Icon(Icons.keyboard_arrow_down,
                              //             size: 16, color: Colors.blue[700]),
                              //         const SizedBox(width: 4),
                              //         Text(
                              //           '다음 버스 정보',
                              //           style: TextStyle(
                              //             fontSize: 13,
                              //             fontWeight: FontWeight.w500,
                              //             color: Colors.blue[700],
                              //           ),
                              //         ),
                              //       ],
                              //     ),
                              //   ),
                              // ),
                              // const SizedBox(height: 16),

                              // 다음 버스 정보 섹션 헤더
                              const Text(
                                '다음 버스 정보',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 다음 버스 목록
                              ...busArrival.buses.skip(1).map((bus) {
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: Colors.grey[200]!),
                                  ),
                                  child: InkWell(
                                    onTap: () {
                                      // 해당 버스만 포함한 새 BusArrival 객체 생성
                                      final selectedBusArrival = BusArrival(
                                        routeNo: busArrival.routeNo,
                                        destination: busArrival.destination,
                                        routeId: busArrival.routeId,
                                        buses: [bus],
                                        stationId: busArrival.stationId,
                                      );

                                      // 현재 모달 닫고 새 버스 상세 모달 열기
                                      Navigator.pop(context);
                                      _showBusDetailModal(
                                          context, station, selectedBusArrival);
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Row(
                                        children: [
                                          // 버스 번호와 저상 여부
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    busArrival.routeNo,
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.blue[600],
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  if (bus.isLowFloor)
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 4,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            Colors.green[100],
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4),
                                                      ),
                                                      child: Text(
                                                        '저상',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color:
                                                              Colors.green[700],
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                bus.currentStation,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              Text(
                                                bus.remainingStops.toString(),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[500],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const Spacer(),
                                          // 도착 시간
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                '도착예정',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                              Text(
                                                bus.arrivalTime,
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      bus.getRemainingMinutes() <=
                                                              3
                                                          ? Colors.red
                                                          : Colors.blue[600],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                              const SizedBox(height: 20),
                            ],
                          ],
                        ),
                      ),
                      // 하단 버튼 영역
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context); // 모달 닫기
                              if (hasActiveAlarm) {
                                logMessage('${busArrival.routeNo}번 도착 알림 취소 요청',
                                    level: LogLevel.debug);

                                // 알람 서비스 참조
                                final alarmService = Provider.of<AlarmService>(
                                    context,
                                    listen: false);

                                // 알림 서비스 초기화
                                final notificationService =
                                    NotificationService();
                                await notificationService.initialize();

                                // 알람 ID 가져오기
                                int alarmId = alarmService.getAlarmId(
                                  busArrival.routeNo,
                                  station.name,
                                  routeId: busArrival.routeId,
                                );

                                // 알람 목록에서 바로 제거 (UI 즉시 반응을 위해)
                                alarmService.removeFromCacheBeforeCancel(
                                  busArrival.routeNo,
                                  station.name,
                                  busArrival.routeId,
                                );

                                // 실제 알람 취소
                                final success =
                                    await alarmService.cancelAlarmByRoute(
                                  busArrival.routeNo,
                                  station.name,
                                  busArrival.routeId,
                                );

                                // 관련 알림 모두 취소
                                await notificationService
                                    .cancelNotification(alarmId);
                                await notificationService
                                    .cancelOngoingTracking();

                                // 알람 즉시 새로고침
                                await alarmService.loadAlarms();

                                if (success && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${busArrival.routeNo}번 도착 알림이 취소되었습니다'),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                } else if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${busArrival.routeNo}번 도착 알림 취소에 실패했습니다'),
                                      backgroundColor: Colors.red[700],
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } else {
                                _showFavoriteAlarmModal(
                                    context, station, busArrival);
                              }
                            },
                            icon: Icon(
                              hasActiveAlarm
                                  ? Icons.notifications_off
                                  : Icons.notifications_active,
                            ),
                            label: Text(
                              hasActiveAlarm ? '도착 알림 취소' : '도착 알림 설정',
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor:
                                  hasActiveAlarm ? Colors.red[100] : null,
                              foregroundColor:
                                  hasActiveAlarm ? Colors.red[700] : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _startStationTracking(BusStop station) async {
    try {
      final result =
          await _stationTrackingChannel.invokeMethod('startStationTracking', {
        'stationId': station.id,
        'stationName': station.name,
      });
      if (result == true && mounted) {
        setState(() {
          _stationTrackingStatus[station.id] = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${station.name} 정류장 전체 도착 정보 추적을 시작합니다.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on PlatformException catch (e) {
      logMessage("Failed to start station tracking: '${e.message}'.",
          level: LogLevel.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('정류장 추적 시작 실패: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _stopStationTracking(BusStop station) async {
    try {
      final result =
          await _stationTrackingChannel.invokeMethod('stopStationTracking');
      if (result == true && mounted) {
        setState(() {
          _stationTrackingStatus[station.id] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${station.name} 정류장 전체 도착 정보 추적을 중지합니다.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on PlatformException catch (e) {
      logMessage("Failed to stop station tracking: '${e.message}'.",
          level: LogLevel.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('정류장 추적 중지 실패: ${e.message}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}
