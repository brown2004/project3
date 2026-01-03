import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LogService {
  static const String _keyLogs = 'activity_logs';
  static const String _keyLastClearDate = 'last_clear_date';

  // Lưu danh sách log vào storage
  Future<void> saveLogs(List<Map<String, dynamic>> logs) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Chuyển list thành JSON string
    String jsonLogs = jsonEncode(logs);
    await prefs.setString(_keyLogs, jsonLogs);
    
    print("💾 Đã lưu ${logs.length} log vào storage");
  }

  // Lấy danh sách log từ storage
  Future<List<Map<String, dynamic>>> loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Kiểm tra xem có phải ngày mới không, nếu có thì xóa log cũ
    await _clearLogsIfNewDay(prefs);
    
    String? jsonLogs = prefs.getString(_keyLogs);
    
    if (jsonLogs == null || jsonLogs.isEmpty) {
      print("📭 Không có log nào trong storage");
      return [];
    }
    
    try {
      List<dynamic> decoded = jsonDecode(jsonLogs);
      List<Map<String, dynamic>> logs = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      print("📂 Đã load ${logs.length} log từ storage");
      return logs;
    } catch (e) {
      print("❌ Lỗi khi load logs: $e");
      return [];
    }
  }

  // Thêm một log mới
  Future<void> addLog(Map<String, dynamic> log) async {
    List<Map<String, dynamic>> logs = await loadLogs();
    logs.insert(0, log); // Thêm vào đầu danh sách
    
    // Giới hạn chỉ lưu 100 log gần nhất để tránh quá tải
    if (logs.length > 100) {
      logs = logs.sublist(0, 100);
    }
    
    await saveLogs(logs);
  }

  // Xóa tất cả log
  Future<void> clearAllLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLogs);
    print("🗑️ Đã xóa toàn bộ log");
  }

  // Kiểm tra và xóa log nếu là ngày mới
  Future<void> _clearLogsIfNewDay(SharedPreferences prefs) async {
    String today = _getTodayDateString();
    String? lastClearDate = prefs.getString(_keyLastClearDate);
    
    if (lastClearDate != today) {
      // Ngày mới => Xóa log cũ
      await prefs.remove(_keyLogs);
      await prefs.setString(_keyLastClearDate, today);
      print("🆕 Ngày mới: $today - Đã xóa log cũ");
    }
  }

  // Lấy chuỗi ngày hôm nay (format: yyyy-MM-dd)
  String _getTodayDateString() {
    DateTime now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }
}