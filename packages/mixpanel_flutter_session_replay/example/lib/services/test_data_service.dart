import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/test_content.dart';

/// Service to load test data from JSON assets
class TestDataService {
  /// Load test data from assets/test_data.json
  static Future<TestData> loadTestData() async {
    try {
      final jsonString = await rootBundle.loadString('assets/test_data.json');
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      return TestData.fromJson(jsonData);
    } catch (e) {
      throw Exception('Failed to load test data: $e');
    }
  }
}
