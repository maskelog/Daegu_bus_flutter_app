import 'package:flutter/material.dart';

import '../models/bus_route.dart';

const Color _routeDirectBackground = Color(0xFFFFFFFF);
const Color _routeExpressBackground = Color(0xFFE60012);
const Color _routeCircularBackground = Color(0xFF009944);
const Color _routeTrunkBackground = Color(0xFF00A0E9);
const Color _routeBranchBackground = Color(0xFFF39800);
const Color _routeCommuteBackground = Color(0xFF8CC63F);
const Color _routeGunwiBackground = Color(0xFF1D2088);
const Color _routeTourBackground = Color(0xFFE4007F);
const Color _routeDrtBackground = Color(0xFFE60012);
const Color _routeBrandRed = Color(0xFFE60012);

/// 대구 버스 노선 배지용 분류.
enum RouteBrandType {
  direct,
  express,
  circular,
  trunk,
  branch,
  commute,
  gunwi,
  tour,
  drt,
}

/// 노선 분류에 따른 배지 색상 세트.
class RouteBranding {
  final RouteBrandType type;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final double borderWidth;

  const RouteBranding({
    required this.type,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.borderWidth,
  });

  Color get emphasisColor => borderWidth > 0 ? borderColor : backgroundColor;
}

RouteBranding? resolveRouteBranding({
  required String routeNo,
  String? routeDescription,
  String? routeTp,
}) {
  final haystack = [routeNo, routeDescription, routeTp]
      .where((item) => item != null && item.trim().isNotEmpty)
      .map((item) => item!.toLowerCase())
      .join(' ');

  if (haystack.contains('drt')) {
    return const RouteBranding(
      type: RouteBrandType.drt,
      label: 'DRT',
      backgroundColor: _routeDrtBackground,
      foregroundColor: Colors.white,
      borderColor: _routeDrtBackground,
      borderWidth: 0,
    );
  }
  if (haystack.contains('군위')) {
    return const RouteBranding(
      type: RouteBrandType.gunwi,
      label: '군위',
      backgroundColor: _routeGunwiBackground,
      foregroundColor: Colors.white,
      borderColor: _routeGunwiBackground,
      borderWidth: 0,
    );
  }
  if (haystack.contains('투어')) {
    return const RouteBranding(
      type: RouteBrandType.tour,
      label: '투어',
      backgroundColor: _routeTourBackground,
      foregroundColor: Colors.white,
      borderColor: _routeTourBackground,
      borderWidth: 0,
    );
  }
  if (haystack.contains('출근')) {
    return const RouteBranding(
      type: RouteBrandType.commute,
      label: '출근',
      backgroundColor: _routeCommuteBackground,
      foregroundColor: Colors.white,
      borderColor: _routeCommuteBackground,
      borderWidth: 0,
    );
  }
  if (haystack.contains('순환')) {
    return const RouteBranding(
      type: RouteBrandType.circular,
      label: '순환',
      backgroundColor: _routeCircularBackground,
      foregroundColor: Colors.white,
      borderColor: _routeCircularBackground,
      borderWidth: 0,
    );
  }
  if (haystack.contains('간선')) {
    return const RouteBranding(
      type: RouteBrandType.trunk,
      label: '간선',
      backgroundColor: _routeTrunkBackground,
      foregroundColor: Colors.white,
      borderColor: _routeTrunkBackground,
      borderWidth: 0,
    );
  }
  if (haystack.contains('지선')) {
    return const RouteBranding(
      type: RouteBrandType.branch,
      label: '지선',
      backgroundColor: _routeBranchBackground,
      foregroundColor: Colors.white,
      borderColor: _routeBranchBackground,
      borderWidth: 0,
    );
  }
  if (haystack.contains('직행')) {
    return const RouteBranding(
      type: RouteBrandType.direct,
      label: '직행',
      backgroundColor: _routeDirectBackground,
      foregroundColor: _routeBrandRed,
      borderColor: _routeBrandRed,
      borderWidth: 1.25,
    );
  }
  if (haystack.contains('급행')) {
    return const RouteBranding(
      type: RouteBrandType.express,
      label: '급행',
      backgroundColor: _routeExpressBackground,
      foregroundColor: Colors.white,
      borderColor: _routeExpressBackground,
      borderWidth: 0,
    );
  }
  return null;
}

RouteBranding? resolveRouteBrandingForRoute(BusRoute route) {
  return resolveRouteBranding(
    routeNo: route.routeNo,
    routeDescription: route.routeDescription,
    routeTp: route.routeTp,
  );
}

