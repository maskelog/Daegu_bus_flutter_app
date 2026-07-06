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

  test('실패는 영구 캐시되지 않고, 30분 내 재호출은 CDN을 건너뛴다', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <Uri>[];
    final service =
        HolidayService.internal(client: failingClient(requests));

    // 에셋이 없는 연도 → 완전 실패 → 빈 리스트
    final first = await service.fetchHolidays(2099, 1);
    expect(first, isEmpty);
    expect(requests, hasLength(1));

    // 직후 재호출: 실패가 메모리에 눌러앉지 않았으므로 다시 시도하되,
    // 30분 백오프 때문에 CDN 요청은 추가로 나가지 않는다
    final second = await service.fetchHolidays(2099, 1);
    expect(second, isEmpty);
    expect(requests, hasLength(1));
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
