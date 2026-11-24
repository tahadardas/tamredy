import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tamreedy_core/tamreedy_core.dart';
import 'package:tamreedy_patient_app/screens/saved_places.dart';

void main() {
  testWidgets(
    'picking a saved address sends its use request and returns its point',
    (tester) async {
      final api = TamreedyApi();
      final row = {
        'id': 'home',
        'label': 'المنزل',
        'formatted_address': 'دمشق، المزة',
        'latitude': 33.5,
        'longitude': 36.3,
        'accuracy': 18,
        'is_default': true,
        'floor': '2',
      };
      final requests = <String>[];
      api.dio.interceptors.clear();
      api.dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add('${request.method} ${request.path}');
            handler.resolve(
              Response(
                requestOptions: request,
                data: request.method == 'GET' ? [row] : row,
                statusCode: 200,
              ),
            );
          },
        ),
      );
      SavedPlace? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SavedPlaces(
              api: api,
              onSelected: (place) => selected = place,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('المنزل'));
      await tester.pumpAndSettle();
      expect(selected?.point, const LatLng(33.5, 36.3));
      expect(selected?.details, 'الطابق 2');
      expect(requests, [
        'GET /v1/patient/saved-places',
        'POST /v1/patient/saved-places/home/use',
      ]);
    },
  );
}
