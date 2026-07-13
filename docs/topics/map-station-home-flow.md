# 지도 정류장 선택 → 홈 전환

> 이 문서는 **현재 상태**를 서술한다. 변경 이력은 [devlog.md](../devlog.md)를 참조한다.
> 마지막 갱신: 2026-07-13

## 사용자 흐름

- 지도에서 도착 정보 조회가 가능한 정류장 마커를 선택하면 지도 하단에 정류장명과
  `홈에서 보기` 액션 카드가 표시된다.
- 빈 지도 또는 닫기 버튼을 누르면 액션 카드가 닫힌다.
- 홈 화면에 임베드된 지도에서는 `onShowStationOnHome` 콜백으로 홈 탭을 선택하고 해당
  정류장의 도착 정보를 표시한다.
- 노선도에서 push된 지도에서는 선택한 `BusStop`을 Navigator 결과로 반환한다. 노선도
  화면이 그 결과를 받아 자신의 `onShowStationOnHome` 콜백으로 전달하거나 상위 화면으로
  다시 반환한다.

## 구현 위치

- `lib/screens/map_screen.dart` — 마커 선택 상태, 액션 카드, 콜백/결과 반환
- `lib/screens/route_map_screen.dart` — push된 지도의 `BusStop` 결과 전달
- `lib/screens/home_screen.dart` — 홈/노선도 탭의 콜백 처리와 선택 정류장 갱신

## 유효 정류장 조건

- 도착 정보를 조회할 수 있는 유효한 stationId가 확정된 정류장만 액션 카드에 반영한다.
- 지도 데이터에 stationId가 없으면 API 검색 fallback으로 정류장을 확정한 뒤 카드 상태를
  갱신한다.

## 검증 상태

- Galaxy S25 Ultra(Android 16 / One UI 8)에서 지도 마커 선택 → `홈에서 보기` → 홈 탭
  전환 → 선택 정류장 도착 정보 표시 흐름을 ADB 입력과 화면 캡처로 확인했다.
