
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:daegu_bus_app/models/bus_stop.dart';
import 'package:daegu_bus_app/services/location_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Completer<GoogleMapController> _controller = Completer();
  Position? _currentPosition;
  Set<Marker> _markers = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _getCurrentLocationAndNearbyStops();
  }

  Future<void> _getCurrentLocationAndNearbyStops() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (!mounted) return;
      final nearbyStops = await LocationService.getNearbyStations(500, context: context);
      _setMarkers(nearbyStops);
    } catch (e) {
      // Handle location errors
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setMarkers(List<BusStop> stops) {
    setState(() {
      _markers = stops.map((stop) {
        return Marker(
          markerId: MarkerId(stop.id),
          position: LatLng(stop.latitude!, stop.longitude!),
          infoWindow: InfoWindow(
            title: stop.name,
            snippet: 'ID: ${stop.id}',
          ),
        );
      }).toSet();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : GoogleMap(
              mapType: MapType.normal,
              initialCameraPosition: CameraPosition(
                target: _currentPosition != null
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    : LatLng(35.8714, 128.6014), // Default to Daegu
                zoom: 15,
              ),
              onMapCreated: (GoogleMapController controller) {
                _controller.complete(controller);
              },
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
    );
  }
}
