import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'attendance_system_v2.db');
    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future _onCreate(Database db, int version) async {
    await _createAllTables(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add device_registry table for global cross-session anti-proxy tracking
      await db.execute('''
        CREATE TABLE IF NOT EXISTS device_registry(
          deviceId TEXT PRIMARY KEY,
          regNumber TEXT NOT NULL,
          firstSeenAt TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE sessions ADD COLUMN codeDuration INTEGER DEFAULT 60');
      } catch (_) {}
    }
    if (oldVersion < 4) {
      await _createCentralStudentsTable(db);
      // Auto-migrate any existing roster entries into central_students
      try {
        final existingRosters = await db.rawQuery(
          'SELECT DISTINCT regNumber, name FROM rosters WHERE regNumber IS NOT NULL AND regNumber != ""',
        );
        final now = DateTime.now().toIso8601String();
        for (final row in existingRosters) {
          final reg = (row['regNumber'] as String).trim();
          final name = (row['name'] as String?)?.trim() ?? reg;
          final session = deriveSessionFromRegNumber(reg);
          await db.insert(
            'central_students',
            {
              'regNumber': reg,
              'name': name.isEmpty ? reg : name,
              'session': session,
              'createdAt': now,
              'updatedAt': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      } catch (_) {}
    }
  }

  static Future<void> _createCentralStudentsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS central_students(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        regNumber TEXT UNIQUE NOT NULL,
        name TEXT NOT NULL,
        session TEXT NOT NULL,
        department TEXT,
        email TEXT,
        phone TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createAllTables(Database db) async {
    // Teacher Data
    await db.execute('''
      CREATE TABLE courses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        code TEXT UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE rosters(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        courseId INTEGER,
        regNumber TEXT,
        name TEXT,
        boundDeviceId TEXT,
        FOREIGN KEY (courseId) REFERENCES courses (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        courseId INTEGER,
        roomNumber TEXT,
        pin TEXT,
        startTime TEXT,
        endTime TEXT,
        isActive INTEGER,
        codeDuration INTEGER DEFAULT 60,
        FOREIGN KEY (courseId) REFERENCES courses (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId INTEGER,
        regNumber TEXT,
        timestamp TEXT,
        deviceId TEXT,
        FOREIGN KEY (sessionId) REFERENCES sessions (id)
      )
    ''');

    // Central Students Directory
    await _createCentralStudentsTable(db);

    // Student Data (Simple local storage for their own ID)
    await db.execute('''
      CREATE TABLE student_config(
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Global device registry: tracks which physical device maps to which reg number
    // Used across all sessions to detect proxy attempts
    await db.execute('''
      CREATE TABLE device_registry(
        deviceId TEXT PRIMARY KEY,
        regNumber TEXT NOT NULL,
        firstSeenAt TEXT NOT NULL
      )
    ''');
  }

  // ─── Central Student Database Operations ──────────────────────────────────

  /// Derives the academic session (e.g. "2023-24") from registration number prefix.
  /// Example: "2023831004" -> "2023-24".
  static String deriveSessionFromRegNumber(String reg) {
    final clean = reg.trim();
    if (clean.length >= 4) {
      final yearPrefix = clean.substring(0, 4);
      final year = int.tryParse(yearPrefix);
      if (year != null && year >= 1990 && year <= 2099) {
        final nextYear = (year + 1) % 100;
        final nextYearStr = nextYear < 10 ? '0$nextYear' : '$nextYear';
        return '$year-$nextYearStr';
      }
    }
    // Also check for 2-digit year prefix like 23-831-004
    final twoDigitMatch = RegExp(r'^(\d{2})[-_/\s]?\d+').firstMatch(clean);
    if (twoDigitMatch != null) {
      final y2 = int.tryParse(twoDigitMatch.group(1)!);
      if (y2 != null && y2 >= 15 && y2 <= 35) {
        final fullYear = 2000 + y2;
        final nextYear = (fullYear + 1) % 100;
        final nextYearStr = nextYear < 10 ? '0$nextYear' : '$nextYear';
        return '$fullYear-$nextYearStr';
      }
    }
    return 'General';
  }

  /// Inserts or updates a central student profile.
  Future<int> insertOrUpdateCentralStudent({
    required String regNumber,
    required String name,
    String? session,
    String? department,
    String? email,
    String? phone,
  }) async {
    Database db = await database;
    final cleanReg = regNumber.trim();
    final cleanName = name.trim();
    final derivedSession = (session != null && session.trim().isNotEmpty)
        ? session.trim()
        : deriveSessionFromRegNumber(cleanReg);
    final now = DateTime.now().toIso8601String();

    return await db.rawInsert('''
      INSERT INTO central_students(regNumber, name, session, department, email, phone, createdAt, updatedAt)
      VALUES(?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(regNumber) DO UPDATE SET
        name = excluded.name,
        session = excluded.session,
        department = coalesce(excluded.department, central_students.department),
        email = coalesce(excluded.email, central_students.email),
        phone = coalesce(excluded.phone, central_students.phone),
        updatedAt = excluded.updatedAt
    ''', [
      cleanReg,
      cleanName,
      derivedSession,
      department?.trim(),
      email?.trim(),
      phone?.trim(),
      now,
      now,
    ]);
  }

  /// Bulk inserts/updates students in a single transaction.
  Future<int> bulkInsertCentralStudents(List<Map<String, String>> students) async {
    Database db = await database;
    int count = 0;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final s in students) {
        final reg = (s['regNumber'] ?? '').trim();
        final name = (s['name'] ?? '').trim();
        if (reg.isEmpty) continue;
        final studentName = name.isEmpty ? reg : name;
        final session = (s['session'] != null && s['session']!.trim().isNotEmpty)
            ? s['session']!.trim()
            : deriveSessionFromRegNumber(reg);

        batch.rawInsert('''
          INSERT INTO central_students(regNumber, name, session, department, email, phone, createdAt, updatedAt)
          VALUES(?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(regNumber) DO UPDATE SET
            name = excluded.name,
            session = excluded.session,
            updatedAt = excluded.updatedAt
        ''', [
          reg,
          studentName,
          session,
          s['department']?.trim(),
          s['email']?.trim(),
          s['phone']?.trim(),
          now,
          now,
        ]);
        count++;
      }
      await batch.commit(noResult: true);
    });
    return count;
  }

  /// Retrieves central students with optional session filter, search query, and sorting.
  Future<List<Map<String, dynamic>>> getCentralStudents({
    String? sessionFilter,
    String? searchQuery,
    String sortBy = 'regNumber_asc', // 'regNumber_asc', 'regNumber_desc', 'name_asc', 'name_desc'
  }) async {
    Database db = await database;
    List<String> whereClauses = [];
    List<dynamic> whereArgs = [];

    if (sessionFilter != null && sessionFilter.isNotEmpty && sessionFilter != 'All') {
      whereClauses.add('session = ?');
      whereArgs.add(sessionFilter);
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      whereClauses.add('(regNumber LIKE ? OR name LIKE ?)');
      final pattern = '%${searchQuery.trim()}%';
      whereArgs.add(pattern);
      whereArgs.add(pattern);
    }

    String whereSql = whereClauses.isNotEmpty ? 'WHERE ${whereClauses.join(' AND ')}' : '';

    String orderBySql;
    switch (sortBy) {
      case 'regNumber_desc':
        orderBySql = 'ORDER BY regNumber DESC';
        break;
      case 'name_asc':
        orderBySql = 'ORDER BY name COLLATE NOCASE ASC';
        break;
      case 'name_desc':
        orderBySql = 'ORDER BY name COLLATE NOCASE DESC';
        break;
      case 'regNumber_asc':
      default:
        orderBySql = 'ORDER BY regNumber ASC';
        break;
    }

    return await db.rawQuery('''
      SELECT * FROM central_students
      $whereSql
      $orderBySql
    ''', whereArgs);
  }

  /// Gets all distinct sessions present in the central database with student counts.
  Future<List<Map<String, dynamic>>> getDistinctSessions() async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT session, COUNT(*) as studentCount
      FROM central_students
      GROUP BY session
      ORDER BY session DESC
    ''');
  }

  /// Updates an existing central student record.
  Future<int> updateCentralStudent({
    required int id,
    required String regNumber,
    required String name,
    required String session,
  }) async {
    Database db = await database;
    final now = DateTime.now().toIso8601String();
    return await db.update(
      'central_students',
      {
        'regNumber': regNumber.trim(),
        'name': name.trim(),
        'session': session.trim(),
        'updatedAt': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Deletes a central student by ID.
  Future<int> deleteCentralStudent(int id) async {
    Database db = await database;
    return await db.delete('central_students', where: 'id = ?', whereArgs: [id]);
  }

  /// Total count of central students.
  Future<int> getCentralStudentsCount() async {
    Database db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as count FROM central_students');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  /// Enrolls a list of central students (by regNumbers) into a course roster.
  Future<int> enrollStudentsFromCentralDb(int courseId, List<String> regNumbers) async {
    Database db = await database;
    int enrolledCount = 0;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final reg in regNumbers) {
        // Fetch student name from central_students if exists
        final studentRows = await txn.query(
          'central_students',
          columns: ['name'],
          where: 'regNumber = ?',
          whereArgs: [reg],
        );
        String? name;
        if (studentRows.isNotEmpty) {
          name = studentRows.first['name'] as String?;
        }

        batch.insert(
          'rosters',
          {
            'courseId': courseId,
            'regNumber': reg,
            'name': name ?? reg,
            'boundDeviceId': null,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        enrolledCount++;
      }
      await batch.commit(noResult: true);
    });
    return enrolledCount;
  }

  /// Returns set of regNumbers already enrolled in a given course.
  Future<Set<String>> getEnrolledRegNumbersForCourse(int courseId) async {
    Database db = await database;
    final rows = await db.query(
      'rosters',
      columns: ['regNumber'],
      where: 'courseId = ?',
      whereArgs: [courseId],
    );
    return rows.map((r) => (r['regNumber'] as String).trim()).toSet();
  }

  // ─── Course Operations ────────────────────────────────────────────────────

  Future<int> insertCourse(String name, String code) async {
    Database db = await database;
    return await db.insert(
      'courses',
      {'name': name, 'code': code},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<Map<String, dynamic>>> getCourses() async {
    Database db = await database;
    return await db.query('courses');
  }

  // ─── Roster Operations ────────────────────────────────────────────────────

  /// [name] is optional — teacher may upload reg numbers only.
  Future<void> insertRosterEntry(int courseId, String regNumber, String? name) async {
    Database db = await database;
    await db.insert(
      'rosters',
      {
        'courseId': courseId,
        'regNumber': regNumber,
        'name': name,
        'boundDeviceId': null,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getRosterForCourse(int courseId) async {
    Database db = await database;
    return await db.query('rosters', where: 'courseId = ?', whereArgs: [courseId]);
  }

  /// Binds a physical device to a reg number within a specific course.
  Future<void> bindDeviceToStudent(int courseId, String regNumber, String deviceId) async {
    Database db = await database;
    await db.update(
      'rosters',
      {'boundDeviceId': deviceId},
      where: 'courseId = ? AND regNumber = ?',
      whereArgs: [courseId, regNumber],
    );
  }

  // ─── Device Registry (Anti-Proxy) ────────────────────────────────────────

  /// Registers a device globally for the first time.
  /// Call this after successfully binding a device on first attendance.
  Future<void> registerDevice(String deviceId, String regNumber) async {
    Database db = await database;
    await db.insert(
      'device_registry',
      {
        'deviceId': deviceId,
        'regNumber': regNumber,
        'firstSeenAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore, // Don't overwrite existing entry
    );
  }

  /// Returns true if the deviceId has been seen before with a DIFFERENT regNumber.
  /// This indicates a proxy attempt (one phone submitting for multiple students).
  Future<bool> checkDeviceFraud(String deviceId, String regNumber) async {
    Database db = await database;
    final rows = await db.query(
      'device_registry',
      where: 'deviceId = ? AND regNumber != ?',
      whereArgs: [deviceId, regNumber],
    );
    return rows.isNotEmpty;
  }

  // ─── Session Operations ───────────────────────────────────────────────────

  Future<int> startSession(int courseId, String roomNumber, {int codeDuration = 60}) async {
    Database db = await database;
    return await db.insert('sessions', {
      'courseId': courseId,
      'roomNumber': roomNumber,
      'pin': '',
      'startTime': DateTime.now().toIso8601String(),
      'isActive': 1,
      'codeDuration': codeDuration,
    });
  }

  /// Updates the rolling PIN for an active session.
  Future<void> updateSessionPin(int sessionId, String pin) async {
    Database db = await database;
    await db.update(
      'sessions',
      {'pin': pin},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Updates the code duration timer (in seconds) for a session.
  Future<void> updateSessionDuration(int sessionId, int codeDuration) async {
    Database db = await database;
    await db.update(
      'sessions',
      {'codeDuration': codeDuration},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> endSession(int id) async {
    Database db = await database;
    await db.update(
      'sessions',
      {'isActive': 0, 'endTime': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getSessionsWithCourse() async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT s.*, c.name as courseName, c.code as courseCode 
      FROM sessions s 
      JOIN courses c ON s.courseId = c.id 
      ORDER BY s.id DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT s.*, c.name as courseName, c.code as courseCode,
        (SELECT COUNT(*) FROM attendance a WHERE a.sessionId = s.id) as presentCount,
        (SELECT COUNT(*) FROM rosters r WHERE r.courseId = s.courseId) as enrolledCount
      FROM sessions s
      JOIN courses c ON s.courseId = c.id
      WHERE s.isActive = 1
      ORDER BY s.id DESC
    ''');
  }

  Future<Map<String, dynamic>?> getSessionById(int sessionId) async {
    Database db = await database;
    final results = await db.rawQuery('''
      SELECT s.*, c.name as courseName, c.code as courseCode
      FROM sessions s
      JOIN courses c ON s.courseId = c.id
      WHERE s.id = ?
    ''', [sessionId]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> clearAttendanceForSession(int sessionId) async {
    Database db = await database;
    await db.delete('attendance', where: 'sessionId = ?', whereArgs: [sessionId]);
  }

  // ─── Attendance Operations ────────────────────────────────────────────────

  Future<int> markAttendance(int sessionId, String regNumber, String deviceId) async {
    Database db = await database;
    return await db.insert('attendance', {
      'sessionId': sessionId,
      'regNumber': regNumber,
      'timestamp': DateTime.now().toIso8601String(),
      'deviceId': deviceId,
    });
  }

  Future<List<Map<String, dynamic>>> getAttendanceForSession(int sessionId) async {
    Database db = await database;
    // Scope the roster JOIN to only the course that this session belongs to,
    // so we get the right name even if the same reg number appears in other courses.
    return await db.rawQuery('''
      SELECT a.*, r.name 
      FROM attendance a 
      LEFT JOIN rosters r 
        ON a.regNumber = r.regNumber 
        AND r.courseId = (SELECT courseId FROM sessions WHERE id = ?)
      WHERE a.sessionId = ?
    ''', [sessionId, sessionId]);
  }

  // ─── Student Config ───────────────────────────────────────────────────────

  Future<void> setConfig(String key, String value) async {
    Database db = await database;
    await db.insert(
      'student_config',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getConfig(String key) async {
    Database db = await database;
    List<Map<String, dynamic>> maps =
        await db.query('student_config', where: 'key = ?', whereArgs: [key]);
    if (maps.isNotEmpty) return maps.first['value'] as String;
    return null;
  }

  // ─── Attendance Analytics ─────────────────────────────────────────────────

  /// Returns per-course attendance stats for a student.
  /// Each row: courseId, courseCode, courseName, totalSessions, attended, percentage
  Future<List<Map<String, dynamic>>> getStudentAttendanceStats(String regNumber) async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT
        c.id        AS courseId,
        c.code      AS courseCode,
        c.name      AS courseName,
        COUNT(DISTINCT s.id)                                          AS totalSessions,
        COUNT(DISTINCT a.sessionId)                                   AS attended,
        ROUND(
          100.0 * COUNT(DISTINCT a.sessionId) / MAX(COUNT(DISTINCT s.id), 1),
          1
        )                                                             AS percentage
      FROM courses c
      INNER JOIN rosters  r ON r.courseId = c.id AND r.regNumber = ?
      INNER JOIN sessions s ON s.courseId = c.id
      LEFT JOIN  attendance a ON a.sessionId = s.id AND a.regNumber = ?
      GROUP BY c.id
      ORDER BY c.code
    ''', [regNumber, regNumber]);
  }

  /// Returns list of enrolled students who did NOT mark attendance in a given session.
  /// Each row: regNumber, name
  Future<List<Map<String, dynamic>>> getAbsenteesForSession(int sessionId, int courseId) async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT r.regNumber, r.name
      FROM rosters r
      WHERE r.courseId = ?
        AND r.regNumber NOT IN (
          SELECT a.regNumber FROM attendance a WHERE a.sessionId = ?
        )
      ORDER BY r.name
    ''', [courseId, sessionId]);
  }

  /// Returns per-student attendance summary for a whole course.
  /// Each row: regNumber, name, attended, totalSessions, percentage
  Future<List<Map<String, dynamic>>> getCourseStudentReport(int courseId) async {
    Database db = await database;
    return await db.rawQuery('''
      SELECT
        r.regNumber,
        r.name,
        COUNT(DISTINCT s.id)              AS totalSessions,
        COUNT(DISTINCT a.sessionId)       AS attended,
        ROUND(
          100.0 * COUNT(DISTINCT a.sessionId) / MAX(COUNT(DISTINCT s.id), 1),
          1
        )                                 AS percentage
      FROM rosters r
      CROSS JOIN (SELECT id FROM sessions WHERE courseId = ?) s
      LEFT JOIN attendance a ON a.sessionId = s.id AND a.regNumber = r.regNumber
      WHERE r.courseId = ?
      GROUP BY r.regNumber
      ORDER BY percentage ASC
    ''', [courseId, courseId]);
  }

  /// Returns a per-session summary for a course with present count and enrolled count.
  /// Each row: sessionId, startTime, roomNumber, presentCount, enrolledCount
  Future<List<Map<String, dynamic>>> getCourseSessionSummaries(int courseId) async {
    Database db = await database;
    final enrolledCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM rosters WHERE courseId = ?', [courseId]),
    ) ?? 0;
    final rows = await db.rawQuery('''
      SELECT
        s.id         AS sessionId,
        s.startTime,
        s.endTime,
        s.roomNumber,
        COUNT(a.id)  AS presentCount
      FROM sessions s
      LEFT JOIN attendance a ON a.sessionId = s.id
      WHERE s.courseId = ?
      GROUP BY s.id
      ORDER BY s.id DESC
    ''', [courseId]);

    // Inject enrolledCount into each row (SQLite cross-query workaround)
    return rows.map((r) => {...r, 'enrolledCount': enrolledCount}).toList();
  }
}
