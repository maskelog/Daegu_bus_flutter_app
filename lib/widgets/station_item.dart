import 'package:flutter/material.dart';
import '../models/bus_stop.dart';

class StationItem extends StatelessWidget {
  final BusStop station;
  final bool isSelected;
  final bool isTracking; // 추가: 정류장 추적 상태
  final Function() onTap;
  final Function()? onFavoriteToggle;
  final Function()? onTrackingToggle; // 추가: 정류장 추적 토글 콜백

  const StationItem({
    super.key,
    required this.station,
    required this.isSelected,
    this.isTracking = false, // 기본값 false
    required this.onTap,
    this.onFavoriteToggle,
    this.onTrackingToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.blue.shade300 : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected ? Colors.blue.shade50 : Colors.grey.shade50,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 정류장 정보 행
              Row(
                children: [
                  // 위치 아이콘
                  Icon(
                    Icons.location_on,
                    color: Colors.grey.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  // 정류장 번호 (있는 경우)
                  if (station.wincId != null && station.wincId!.isNotEmpty)
                    Text(
                      station.wincId!,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  const Spacer(),
                  // 즐겨찾기 버튼
                  if (onFavoriteToggle != null)
                    IconButton(
                      icon: Icon(
                        station.isFavorite ? Icons.star : Icons.star_border,
                        color: station.isFavorite ? Colors.amber : Colors.grey,
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onFavoriteToggle,
                    ),
                  // 정류장 추적 버튼
                  if (onTrackingToggle != null)
                    IconButton(
                      icon: Icon(
                        isTracking ? Icons.visibility : Icons.visibility_off,
                        color: isTracking ? Colors.green : Colors.grey,
                        size: 24,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: onTrackingToggle,
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // 정류장 이름
              Text(
                station.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.blue.shade700 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
