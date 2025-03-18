import 'package:flutter/material.dart';

class TimePickerSpinner extends StatefulWidget {
  final DateTime time;
  final bool is24HourMode;
  final TextStyle normalTextStyle;
  final TextStyle highlightedTextStyle;
  final int itemHeight;
  final int itemWidth;
  final int spacing;
  final AlignmentGeometry alignment;
  final Function(DateTime) onTimeChange;

  const TimePickerSpinner({
    super.key,
    required this.time,
    required this.onTimeChange,
    this.is24HourMode = true,
    this.normalTextStyle = const TextStyle(
      fontSize: 16,
      color: Colors.black54,
    ),
    this.highlightedTextStyle = const TextStyle(
      fontSize: 20,
      color: Colors.black,
    ),
    this.itemHeight = 40,
    this.itemWidth = 60,
    this.spacing = 20,
    this.alignment = Alignment.center,
  });

  @override
  State<TimePickerSpinner> createState() => _TimePickerSpinnerState();
}

class _TimePickerSpinnerState extends State<TimePickerSpinner> {
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;
  FixedExtentScrollController? _ampmController; // nullable로 변경

  late int _currentHourIndex;
  late int _currentMinuteIndex;
  late int _currentAmPmIndex;

  @override
  void initState() {
    super.initState();

    int hour = widget.time.hour;
    int minute = widget.time.minute;

    // 모든 경우에 초기화 보장
    _currentAmPmIndex = 0; // 기본값 설정
    if (!widget.is24HourMode) {
      _currentAmPmIndex = hour >= 12 ? 1 : 0;
      hour = hour % 12;
      if (hour == 0) hour = 12;
    }

    _currentHourIndex = widget.is24HourMode ? hour : hour - 1;
    _currentMinuteIndex = minute;

    _hourController =
        FixedExtentScrollController(initialItem: _currentHourIndex);
    _minuteController =
        FixedExtentScrollController(initialItem: _currentMinuteIndex);
    if (!widget.is24HourMode) {
      _ampmController =
          FixedExtentScrollController(initialItem: _currentAmPmIndex);
    }
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _ampmController?.dispose(); // null 체크 추가
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        // 시간 선택
        SizedBox(
          width: widget.itemWidth.toDouble(),
          child: ListWheelScrollView.useDelegate(
            controller: _hourController,
            itemExtent: widget.itemHeight.toDouble(),
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              if (mounted) {
                setState(() => _currentHourIndex = index);
                _onTimeChanged();
              }
            },
            childDelegate: ListWheelChildBuilderDelegate(
              builder: (context, index) {
                int displayHour = widget.is24HourMode ? index : index + 1;
                if (!widget.is24HourMode && displayHour > 12) {
                  displayHour = displayHour % 12;
                }
                return _buildTimeItem(
                  displayHour.toString().padLeft(2, '0'),
                  index == _currentHourIndex,
                );
              },
              childCount: widget.is24HourMode ? 24 : 12,
            ),
          ),
        ),

        Text(
          ':',
          style: widget.highlightedTextStyle,
        ),

        // 분 선택
        SizedBox(
          width: widget.itemWidth.toDouble(),
          child: ListWheelScrollView.useDelegate(
            controller: _minuteController,
            itemExtent: widget.itemHeight.toDouble(),
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (index) {
              if (mounted) {
                setState(() => _currentMinuteIndex = index);
                _onTimeChanged();
              }
            },
            childDelegate: ListWheelChildBuilderDelegate(
              builder: (context, index) {
                return _buildTimeItem(
                  index.toString().padLeft(2, '0'),
                  index == _currentMinuteIndex,
                );
              },
              childCount: 60,
            ),
          ),
        ),

        // AM/PM 선택 (12시간 모드일 때만)
        if (!widget.is24HourMode && _ampmController != null)
          SizedBox(
            width: widget.itemWidth.toDouble(),
            child: ListWheelScrollView.useDelegate(
              controller: _ampmController,
              itemExtent: widget.itemHeight.toDouble(),
              physics: const FixedExtentScrollPhysics(),
              onSelectedItemChanged: (index) {
                if (mounted) {
                  setState(() => _currentAmPmIndex = index);
                  _onTimeChanged();
                }
              },
              childDelegate: ListWheelChildBuilderDelegate(
                builder: (context, index) {
                  return _buildTimeItem(
                    index == 0 ? 'AM' : 'PM',
                    index == _currentAmPmIndex,
                  );
                },
                childCount: 2,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeItem(String text, bool isSelected) {
    return Center(
      child: Text(
        text,
        style:
            isSelected ? widget.highlightedTextStyle : widget.normalTextStyle,
        textAlign: TextAlign.center,
      ),
    );
  }

  void _onTimeChanged() {
    int hour = _currentHourIndex;
    int minute = _currentMinuteIndex;

    if (!widget.is24HourMode) {
      hour = hour + 1; // 1~12 범위로 조정
      if (_currentAmPmIndex == 1) {
        // PM
        if (hour < 12) {
          hour += 12;
        }
      } else {
        // AM
        if (hour == 12) {
          hour = 0;
        }
      }
    }

    DateTime newTime = DateTime(
      widget.time.year,
      widget.time.month,
      widget.time.day,
      hour,
      minute,
    );

    widget.onTimeChange(newTime);
  }
}
