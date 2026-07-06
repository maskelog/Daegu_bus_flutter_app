import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/services/alarm/holiday_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MockClient countingClient(int statusCode, String body, List<Uri> log) {
    return MockClient((request) async {
      log.add(request.url);
      // 한글 본문이 latin-1로 인코딩되지 않도록 UTF-8 명시
      return http.Response.bytes(utf8.encode(body), statusCode, headers: {
        'content-type': 'application/json; charset=utf-8',
      });
    });
  }

  MockClient failingClient(List<Uri> log) {
    return MockClient((request) async {
      log.add(request.url);
      throw Exception('network down');
    });
  }

  test('신선한 영속 캐시가 있으면 네트워크를 타지 않는다', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'holidays_cache_2030': jsonEncode(['2030-01-01', '2030-03-01']),
      'holidays_cache_at_2030': now,
    });
    final requests = <Uri>[];
    final service =
        HolidayService.internal(client: failingClient(requests));

    final january = await service.fetchHolidays(2030, 1);
    final march = await service.fetchHolidays(2030, 3);

    expect(january, [DateTime(2030, 1, 1)]);
    expect(march, [DateTime(2030, 3, 1)]);
    expect(requests, isEmpty);
  });

  test('CDN 성공 시 결과를 영속 캐시에 저장한다', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final body = jsonEncode({'2030-05-05': '어린이날', '2030-05-06': '대체공휴일'});
    final service =
        HolidayService.internal(client: countingClient(200, body, requests));

    final may = await service.fetchHolidays(2030, 5);

    expect(may, [DateTime(2030, 5, 5), DateTime(2030, 5, 6)]);
    expect(requests, hasLength(1));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('holidays_cache_2030'),
        jsonEncode(['2030-05-05', '2030-05-06']));
    expect(prefs.getInt('holidays_cache_at_2030'), isNotNull);
  });

  test('CDN 실패 시 만료된 영속 캐시라도 사용한다', () async {
    final staleAt = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    SharedPreferences.setMockInitialValues({
      'holidays_cache_2030': jsonEncode(['2030-08-15']),
      'holidays_cache_at_2030': staleAt,
    });
    final requests = <Uri>[];
    final service =
        HolidayService.internal(client: failingClient(requests));

    final august = await service.fetchHolidays(2030, 8);

    expect(august, [DateTime(2030, 8, 15)]);
    expect(requests, hasLength(1)); // CDN 시도는 했음
  });

  test('영속 캐시 없이 CDN 실패 시 번들 에셋으로 폴백한다', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final service =
        HolidayService.internal(client: failingClient(requests));

    // assets/holidays/2026.json이 번들되어 있다
    final january = await service.fetchHolidays(2026, 1);

    expect(january, contains(DateTime(2026, 1, 1)));
    expect(requests, hasLength(1));
  });

  test('완전 실패 시 양력 고정 공휴일로 대체하고, 30분 내 재호출은 CDN을 건너뛴다', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final service =
        HolidayService.internal(client: failingClient(requests));

    // 에셋이 없는 연도 → 완전 실패 → 양력 고정 공휴일 fallback
    final january = await service.fetchHolidays(2099, 1);
    expect(january, [DateTime(2099, 1, 1)]); // 신정
    expect(requests, hasLength(1));

    final february = await service.fetchHolidays(2099, 2);
    expect(february, isEmpty); // 2월엔 양력 고정 공휴일 없음 (설날은 계산 불가)

    // 직후 재호출: 실패가 메모리에 눌러앉지 않았으므로 다시 시도하되,
    // 30분 백오프 때문에 CDN 요청은 추가로 나가지 않는다
    expect(requests, hasLength(1));
  });

  test('제헌절·노동절과 그 대체공휴일은 걸러진다', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final body = jsonEncode({
      '2027-05-01': ['노동절'],
      '2027-05-03': ['대체공휴일(노동절)'],
      '2027-07-17': ['제헌절'],
      '2027-07-19': ['대체공휴일(제헌절)'],
      '2027-08-15': ['광복절'],
    });
    final service =
        HolidayService.internal(client: countingClient(200, body, requests));

    final may = await service.fetchHolidays(2027, 5);
    final july = await service.fetchHolidays(2027, 7);
    final august = await service.fetchHolidays(2027, 8);

    expect(may, isEmpty);
    expect(july, isEmpty);
    expect(august, [DateTime(2027, 8, 15)]);

    // 영속 캐시에도 걸러진 결과만 저장된다
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('holidays_cache_2027'), jsonEncode(['2027-08-15']));
  });

  test('fallback이 확정 공휴일을 재현한다 — 2025~2027 전체 대조 (대체공휴일 포함)', () {
    final service = HolidayService.internal();

    // 기준값: upstream 확정 데이터(CDN)에서 실측한 관공서 공휴일.
    // fallback이 계산할 수 없는 임시공휴일·선거일만 제외한 전체 목록.
    expect(service.fallbackHolidaysForYear(2025), [
      DateTime(2025, 1, 1),
      DateTime(2025, 1, 28), DateTime(2025, 1, 29), DateTime(2025, 1, 30),
      DateTime(2025, 3, 1), DateTime(2025, 3, 3), // 삼일절(토) → 월요일 대체
      DateTime(2025, 5, 5), DateTime(2025, 5, 6), // 어린이날+부처님오신날 겹침 → 대체
      DateTime(2025, 6, 6),
      DateTime(2025, 8, 15),
      DateTime(2025, 10, 3),
      DateTime(2025, 10, 5), DateTime(2025, 10, 6), DateTime(2025, 10, 7),
      DateTime(2025, 10, 8), // 추석 연휴 중 일요일(10/5) → 대체
      DateTime(2025, 10, 9),
      DateTime(2025, 12, 25),
    ]);

    expect(service.fallbackHolidaysForYear(2026), [
      DateTime(2026, 1, 1),
      DateTime(2026, 2, 16), DateTime(2026, 2, 17), DateTime(2026, 2, 18),
      DateTime(2026, 3, 1), DateTime(2026, 3, 2), // 삼일절(일) → 대체
      DateTime(2026, 5, 5),
      DateTime(2026, 5, 24), DateTime(2026, 5, 25), // 부처님오신날(일) → 대체
      DateTime(2026, 6, 6), // 현충일(토) — 대체 없음
      DateTime(2026, 8, 15), DateTime(2026, 8, 17), // 광복절(토) → 일요일 건너뛰고 월요일
      DateTime(2026, 9, 24), DateTime(2026, 9, 25), DateTime(2026, 9, 26),
      DateTime(2026, 10, 3), DateTime(2026, 10, 5), // 개천절(토) → 대체
      DateTime(2026, 10, 9),
      DateTime(2026, 12, 25),
    ]);

    expect(service.fallbackHolidaysForYear(2027), [
      DateTime(2027, 1, 1),
      DateTime(2027, 2, 6), DateTime(2027, 2, 7), DateTime(2027, 2, 8),
      DateTime(2027, 2, 9), // 설날 연휴 중 일요일(2/7) → 대체
      DateTime(2027, 3, 1),
      DateTime(2027, 5, 5),
      DateTime(2027, 5, 13),
      DateTime(2027, 6, 6), // 현충일(일) — 대체 없음
      DateTime(2027, 8, 15), DateTime(2027, 8, 16), // 광복절(일) → 대체
      DateTime(2027, 9, 14), DateTime(2027, 9, 15), DateTime(2027, 9, 16),
      DateTime(2027, 10, 3), DateTime(2027, 10, 4), // 개천절(일) → 대체
      DateTime(2027, 10, 9), DateTime(2027, 10, 11), // 한글날(토) → 대체
      DateTime(2027, 12, 25), DateTime(2027, 12, 27), // 성탄절(토) → 대체
    ]);
  });

  test('fallback은 변환 테이블 범위(~2049) 밖에서는 음력 공휴일을 계산하지 않는다', () {
    final service = HolidayService.internal();
    final holidays2099 = service.fallbackHolidaysForYear(2099);
    expect(holidays2099, contains(DateTime(2099, 1, 1)));
    // 설날(1~2월 음력)·추석(9~10월 음력)은 미계산 — 9월에 날짜가 없어야 한다
    expect(holidays2099.where((d) => d.month == 9), isEmpty);
  });

  test('유효한 공휴일 이름이 하나라도 겹치면 유지한다', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final body = jsonEncode({
      '2025-05-05': ['어린이날', '부처님오신날'],
      '2025-05-01': ['노동절', '어린이날'], // 가상의 겹침 — 유효 이름 존재
    });
    final service =
        HolidayService.internal(client: countingClient(200, body, requests));

    final may = await service.fetchHolidays(2025, 5);

    expect(may, containsAll([DateTime(2025, 5, 5), DateTime(2025, 5, 1)]));
  });

  test('동시 호출은 CDN 요청 1회로 합류한다', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final body = jsonEncode({'2030-01-01': '신정'});
    final service =
        HolidayService.internal(client: countingClient(200, body, requests));

    final results = await Future.wait([
      service.fetchHolidays(2030, 1),
      service.fetchHolidays(2030, 1),
    ]);

    expect(results[0], [DateTime(2030, 1, 1)]);
    expect(results[1], [DateTime(2030, 1, 1)]);
    expect(requests, hasLength(1));
  });
}
