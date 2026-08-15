import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_proximity_attendance/services/database_helper.dart';
import 'package:smart_proximity_attendance/services/student_import_service.dart';

class OcrScanReviewScreen extends StatefulWidget {
  final int? targetCourseId;
  final String? targetCourseCode;
  final String? initialImagePath;

  const OcrScanReviewScreen({
    super.key,
    this.targetCourseId,
    this.targetCourseCode,
    this.initialImagePath,
  });

  @override
  State<OcrScanReviewScreen> createState() => _OcrScanReviewScreenState();
}

class _OcrItem {
  TextEditingController regController;
  TextEditingController nameController;
  String session;
  bool isSelected;

  _OcrItem({
    required String regNumber,
    required String name,
    required this.session,
    this.isSelected = true,
  })  : regController = TextEditingController(text: regNumber),
        nameController = TextEditingController(text: name);

  void dispose() {
    regController.dispose();
    nameController.dispose();
  }
}

class _OcrScanReviewScreenState extends State<OcrScanReviewScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ImagePicker _picker = ImagePicker();

  String? _imagePath;
  bool _isProcessing = false;
  List<_OcrItem> _items = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null) {
      _processImage(widget.initialImagePath!);
    } else {
      _pickImage(ImageSource.camera);
    }
  }

  @override
  void dispose() {
    for (var item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 95,
      );
      if (picked != null) {
        _processImage(picked.path);
      } else if (_items.isEmpty && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open camera/gallery: $e')),
        );
      }
    }
  }

  Future<void> _processImage(String path) async {
    setState(() {
      _imagePath = path;
      _isProcessing = true;
    });

    try {
      final parsed = await StudentImportService.parseImageWithOcr(path);

      // Clean up previous items
      for (var item in _items) {
        item.dispose();
      }

      final newItems = parsed.map((p) {
        final reg = p['regNumber'] ?? '';
        final name = p['name'] ?? reg;
        final session = p['session'] ?? DatabaseHelper.deriveSessionFromRegNumber(reg);
        final item = _OcrItem(regNumber: reg, name: name, session: session);
        item.regController.addListener(() {
          final updatedReg = item.regController.text.trim();
          final updatedSession = DatabaseHelper.deriveSessionFromRegNumber(updatedReg);
          if (item.session != updatedSession) {
            setState(() {
              item.session = updatedSession;
            });
          }
        });
        return item;
      }).toList();

      if (mounted) {
        setState(() {
          _items = newItems;
          _isProcessing = false;
        });

        if (_items.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No student registration numbers recognized. Try capturing with better lighting or focus.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error running OCR: $e')),
        );
      }
    }
  }

  void _toggleSelectAll(bool select) {
    setState(() {
      for (var item in _items) {
        item.isSelected = select;
      }
    });
  }

  void _addNewRow() {
    final item = _OcrItem(
      regNumber: '',
      name: '',
      session: 'General',
      isSelected: true,
    );
    item.regController.addListener(() {
      final updatedReg = item.regController.text.trim();
      final updatedSession = DatabaseHelper.deriveSessionFromRegNumber(updatedReg);
      if (item.session != updatedSession) {
        setState(() {
          item.session = updatedSession;
        });
      }
    });
    setState(() {
      _items.add(item);
    });
  }

  void _removeItem(int index) {
    setState(() {
      final item = _items.removeAt(index);
      item.dispose();
    });
  }

  Future<void> _saveAndImport() async {
    final selectedItems = _items.where((i) => i.isSelected && i.regController.text.trim().isNotEmpty).toList();

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one student to import.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final List<Map<String, String>> studentData = selectedItems.map((i) {
        final reg = i.regController.text.trim();
        final name = i.nameController.text.trim();
        return {
          'regNumber': reg,
          'name': name.isEmpty ? reg : name,
          'session': i.session,
        };
      }).toList();

      // 1. Save all to central students database
      await _dbHelper.bulkInsertCentralStudents(studentData);

      // 2. If targetCourseId is set, enroll them into the course roster as well
      int enrolledCount = 0;
      if (widget.targetCourseId != null) {
        final regList = studentData.map((s) => s['regNumber']!).toList();
        enrolledCount = await _dbHelper.enrollStudentsFromCentralDb(widget.targetCourseId!, regList);
      }

      if (mounted) {
        setState(() => _isSaving = false);
        Navigator.pop(context, {
          'savedCentral': studentData.length,
          'enrolled': enrolledCount,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving students: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _items.where((i) => i.isSelected).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.targetCourseCode != null
            ? 'Scan Roster: ${widget.targetCourseCode}'
            : 'Scan Student List (OCR)'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt),
            tooltip: 'Retake Photo',
          ),
          IconButton(
            onPressed: () => _pickImage(ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            tooltip: 'Pick from Gallery',
          ),
        ],
      ),
      body: _isProcessing
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Scanning image with Google ML Kit (Offline)...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Extracting registration numbers and names',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Top control & image preview bar
                if (_imagePath != null)
                  Container(
                    color: Colors.indigo.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_imagePath!),
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_items.length} student(s) recognized',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                '$selectedCount selected for import',
                                style: TextStyle(color: Colors.indigo.shade700, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _toggleSelectAll(selectedCount < _items.length),
                          icon: Icon(
                            selectedCount < _items.length
                                ? Icons.select_all
                                : Icons.deselect,
                            size: 18,
                          ),
                          label: Text(
                            selectedCount < _items.length ? 'Select All' : 'Deselect All',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                // List of recognized items
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.document_scanner_outlined, size: 64, color: Colors.grey),
                                const SizedBox(height: 16),
                                const Text(
                                  'No students detected in this image',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Try taking a clearer picture of the printed student list or sheet, or add students manually below.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () => _pickImage(ImageSource.camera),
                                  icon: const Icon(Icons.camera_alt),
                                  label: const Text('Capture Again'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
                          itemCount: _items.length,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: item.isSelected ? Colors.indigo.shade300 : Colors.grey.shade200,
                                  width: item.isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Checkbox(
                                      value: item.isSelected,
                                      activeColor: Colors.indigo,
                                      onChanged: (val) {
                                        setState(() {
                                          item.isSelected = val ?? false;
                                        });
                                      },
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          TextField(
                                            controller: item.regController,
                                            decoration: const InputDecoration(
                                              labelText: 'Reg No *',
                                              isDense: true,
                                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                              border: OutlineInputBorder(),
                                            ),
                                            keyboardType: TextInputType.number,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Session: ${item.session}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.indigo.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      flex: 5,
                                      child: TextField(
                                        controller: item.nameController,
                                        decoration: const InputDecoration(
                                          labelText: 'Student Name',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                      onPressed: () => _removeItem(index),
                                      tooltip: 'Remove',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: _addNewRow,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Row'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSaving || selectedCount == 0 ? null : _saveAndImport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  widget.targetCourseCode != null
                      ? 'Import & Enroll ($selectedCount)'
                      : 'Save to Central DB ($selectedCount)',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
