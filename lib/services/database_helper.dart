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
      version: 2,
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

  Future<int> startSession(int courseId, String roomNumber) async {
    Database db = await database;
    return await db.insert('sessions', {
      'courseId': courseId,
      'roomNumber': roomNumber,
      'pin': '',
      'startTime': DateTime.now().toIso8601String(),
      'isActive': 1,
    });
  }

  /// Updates the rolling PIN for an active session (called every 30 seconds).
  Future<void> updateSessionPin(int sessionId, String pin) async {
    Database db = await database;
    await db.update(
      'sessions',
      {'pin': pin},
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
}
