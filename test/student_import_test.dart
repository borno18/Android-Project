import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/services/student_import_service.dart';

void main() {
  group('DatabaseHelper Session Derivation Tests', () {
    test('Correctly derives 2023-24 session from 2023831004', () {
      final session = DatabaseHelper.deriveSessionFromRegNumber('2023831004');
      expect(session, equals('2023-24'));
    });

    test('Correctly derives 2022-23 session from 2022831015', () {
      final session = DatabaseHelper.deriveSessionFromRegNumber('2022831015');
      expect(session, equals('2022-23'));
    });

    test('Correctly derives 2019-20 session from 2019123456', () {
      final session = DatabaseHelper.deriveSessionFromRegNumber('2019123456');
      expect(session, equals('2019-20'));
    });

    test('Handles 2-digit prefix like 23-831-004', () {
      final session = DatabaseHelper.deriveSessionFromRegNumber('23-831-004');
      expect(session, equals('2023-24'));
    });

    test('Falls back to General for non-standard reg numbers', () {
      final session = DatabaseHelper.deriveSessionFromRegNumber('ABC');
      expect(session, equals('General'));
    });
  });

  group('StudentImportService CSV Parsing Tests', () {
    test('Parses CSV file with headers correctly', () async {
      final tempDir = await Directory.systemTemp.createTemp('student_test_');
      final testCsv = File('${tempDir.path}/test_students.csv');
      await testCsv.writeAsString('''
Registration Number,Student Name
2023831001,Alice Johnson
2023831002,Bob Smith
2022831003,Charlie Brown
''');

      final students = await StudentImportService.parseSpreadsheetOrCsv(testCsv.path);
      expect(students.length, equals(3));
      expect(students[0]['regNumber'], equals('2023831001'));
      expect(students[0]['name'], equals('Alice Johnson'));
      expect(students[0]['session'], equals('2023-24'));

      expect(students[1]['regNumber'], equals('2023831002'));
      expect(students[1]['name'], equals('Bob Smith'));
      expect(students[1]['session'], equals('2023-24'));

      expect(students[2]['regNumber'], equals('2022831003'));
      expect(students[2]['name'], equals('Charlie Brown'));
      expect(students[2]['session'], equals('2022-23'));

      await tempDir.delete(recursive: true);
    });

    test('Parses CSV file without headers (raw regNumber, name pairs)', () async {
      final tempDir = await Directory.systemTemp.createTemp('student_test_');
      final testCsv = File('${tempDir.path}/test_raw.csv');
      await testCsv.writeAsString('''
2023831004,Rahim Ahmed
2023831005,Karim Ullah
''');

      final students = await StudentImportService.parseSpreadsheetOrCsv(testCsv.path);
      expect(students.length, equals(2));
      expect(students[0]['regNumber'], equals('2023831004'));
      expect(students[0]['name'], equals('Rahim Ahmed'));
      expect(students[0]['session'], equals('2023-24'));

      await tempDir.delete(recursive: true);
    });
  });
}
