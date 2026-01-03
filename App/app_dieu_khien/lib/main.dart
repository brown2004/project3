import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/mqtt_service.dart';
import 'services/log_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Lock Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const LoginPage(),
    );
  }
}

// ================== MIXIN XỬ LÝ FEEDBACK ==================
mixin MqttFeedbackHandler<T extends StatefulWidget> on State<T> {
  final MqttService mqtt = MqttService();

  Future<Map<String, dynamic>?> sendCommandWithFeedback(
    BuildContext context, 
    String command, 
    String expectedAction,
    {int timeoutSeconds = 5}
  ) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    var responseFuture = mqtt.logStream.firstWhere((logData) {
      String incoming = logData['action'].toString();
      return incoming == expectedAction;
    }).timeout(Duration(seconds: timeoutSeconds));

    await Future.delayed(const Duration(milliseconds: 50));
    mqtt.sendCommand(command);

    try {
      var response = await responseFuture;

      if (!mounted) return null;
      Navigator.pop(context); 

      if (response['success'] == true) {
        return response; 
      } else {
        String msg = response['message'] ?? "That bai";
        if (msg.contains("ton tai")) msg = "The nay da ton tai";
        if (msg.contains("du 10 the")) msg = "Bo nho day";
        _showSnack(context, "Loi: $msg", Colors.orange);
        return null;
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnack(context, "Khong phan hoi (Timeout)", Colors.red);
      }
      return null;
    }
  }

  void _showSnack(BuildContext context, String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, duration: const Duration(seconds: 2)),
    );
  }
}

// ================== LOGIN PAGE ==================
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security_rounded, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 20),
              const Text("SMART LOCK ADMIN", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
              const SizedBox(height: 40),
              const TextField(decoration: InputDecoration(labelText: "Tai khoan", prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
              const SizedBox(height: 15),
              const TextField(decoration: InputDecoration(labelText: "Mat khau", prefixIcon: Icon(Icons.lock), border: OutlineInputBorder()), obscureText: true),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardPage())),
                  child: const Text("DANG NHAP", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================== DASHBOARD PAGE ==================
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with MqttFeedbackHandler {
  bool _isLocked = true;
  final List<Map<String, dynamic>> _logs = [];
  final LogService _logService = LogService();
  
  @override
  void initState() {
    super.initState();
    _loadLogsFromStorage();
    _connectAndSync();
  }

  void _loadLogsFromStorage() async {
    List<Map<String, dynamic>> savedLogs = await _logService.loadLogs();
    if (mounted) {
      setState(() {
        _logs.addAll(savedLogs);
      });
    }
  }

  void _connectAndSync() async {
    await mqtt.connect();
    mqtt.sendCommand("SYNC_REQ");
    
    // === LẮNG NGHE LOG ===
    mqtt.logStream.listen((logData) async { // Thêm async
      if (!mounted) return;
      
      String actionStr = logData['action']?.toString() ?? "";
      
      // 1. Lọc bỏ tin rác
      if (actionStr == "SYNC_REQ" || 
          actionStr == "SCAN_NEW_RFID" || 
          actionStr == "CANCEL_SCAN" ||
          actionStr == "SYNC_PIN" ||
          actionStr == "SYNC_CARDS") {
        return; 
      }

      if (logData.containsKey('message') && !logData.containsKey('user')) {
        return;
      }

      // 2. Lọc trùng
      if (_isLocked == false) { 
        String actLower = actionStr.toLowerCase();
        if (actLower.contains('mo') || actLower.contains('unlock') || actLower.contains('open')) {
          return; 
        }
      }

      String userStr = logData['user']?.toString() ?? "System";
      
      // === [SỬA LẠI] LOGIC HIỂN THỊ TÊN CHUẨN ===
      if (userStr.startsWith("RFID:")) {
        try {
          // Lấy UID bằng cách cắt chuỗi từ ký tự thứ 5 trở đi
          // Ví dụ: "RFID:47:60:3E:05" -> "47:60:3E:05"
          String uid = userStr.substring(5).trim(); 
          
          final prefs = await SharedPreferences.getInstance();
          String? savedName = prefs.getString('card_name_$uid'); 
          
          if (savedName != null && savedName.isNotEmpty) {
            userStr = savedName; // Hiển thị tên người dùng
          } else {
            userStr = "Thẻ lạ: $uid"; // Hiển thị mã nếu chưa lưu
          }
        } catch (e) {
          print("Lỗi parse tên thẻ: $e");
        }
      }
      // ==========================================

      bool isSuccess = logData['success'] == true;

      Map<String, dynamic> newLog = {
        "time": _formatTime(DateTime.now()),
        "user": userStr,
        "action": actionStr,
        "success": isSuccess
      };
      
      setState(() {
        _logs.insert(0, newLog);
      });
      
      _logService.addLog(newLog);
    });

    mqtt.lockStateStream.listen((locked) {
      if(mounted) setState(() => _isLocked = locked);
    });
  }

  String _formatTime(DateTime time) => "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";

  void _toggleLock() async {
    String command = _isLocked ? "UNLOCK" : "LOCK";
    var result = await sendCommandWithFeedback(context, command, command);
    
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Thanh cong: ${result['message']}"), 
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard Dieu Khien"), centerTitle: true),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isLocked ? [Colors.redAccent, Colors.orangeAccent] : [Colors.green, Colors.teal],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_isLocked ? "DANG KHOA" : "DA MO", 
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(_isLocked ? "An toan" : "Canh bao: Cua dang mo", 
                        style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle),
                  child: IconButton(
                    iconSize: 40,
                    color: Colors.white,
                    icon: Icon(_isLocked ? Icons.lock : Icons.lock_open),
                    onPressed: _toggleLock,
                  ),
                )
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Lich su hoat dong", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () async {
                    bool? confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text("Xoa lich su"),
                        content: const Text("Ban co chac muon xoa toan bo lich su?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("Huy")),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text("Xoa"),
                          ),
                        ],
                      ),
                    );
                    
                    if (confirm == true) {
                      await _logService.clearAllLogs();
                      setState(() => _logs.clear());
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text("Xoa", style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),

          Expanded(
            child: _logs.isEmpty
                ? const Center(child: Text("Chua co hoat dong nao", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Icon(
                            log['success'] ? Icons.check_circle : Icons.warning,
                            color: log['success'] ? Colors.green : Colors.red,
                          ),
                          title: Text(log['action'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("${log['user']}"),
                          trailing: Text(log['time'], style: const TextStyle(color: Colors.grey)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ================== RFID MANAGE PAGE ==================
class RfidManagePage extends StatefulWidget {
  const RfidManagePage({super.key});

  @override
  State<RfidManagePage> createState() => _RfidManagePageState();
}

class _RfidManagePageState extends State<RfidManagePage> with MqttFeedbackHandler {
  List<Map<String, String>> rfids = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _connectAndSync();
  }

  void _connectAndSync() async {
    await mqtt.connect();
    mqtt.sendCommand("SYNC_REQ"); 
    
    mqtt.logStream.listen((logData) async { // Thêm async
      if (logData['type'] == 'SYNC_CARDS' && mounted) {
        List<dynamic> cards = logData['cards'] ?? [];
        
        // Load tên thẻ từ bộ nhớ máy
        final prefs = await SharedPreferences.getInstance();
        List<Map<String, String>> tempRfids = [];

        for (var cardId in cards) {
          String uid = cardId.toString();
          // Lấy tên đã lưu, nếu không có thì ghi "Thẻ chưa đặt tên"
          String name = prefs.getString('card_name_$uid') ?? "The chua dat ten";
          tempRfids.add({
            "name": name,
            "id": uid
          });
        }

        setState(() {
          rfids = tempRfids;
          _isLoading = false;
        });
      }
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    });
  }

  void _addNewCardProcess() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Dang cho quet the..."),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("1. Cham the vao khoa", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text("2. Tu huy sau 10 giay", style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              mqtt.sendCommand("CANCEL_SCAN");
            },
            child: const Text("Huy", style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );

    mqtt.sendCommand("SCAN_NEW_RFID");

    try {
      String rfidCode = await mqtt.rfidStream.first.timeout(const Duration(seconds: 10));

      if (!mounted) return;
      Navigator.pop(context);
      _showNameInput(rfidCode);

    } on TimeoutException {
      if (!mounted) return;
      Navigator.pop(context);
      mqtt.sendCommand("CANCEL_SCAN"); 
      _showSnack(context, "Het thoi gian! Da huy che do them.", Colors.red);
    }
  }

  void _showNameInput(String code) {
    TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog( 
        title: const Text("The moi phat hien!"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Ma the: $code", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: "Ten chu the", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Huy")),
          
          ElevatedButton(
            onPressed: () async {
              String name = controller.text.trim();
              if (name.isEmpty) return;
              
              Navigator.pop(dialogContext);
              
              var result = await sendCommandWithFeedback(
                context, 
                "SAVE_CARD:$code:$name", // Gửi lệnh lưu
                "SAVE_CARD"
              );

              if (result != null) {
                // === LƯU TÊN VÀO BỘ NHỚ ===
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('card_name_$code', name);
                // ==========================

                setState(() {
                  rfids.add({"name": name, "id": code});
                });
                if(mounted) _showSnack(context, "Thanh cong: ${result['message']}", Colors.green);
              }
            },
            child: const Text("Luu"),
          ),
        ],
      ),
    );
  }

  void _deleteCard(int index) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xac nhan xoa"),
        content: Text("Xoa the ${rfids[index]['name']}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Huy")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Xoa"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      String uidToDelete = rfids[index]['id']!;
      
      var result = await sendCommandWithFeedback(
        context, 
        "DELETE:$uidToDelete", 
        "DELETE"
      );

      if (result != null) {
        // Xóa tên khỏi bộ nhớ
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('card_name_$uidToDelete');

        setState(() => rfids.removeAt(index));
        if(mounted) _showSnack(context, "Thanh cong: ${result['message']}", Colors.green);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quan ly the RFID")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : rfids.isEmpty
              ? const Center(child: Text("Chua co the nao. Nhan + de them.", style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rfids.length,
                  itemBuilder: (context, index) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.credit_card)),
                      title: Text(rfids[index]['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("ID: ${rfids[index]['id']!}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteCard(index),
                      ),
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewCardProcess,
        icon: const Icon(Icons.add),
        label: const Text("Them the"),
      ),
    );
  }
}

// ================== CHANGE PASSWORD PAGE ==================
class ChangeLockPasswordPage extends StatefulWidget {
  const ChangeLockPasswordPage({super.key});
  @override
  State<ChangeLockPasswordPage> createState() => _ChangeLockPasswordPageState();
}

class _ChangeLockPasswordPageState extends State<ChangeLockPasswordPage> with MqttFeedbackHandler {
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  void _changePin() async {
    String newPin = _newPinController.text;
    if (newPin != _confirmPinController.text) {
      _showSnack(context, "Ma PIN xac nhan khong khop!", Colors.orange);
      return;
    }
    if (newPin.length < 4 || newPin.length > 8) {
      _showSnack(context, "PIN phai tu 4-8 so!", Colors.orange);
      return;
    }

    var result = await sendCommandWithFeedback(context, "CHANGE_PIN:$newPin", "CHANGE_PIN");

    if (result != null) {
      if (mounted) {
        _showSnack(context, "Thanh cong: ${result['message']}", Colors.green);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Doi ma PIN")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Card(
              color: Colors.orangeAccent,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text("Ma PIN nay dung de nhap truc tiep tren ban phim cua khoa (4-8 so).", style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
            TextField(controller: _newPinController, decoration: const InputDecoration(labelText: "PIN moi", border: OutlineInputBorder()), keyboardType: TextInputType.number, maxLength: 8),
            const SizedBox(height: 15),
            TextField(controller: _confirmPinController, decoration: const InputDecoration(labelText: "Nhap lai PIN", border: OutlineInputBorder()), keyboardType: TextInputType.number, maxLength: 8),
            const SizedBox(height: 30),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _changePin, child: const Text("LUU THAY DOI"))),
          ],
        ),
      ),
    );
  }
}

// ================== APP DRAWER ==================
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const UserAccountsDrawerHeader(
            accountName: Text("Admin Gia Dinh"),
            accountEmail: Text("admin@smartlock.com"),
            currentAccountPicture: CircleAvatar(child: Icon(Icons.person, size: 50)),
            decoration: BoxDecoration(color: Colors.blueAccent),
          ),
          ListTile(leading: const Icon(Icons.dashboard), title: const Text('Dashboard'), onTap: () => Navigator.pop(context)),
          ListTile(
            leading: const Icon(Icons.nfc), title: const Text('Quan ly the RFID'),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => const RfidManagePage())); },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.password), title: const Text('Doi mat khau khoa'),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => const ChangeLockPasswordPage())); },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Dang xuat', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginPage())),
          ),
        ],
      ),
    );
  }
}