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
      ),
      home: const LoginPage(),
    );
  }
}alo


// ================== LOGIN ==================
class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const ForgotPasswordPage())),
                  child: const Text("Quên mật khẩu?"),
                ),
              ),
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

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Khôi phục mật khẩu")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Nhập email đã đăng ký để nhận mã reset mật khẩu.", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            const TextField(decoration: InputDecoration(labelText: "Email", border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã gửi mã OTP về email!")));
                  Navigator.pop(context);
                },
                child: const Text("GỬI YÊU CẦU"),
              ),
            )
          ],
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

class _DashboardPageState extends State<DashboardPage> {
  bool _isLocked = true;
  final List<Map<String, dynamic>> _logs = [];
  final MqttService _mqtt = MqttService();
  
  @override
  void initState() {
    super.initState();
    _connectAndListen();
  }

  void _connectAndListen() async {
    await _mqtt.connect();
    
    // Lắng nghe log
    _mqtt.logStream.listen((logData) {
      if (!mounted) return;
      setState(() {
        _logs.insert(0, {
          "time": _formatTime(DateTime.now()),
          "date": "Hôm nay",
          "user": logData['user'] ?? "Unknown",
          "action": logData['action'] ?? "Hoạt động",
          "success": logData['success'] ?? false
        });
      });
    });

    // Lắng nghe trạng thái khóa từ ESP32
    _mqtt.lockStateStream.listen((locked) {
      if (!mounted) return;
      setState(() {
        _isLocked = locked;
      });
    });
  }

  String _formatTime(DateTime time) {
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  void _toggleLock() async {
    bool success = await _mqtt.sendCommand(_isLocked ? "UNLOCK" : "LOCK");
    
    if (success) {
      setState(() {
        _isLocked = !_isLocked;
        _logs.insert(0, {
          "time": _formatTime(DateTime.now()),
          "date": "Vừa xong",
          "user": "Admin",
          "action": _isLocked ? "Đã Khóa cửa qua App" : "Đã Mở cửa qua App",
          "success": true
        });
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi: Không thể kết nối tới khóa!")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Dashboard Điều Khiển"),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      drawer: const AppDrawer(),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isLocked ? [Colors.redAccent, Colors.orangeAccent] : [Colors.green, Colors.teal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
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

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Lịch sử hoạt động", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton(onPressed: () {}, child: const Text("Xem tất cả")),
              ],
            ),
          ),

          Expanded(
            child: _logs.isEmpty
                ? const Center(child: Text("Chưa có hoạt động nào", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      final bool isSuccess = log['success'];
                      
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isSuccess ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                            child: Icon(
                              isSuccess ? Icons.check_circle : Icons.warning,
                              color: isSuccess ? Colors.green : Colors.red,
                            ),
                          ),
                          title: Text(log['action'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text("${log['user']} • ${log['date']}"),
                          trailing: Text(log['time'], style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
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
          ListTile(
            leading: const Icon(Icons.dashboard),
            title: const Text('Dashboard'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.nfc),
            title: const Text('Quản lý thẻ RFID'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const RfidManagePage()));
            },
          ),
          const Divider(),
          const Padding(padding: EdgeInsets.only(left: 16, top: 10, bottom: 10), child: Text("Cài đặt khóa", style: TextStyle(color: Colors.grey))),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Đổi mật khẩu khóa'),
            subtitle: const Text('Mã PIN mở cửa'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangeLockPasswordPage()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage())),
          ),
        ],
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

class _ChangeLockPasswordPageState extends State<ChangeLockPasswordPage> {
  final TextEditingController _oldPinController = TextEditingController();
  final TextEditingController _newPinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();
  final MqttService _mqtt = MqttService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Đổi mã PIN khóa cửa")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Card(
              color: Colors.orangeAccent,
              child: Padding(
                padding: EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white),
                    SizedBox(width: 10),
                    Expanded(child: Text("Mã này dùng để nhập trực tiếp trên bàn phím của khóa.", style: TextStyle(color: Colors.white))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _oldPinController,
              decoration: const InputDecoration(labelText: "Mã PIN hiện tại", border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _newPinController,
              decoration: const InputDecoration(labelText: "Mã PIN mới (4-8 số)", border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _confirmPinController,
              decoration: const InputDecoration(labelText: "Nhập lại PIN mới", border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  if (_newPinController.text != _confirmPinController.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("PIN xác nhận không khớp!")),
                    );
                    return;
                  }

                  if (_newPinController.text.length < 4) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("PIN phải có ít nhất 4 số!")),
                    );
                    return;
                  }

                  bool success = await _mqtt.sendCommand("CHANGE_PIN:${_newPinController.text}");
                  
                  if (success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Đã cập nhật mã PIN thành công!")),
                    );
                    Navigator.pop(context);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Lỗi: Không thể kết nối!")),
                    );
                  }
                },
                child: const Text("LƯU THAY ĐỔI"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _oldPinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }
}

// ================== QUẢN LÝ RFID ==================
class RfidManagePage extends StatefulWidget {
  const RfidManagePage({super.key});

  @override
  State<RfidManagePage> createState() => _RfidManagePageState();
}

class _RfidManagePageState extends State<RfidManagePage> {
  List<Map<String, String>> rfids = [];
  final MqttService _mqtt = MqttService();

  @override
  void initState() {
    super.initState();
    _mqtt.connect();
  }

  void _addNewCardProcess() async {
    StreamSubscription? sub;

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
            Text("2. Đợi 2-3 giây", style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              sub?.cancel();
              _mqtt.sendCommand("CANCEL_SCAN");
              Navigator.pop(dialogContext);
            },
            child: const Text("Hủy", style: TextStyle(color: Colors.red)),
          )
        ],
      ),
    );

    bool success = await _mqtt.sendCommand("SCAN_NEW_RFID");

    if (success) {
      sub = _mqtt.rfidStream.listen((rfidCode) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
        sub?.cancel();
        _showNameInput(rfidCode);
      });

      // Timeout 30s
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
          sub?.cancel();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Hết thời gian! Không phát hiện thẻ.")),
          );
        }
      });
    } else {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lỗi: Không kết nối được!")),
      );
    }
  }

  void _showNameInput(String code) {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Thẻ mới phát hiện!"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Mã thẻ: $code", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            const SizedBox(height: 15),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: "Tên chủ thẻ",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Vui lòng nhập tên!")),
                );
                return;
              }

              setState(() {
                rfids.add({"name": controller.text.trim(), "id": code});
              });

              await _mqtt.sendCommand("SAVE_CARD:$code:${controller.text.trim()}");
              Navigator.pop(context);
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Đã thêm thẻ ${controller.text.trim()}")),
              );
            },
            child: const Text("Lưu"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quản lý thẻ RFID")),
      body: rfids.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.nfc, size: 80, color: Colors.grey),
                  SizedBox(height: 20),
                  Text("Chưa có thẻ nào", style: TextStyle(fontSize: 18, color: Colors.grey)),
                  SizedBox(height: 10),
                  Text("Nhấn nút + để thêm thẻ", style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: rfids.length,
              itemBuilder: (context, index) => Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.credit_card)),
                  title: Text(rfids[index]['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("ID: ${rfids[index]['id']!}"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      bool? confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("Xác nhận xóa"),
                          content: Text("Xóa thẻ ${rfids[index]['name']}?"),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Hủy"),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Xóa"),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        await _mqtt.sendCommand("DELETE:${rfids[index]['id']}");
                        setState(() => rfids.removeAt(index));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Đã xóa thẻ")),
                        );
                      }
                    },
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