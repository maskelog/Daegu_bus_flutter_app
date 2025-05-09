import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/main.dart' show log;
import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:flutter/material.dart';

class BusArrivalScreen extends StatefulWidget {
  final BusArrival busArrival;
  final String stationName;

  const BusArrivalScreen(
      {super.key, required this.busArrival, required this.stationName});

  @override
  State<BusArrivalScreen> createState() => _BusArrivalScreenState();
}

class _BusArrivalScreenState extends State<BusArrivalScreen> {
  late final AlarmService _alarmService;
  final _formKey = GlobalKey<FormState>();
  String? _message;
  bool _isLoading = false;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _alarmService = AlarmService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.busArrival.routeNo}번 버스'),
      ),
      body: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBusInfoCard(),
              const SizedBox(height: 24),
              _buildMessageDisplay(),
              const SizedBox(height: 16),
              _buildActionButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBusInfoCard() {
    final busInfo = widget.busArrival.busInfoList.isNotEmpty
        ? widget.busArrival.busInfoList.first
        : null;

    final remainingMinutes = busInfo?.getRemainingMinutes() ?? 0;
    final isArrivingSoon = remainingMinutes <= 3 && remainingMinutes > 0;
    final isOutOfService = busInfo?.isOutOfService ?? true;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.stationName} 정류장',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (busInfo != null) ...[
              Text(
                '현재 위치: ${busInfo.currentStation}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                '남은 정류장: ${busInfo.remainingStops}',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              _buildTimeIndicator(
                  remainingMinutes, isArrivingSoon, isOutOfService),
            ] else
              const Text(
                '버스 정보를 불러올 수 없습니다',
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeIndicator(
      int remainingMinutes, bool isArrivingSoon, bool isOutOfService) {
    String timeText;
    Color textColor;

    if (isOutOfService) {
      timeText = '운행 종료';
      textColor = Colors.grey;
    } else if (remainingMinutes <= 0) {
      timeText = '곧 도착';
      textColor = Colors.green;
    } else {
      timeText = '$remainingMinutes분 후 도착';
      textColor = isArrivingSoon ? Colors.red : Colors.blue;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Color.fromARGB(
            26, textColor.r.toInt(), textColor.g.toInt(), textColor.b.toInt()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Color.fromARGB(77, textColor.r.toInt(), textColor.g.toInt(),
              textColor.b.toInt()),
        ),
      ),
      child: Text(
        timeText,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildMessageDisplay() {
    if (_message == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isSuccess
            ? const Color(0x1A008000) // Color.fromRGBO(0, 128, 0, 0.1)
            : const Color(0x1AFF0000), // Color.fromRGBO(255, 0, 0, 0.1)
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isSuccess
              ? const Color(0x4D008000) // Color.fromRGBO(0, 128, 0, 0.3)
              : const Color(0x4DFF0000), // Color.fromRGBO(255, 0, 0, 0.3)
        ),
      ),
      child: Text(
        _message!,
        style: TextStyle(
          color: _isSuccess ? Colors.green[700] : Colors.red[700],
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildActionButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _handleArrival,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          : const Text(
              '알람 설정',
              style: TextStyle(fontSize: 16),
            ),
    );
  }

  Future<void> _handleArrival() async {
    setState(() {
      _message = null;
      _isLoading = true;
      _isSuccess = false;
    });

    try {
      // 남은 시간 계산
      final remainingMinutes = widget.busArrival.busInfoList.isNotEmpty
          ? widget.busArrival.busInfoList.first.getRemainingMinutes()
          : 0;

      if (remainingMinutes <= 0) {
        _showMessage('버스가 이미 도착했거나 곧 도착합니다', false);
        return;
      }

      bool success = await _alarmService.setOneTimeAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        remainingMinutes,
        routeId: widget.busArrival.routeId,
        useTTS: true,
      );

      if (success) {
        _showMessage('알람이 설정되었습니다', true);
      } else {
        _showMessage('알람 설정에 실패했습니다', false);
      }
    } catch (e) {
      log('알람 설정 중 오류 발생: $e');
      _showMessage('오류가 발생했습니다: $e', false);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showMessage(String message, bool isSuccess) {
    setState(() {
      _message = message;
      _isSuccess = isSuccess;
    });

    // 3초 후 메시지 제거
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _message = null;
        });
      }
    });
  }
}
