import 'package:flutter/material.dart';
import 'package:daegu_bus_app/services/api_service.dart';

class BusSelectionScreen extends StatefulWidget {
  final String stationId;
  final String stationName;

  const BusSelectionScreen({
    super.key,
    required this.stationId,
    required this.stationName,
  });

  @override
  State<BusSelectionScreen> createState() => _BusSelectionScreenState();
}

class _BusSelectionScreenState extends State<BusSelectionScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _busRoutes = [];
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadBusRoutes();
  }

  Future<void> _loadBusRoutes() async {
    try {
      setState(() => _isLoading = true);
      final routes = await ApiService.getBusRoutesByStation(widget.stationId);
      setState(() {
        _busRoutes = routes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '버스 노선 정보를 불러오는데 실패했습니다.';
        _isLoading = false;
      });
      debugPrint('버스 노선 로딩 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.stationName} 버스 선택'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadBusRoutes,
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : _busRoutes.isEmpty
                  ? const Center(
                      child: Text('이 정류장을 지나는 버스가 없습니다.'),
                    )
                  : ListView.builder(
                      itemCount: _busRoutes.length,
                      itemBuilder: (context, index) {
                        final route = _busRoutes[index];
                        return ListTile(
                          title: Text(route['routeNo'] ?? ''),
                          subtitle: Text(route['routeDescription'] ?? ''),
                          onTap: () {
                            Navigator.pop(context, {
                              'routeId': route['id'],
                              'routeNo': route['routeNo'],
                            });
                          },
                        );
                      },
                    ),
    );
  }
}
