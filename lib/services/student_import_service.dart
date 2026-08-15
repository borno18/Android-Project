import 'dart:io';
import 'package:excel/excel.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';

class StudentImportService {
  /// Parses a CSV, XLSX, or XLS file and returns a list of student records
  /// with keys: 'regNumber', 'name', 'session'.
  static Future<List<Map<String, String>>> parseSpreadsheetOrCsv(String filePath) async {
    final file = File(filePath);
    final ext = filePath.split('.').last.toLowerCase();

    if (ext == 'csv' || ext == 'txt') {
      return _parseCsvFile(file);
    } else if (ext == 'xlsx' || ext == 'xls') {
      return _parseExcelFile(file);
    } else {
      // Try CSV first, then Excel fallback
      try {
        return await _parseCsvFile(file);
      } catch (_) {
        return await _parseExcelFile(file);
      }
    }
  }

  static Future<List<Map<String, String>>> _parseCsvFile(File file) async {
    String input = await file.readAsString();
    input = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final rows = _parseCsvString(input);
    return _extractStudentsFromRows(rows);
  }

  static List<List<dynamic>> _parseCsvString(String input) {
    final List<List<dynamic>> rows = [];
    final lines = input.split('\n');
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;
      // Handle comma, semicolon, and tab separated files
      final delimiter = line.contains('\t')
          ? '\t'
          : (line.contains(';') && !line.contains(',') ? ';' : ',');

      final row = <String>[];
      if (delimiter == ',') {
        final regex = RegExp(r'(?:^|,)(?:"([^"]*(?:""[^"]*)*)"|([^,]*))');
        for (final match in regex.allMatches(line)) {
          if (match.group(1) != null) {
            row.add(match.group(1)!.replaceAll('""', '"').trim());
          } else if (match.group(2) != null) {
            row.add(match.group(2)!.trim());
          }
        }
      } else {
        row.addAll(line.split(delimiter).map((c) => c.trim().replaceAll('"', '')));
      }

      if (row.isNotEmpty) {
        rows.add(row);
      }
    }
    return rows;
  }

  static Future<List<Map<String, String>>> _parseExcelFile(File file) async {
    final bytes = await file.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    List<List<dynamic>> rows = [];

    for (final table in excel.tables.keys) {
      final sheet = excel.tables[table];
      if (sheet == null) continue;
      for (final row in sheet.rows) {
        final rowData = row.map((cell) => cell?.value?.toString() ?? '').toList();
        if (rowData.any((cell) => cell.trim().isNotEmpty)) {
          rows.add(rowData);
        }
      }
      if (rows.isNotEmpty) break; // Use the first non-empty sheet
    }

    return _extractStudentsFromRows(rows);
  }

  static List<Map<String, String>> _extractStudentsFromRows(List<List<dynamic>> rows) {
    if (rows.isEmpty) return [];

    int regColIndex = -1;
    int nameColIndex = -1;
    int sessionColIndex = -1;
    int startRow = 0;

    // 1. Check if first row contains headers
    if (rows.isNotEmpty) {
      final firstRow = rows.first.map((c) => c?.toString().toLowerCase().trim() ?? '').toList();
      for (int i = 0; i < firstRow.length; i++) {
        final h = firstRow[i];
        if (h.contains('reg') || h.contains('roll') || h.contains('student id') || h.contains('id') || h.contains('number')) {
          if (regColIndex == -1) regColIndex = i;
        } else if (h.contains('name') || h.contains('student') || h.contains('fullname')) {
          if (nameColIndex == -1) nameColIndex = i;
        } else if (h.contains('session') || h.contains('batch') || h.contains('year')) {
          if (sessionColIndex == -1) sessionColIndex = i;
        }
      }

      if (regColIndex != -1 || nameColIndex != -1) {
        startRow = 1; // Skip header row
      }
    }

    // Default column heuristics if not found in header
    if (regColIndex == -1 && nameColIndex == -1) {
      // Find which column has numbers/reg format and which has letters
      for (int r = 0; r < rows.length && r < 5; r++) {
        final row = rows[r];
        for (int c = 0; c < row.length; c++) {
          final val = row[c]?.toString().trim() ?? '';
          if (RegExp(r'^\d{6,12}$').hasMatch(val) && regColIndex == -1) {
            regColIndex = c;
          } else if (RegExp(r'^[a-zA-Z\s\.\,\-]+$').hasMatch(val) && val.length > 2 && nameColIndex == -1) {
            nameColIndex = c;
          }
        }
      }
    }

    // Fallbacks
    if (regColIndex == -1) regColIndex = 0;
    if (nameColIndex == -1) nameColIndex = 1;

    final List<Map<String, String>> students = [];
    final Set<String> seenRegs = {};

    for (int i = startRow; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty) continue;

      String reg = (regColIndex < row.length ? row[regColIndex]?.toString().trim() : '') ?? '';
      String name = (nameColIndex < row.length ? row[nameColIndex]?.toString().trim() : '') ?? '';
      String session = (sessionColIndex != -1 && sessionColIndex < row.length
          ? row[sessionColIndex]?.toString().trim()
          : '') ?? '';

      // Clean registration number (remove hyphens, spaces, leading #)
      reg = reg.replaceAll(RegExp(r'^[#\s]+'), '');

      // Skip header leftovers or empty strings
      if (reg.isEmpty || reg.toLowerCase().contains('reg') || reg.toLowerCase().contains('roll')) {
        continue;
      }

      // If reg contains pure name and name is empty (e.g. columns inverted), adjust
      if (!RegExp(r'\d').hasMatch(reg) && RegExp(r'\d').hasMatch(name)) {
        final temp = reg;
        reg = name;
        name = temp;
      }

      // Skip invalid entries with no digits
      if (!RegExp(r'\d{3,}').hasMatch(reg)) {
        continue;
      }

      if (session.isEmpty) {
        session = DatabaseHelper.deriveSessionFromRegNumber(reg);
      }

      if (name.isEmpty) {
        name = reg;
      }

      if (!seenRegs.contains(reg)) {
        seenRegs.add(reg);
        students.add({
          'regNumber': reg,
          'name': name,
          'session': session,
        });
      }
    }

    return students;
  }

  /// Performs offline OCR on an image file using Google ML Kit Text Recognition
  /// and extracts student candidates (regNumber, name, session).
  static Future<List<Map<String, String>>> parseImageWithOcr(String imagePath) async {
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final inputImage = InputImage.fromFilePath(imagePath);

    try {
      final recognizedText = await textRecognizer.processImage(inputImage);
      return _extractStudentsFromRecognizedText(recognizedText);
    } finally {
      await textRecognizer.close();
    }
  }

  static List<Map<String, String>> _extractStudentsFromRecognizedText(RecognizedText recognizedText) {
    final List<Map<String, String>> results = [];
    final Set<String> seenRegs = {};

    // Pattern matching registration numbers (e.g., 2023831004, 2022-831-004, 20211234, etc.)
    final regRegex = RegExp(r'\b(20\d{2}[0-9]{4,8}|20\d{2}[-_/][0-9]{3,8}|\d{6,12})\b');

    // 1. Line-by-line inspection (e.g., "1. 2023831004 - Rahim Ahmed" or "2023831004 Rahim")
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        if (text.isEmpty) continue;

        final match = regRegex.firstMatch(text);
        if (match != null) {
          final rawReg = match.group(0)!;
          final regNumber = rawReg.replaceAll(RegExp(r'[-_/]'), '');

          // Extract name from remaining text on that line
          String name = text
              .replaceFirst(rawReg, '')
              .replaceAll(RegExp(r'^\s*[\d\.\)\-\:\#\t]+\s*'), '') // Strip leading serial no like "1."
              .replaceAll(RegExp(r'[\,\:\;\|\-\_]+'), ' ')
              .trim();

          // Remove noise words commonly found in headers
          if (name.toLowerCase() == 'name' || name.toLowerCase() == 'student name' || name.isEmpty) {
            name = regNumber;
          }

          if (!seenRegs.contains(regNumber) && regNumber.length >= 4) {
            seenRegs.add(regNumber);
            results.add({
              'regNumber': regNumber,
              'name': name,
              'session': DatabaseHelper.deriveSessionFromRegNumber(regNumber),
            });
          }
        }
      }
    }

    // 2. If line-by-line found very few items, try spatial row grouping (columnar attendance tables)
    if (results.isEmpty || results.length <= 2) {
      final List<_OcrLineItem> allLines = [];
      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          allLines.add(_OcrLineItem(
            text: line.text.trim(),
            boundingBox: line.boundingBox,
          ));
        }
      }

      // Sort lines by Y coordinate (vertical position)
      allLines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));

      // Group lines that share approximately the same Y-axis (within 22 pixels)
      final List<List<_OcrLineItem>> rows = [];
      for (final item in allLines) {
        bool added = false;
        for (final row in rows) {
          final rowTop = row.first.boundingBox.top;
          if ((item.boundingBox.top - rowTop).abs() < 22) {
            row.add(item);
            added = true;
            break;
          }
        }
        if (!added) {
          rows.add([item]);
        }
      }

      for (final row in rows) {
        // Sort items horizontally within the row
        row.sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));
        final combinedText = row.map((e) => e.text).join(' ');

        final match = regRegex.firstMatch(combinedText);
        if (match != null) {
          final rawReg = match.group(0)!;
          final regNumber = rawReg.replaceAll(RegExp(r'[-_/]'), '');

          String name = combinedText
              .replaceFirst(rawReg, '')
              .replaceAll(RegExp(r'^\s*[\d\.\)\-\:\#\t]+\s*'), '')
              .replaceAll(RegExp(r'[\,\:\;\|\-\_]+'), ' ')
              .trim();

          if (name.toLowerCase() == 'name' || name.toLowerCase() == 'student name' || name.isEmpty) {
            name = regNumber;
          }

          if (!seenRegs.contains(regNumber) && regNumber.length >= 4) {
            seenRegs.add(regNumber);
            results.add({
              'regNumber': regNumber,
              'name': name,
              'session': DatabaseHelper.deriveSessionFromRegNumber(regNumber),
            });
          }
        }
      }
    }

    // Sort by registration number ascending by default
    results.sort((a, b) => (a['regNumber'] ?? '').compareTo(b['regNumber'] ?? ''));

    return results;
  }
}

class _OcrLineItem {
  final String text;
  final dynamic boundingBox;
  _OcrLineItem({required this.text, required this.boundingBox});
}
