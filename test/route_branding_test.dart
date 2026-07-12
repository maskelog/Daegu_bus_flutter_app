import 'package:daegu_bus_app/utils/route_branding.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves the requested route brand palette', () {
    final cases = <({String routeNo, String label, Color bg, Color fg, Color border})>[
      (routeNo: '직행1', label: '직행', bg: const Color(0xFFFFFFFF), fg: const Color(0xFFE60012), border: const Color(0xFFE60012)),
      (routeNo: '급행2', label: '급행', bg: const Color(0xFFE60012), fg: Colors.white, border: const Color(0xFFE60012)),
      (routeNo: '순환3', label: '순환', bg: const Color(0xFF009944), fg: Colors.white, border: const Color(0xFF009944)),
      (routeNo: '간선4', label: '간선', bg: const Color(0xFF00A0E9), fg: Colors.white, border: const Color(0xFF00A0E9)),
      (routeNo: '지선5', label: '지선', bg: const Color(0xFFF39800), fg: Colors.white, border: const Color(0xFFF39800)),
      (routeNo: '출근6', label: '출근', bg: const Color(0xFF8CC63F), fg: Colors.white, border: const Color(0xFF8CC63F)),
      (routeNo: '군위7', label: '군위', bg: const Color(0xFF1D2088), fg: Colors.white, border: const Color(0xFF1D2088)),
      (routeNo: '투어8', label: '투어', bg: const Color(0xFFE4007F), fg: Colors.white, border: const Color(0xFFE4007F)),
      (routeNo: 'DRT9', label: 'DRT', bg: const Color(0xFFE60012), fg: Colors.white, border: const Color(0xFFE60012)),
    ];

    for (final testCase in cases) {
      final branding = resolveRouteBranding(routeNo: testCase.routeNo);
      expect(branding, isNotNull, reason: testCase.routeNo);
      expect(branding!.label, testCase.label);
      expect(branding.backgroundColor, testCase.bg);
      expect(branding.foregroundColor, testCase.fg);
      expect(branding.borderColor, testCase.border);
    }
  });
}
