import 'package:flutter/material.dart';
import 'dart:async';
import 'services/mqtt_service.dart';

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
        // cardTheme: const CardTheme(surfaceTintColor: Colors.white), // <--- NẾU VẪN LỖI THÌ XÓA HẲN DÒNG NÀY ĐI
      ),
      // Nếu xóa dòng trên mà vẫn lỗi, hãy thử thay bằng:
      // cardTheme: const CardThemeData(surfaceTintColor: Colors.white), 
      // Nhưng tốt nhất là xóa đi cho nhẹ nợ.
      
      home: const LoginPage(),
    );
  }
}

// ================== HELPER MIXIN (PHIÊN BẢN FINAL) ==================
mixin MqttFeedbackHandler<T extends StatefulWidget> on State<T> {
  final MqttService mqtt = MqttService();

  Future<Map<String, dynamic>?> sendCommandWithFeedback(
    BuildContext context, 
    String command, 
    String expectedAction,
    {int timeoutSeconds = 5}
  ) async {
    // 1. Hiện Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );

    print("🟡 [APP] Gửi lệnh: $command");

    // 2. GIĂNG BẪY (LẮNG NGHE) TRƯỚC
    var responseFuture = mqtt.logStream.firstWhere((logData) {
      // In ra xem App đang nghe thấy cái gì
      print("👀 [LISTENER] Nghe thấy: $logData");
      
      // So sánh Action
      String incoming = logData['action'].toString();
      bool match = incoming == expectedAction;
      
      if (match) print("✅ [LISTENER] Bắt được tin nhắn khớp!");
      return match;
    }).timeout(Duration(seconds: timeoutSeconds));

    // 3. GỬI LỆNH (Delay 50ms để chắc chắn Listener đã bật)
    await Future.delayed(const Duration(milliseconds: 50));
    mqtt.sendCommand(command);

    try {
      // 4. CHỜ KẾT QUẢ
      var response = await responseFuture;

      if (!mounted) return null;
      Navigator.pop(context); // Tắt loading NGAY

      // 5. XỬ LÝ
      if (response['success'] == true) {
        return response; 
      } else {
        // Xử lý lỗi từ ESP32 gửi về (Ví dụ: Thẻ đã tồn tại)
        String msg = response['message'] ?? "Thất bại";
        print("🟠 [APP] ESP32 báo lỗi: $msg");
        
        // Việt hóa thông báo cho thân thiện
        if (msg.contains("ton tai")) msg = "Thẻ này đã tồn tại!";
        if (msg.contains("du 10 the")) msg = "Bộ nhớ đầy!";
        
        _showSnack(context, "⚠️ $msg", Colors.orange);
        return null;
      }

    } catch (e) {
      print("🔴 [APP] Lỗi hoặc Timeout: $e");
      if (mounted) {
        Navigator.pop(context); // Tắt loading
        _showSnack(context, "⚠️ Không phản hồi (Timeout)!", Colors.red);
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

// ================== LOGIN ==================
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
              const TextField(decoration: InputDecoration(labelText: "Tài khoản", prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
              const SizedBox(height: 15),
              const TextField(decoration: InputDecoration(labelText: "Mật khẩu", prefixIcon: Icon(Icons.lock), border: OutlineInputBorder()), obscureText: true),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardPage())),
                  child: const Text("ĐĂNG NHẬP", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================== DASHBOARD ==================
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with MqttFeedbackHandler {
  bool _isLocked = true;
  final List<Map<String, dynamic>> _logs = [];
  
  @override
  void initState() {
    super.initState();
    _connectAndSync();
  }

  void _connectAndSync() async {
    await mqtt.connect();
    mqtt.sendCommand("SYNC_REQ");
    
    mqtt.logStream.listen((logData) {
      if (!mounted) return;
      if (logData.containsKey('user')) {
        setState(() {
          _logs.insert(0, {
            "time": _formatTime(DateTime.now()),
            "user": logData['user'],
            "action": logData['action'],
            "success": logData['success'] ?? false
          });
        });
      }
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
      setState(() {
        _isLocked = !_isLocked;
        _logs.insert(0, {
          "time": _formatTime(DateTime.now()),
          "user": "Admin App",
          "action": _isLocked ? "Đã Khóa" : "Đã Mở",
          "success": true
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ ${result['message']}"), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Dashboard Điều Khiển"), centerTitle: true),
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
                    Text(_isLocked ? "ĐANG KHÓA" : "ĐÃ MỞ", 
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(_isLocked ? "An toàn" : "Cảnh báo: Cửa đang mở", 
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

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Align(alignment: Alignment.centerLeft, child: Text("Lịch sử hoạt động", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ),

          Expanded(
            child: _logs.isEmpty
                ? const Center(child: Text("Chưa có hoạt động nào", style: TextStyle(color: Colors.grey)))
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

// ================== QUẢN LÝ RFID ==================
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
    
    mqtt.logStream.listen((logData) {
      if (logData['type'] == 'SYNC_CARDS' && mounted) {
        List<dynamic> cards = logData['cards'] ?? [];
        setState(() {
          rfids.clear();
          for (int i = 0; i < cards.length; i++) {
            rfids.add({
              "name": "Thẻ ${i + 1}",
              "id": cards[i].toString()
            });
          }
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
        title: const Text("Đang chờ quét thẻ..."),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text("1. Chạm thẻ vào khóa", style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 5),
            Text("2. Tự hủy sau 10 giây", style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              mqtt.sendCommand("CANCEL_SCAN");
            },
            child: const Text("Hủy", style: TextStyle(color: Colors.red)),
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
      _showSnack(context, "Hết thời gian! Đã hủy chế độ thêm.", Colors.red);
    }
  }

  void _showNameInput(String code) {
    TextEditingController controller = TextEditingController();
    
    showDialog(
      context: context, // Context của trang cha (RfidManagePage)
      // ĐỔI TÊN BIẾN Ở ĐÂY TỪ context THÀNH dialogContext ĐỂ TRÁNH NHẦM
      builder: (dialogContext) => AlertDialog( 
        title: const Text("Thẻ mới phát hiện!"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Mã thẻ: $code", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: "Tên chủ thẻ", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person)),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          // Dùng dialogContext để đóng hộp thoại nhập tên
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text("Hủy")),
          
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) return;
              
              // 1. Đóng hộp thoại nhập tên trước (Dùng dialogContext)
              Navigator.pop(dialogContext);
              
              // 2. Gọi lệnh Lưu (QUAN TRỌNG: DÙNG context CỦA TRANG, KHÔNG DÙNG dialogContext)
              // Biến 'context' này lấy từ State<RfidManagePage>, nó vẫn còn sống.
              var result = await sendCommandWithFeedback(
                context, 
                "SAVE_CARD:$code:${controller.text.trim()}", 
                "SAVE_CARD"
              );

              if (result != null) {
                setState(() {
                  rfids.add({"name": controller.text.trim(), "id": code});
                });
                if(mounted) _showSnack(context, "✅ ${result['message']}", Colors.green);
              }
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  void _deleteCard(int index) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: Text("Xóa thẻ ${rfids[index]['name']}?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Hủy")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Xóa"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      var result = await sendCommandWithFeedback(
        context, 
        "DELETE:${rfids[index]['id']}", 
        "DELETE"
      );

      if (result != null) {
        setState(() => rfids.removeAt(index));
        if(mounted) _showSnack(context, "✅ ${result['message']}", Colors.green);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quản lý thẻ RFID")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : rfids.isEmpty
              ? const Center(child: Text("Chưa có thẻ nào. Nhấn + để thêm.", style: TextStyle(color: Colors.grey)))
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
        label: const Text("Thêm thẻ"),
      ),
    );
  }
}

// ================== ĐỔI MẬT KHẨU ==================
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
      _showSnack(context, "Mã PIN xác nhận không khớp!", Colors.orange);
      return;
    }
    if (newPin.length < 4 || newPin.length > 8) {
      _showSnack(context, "PIN phải từ 4-8 số!", Colors.orange);
      return;
    }

    var result = await sendCommandWithFeedback(context, "CHANGE_PIN:$newPin", "CHANGE_PIN");

    if (result != null) {
      if (mounted) {
        _showSnack(context, "✅ ${result['message']}", Colors.green);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Đổi mã PIN")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Card(
              color: Colors.orangeAccent,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Text("Mã PIN này dùng để nhập trực tiếp trên bàn phím của khóa (4-8 số).", style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
            TextField(controller: _newPinController, decoration: const InputDecoration(labelText: "PIN mới", border: OutlineInputBorder()), keyboardType: TextInputType.number, maxLength: 8),
            const SizedBox(height: 15),
            TextField(controller: _confirmPinController, decoration: const InputDecoration(labelText: "Nhập lại PIN", border: OutlineInputBorder()), keyboardType: TextInputType.number, maxLength: 8),
            const SizedBox(height: 30),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: _changePin, child: const Text("LƯU THAY ĐỔI"))),
          ],
        ),
      ),
    );
  }
}

// ================== DRAWER ==================
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const UserAccountsDrawerHeader(
            accountName: Text("Admin Gia Đình"),
            accountEmail: Text("admin@smartlock.com"),
            currentAccountPicture: CircleAvatar(child: Icon(Icons.person, size: 50)),
            decoration: BoxDecoration(color: Colors.blueAccent),
          ),
          ListTile(leading: const Icon(Icons.dashboard), title: const Text('Dashboard'), onTap: () => Navigator.pop(context)),
          ListTile(
            leading: const Icon(Icons.nfc), title: const Text('Quản lý thẻ RFID'),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => const RfidManagePage())); },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.password), title: const Text('Đổi mật khẩu khóa'),
            onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => const ChangeLockPasswordPage())); },
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (c) => const LoginPage())),
          ),
        ],
      ),
    );
  }
}