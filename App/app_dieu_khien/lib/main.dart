import 'package:flutter/material.dart';

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
        scaffoldBackgroundColor: Colors.grey[100], // Màu nền xám nhẹ cho hiện đại
      ),
      home: const LoginPage(),
    );
  }
}

// ================== 1. MÀN HÌNH ĐĂNG NHẬP & QUÊN MẬT KHẨU ==================

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
            const Text("Nhập email đã đăng ký để nhận mã reset mật khẩu cho tài khoản Admin.", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 20),
            const TextField(decoration: InputDecoration(labelText: "Email", border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã gửi mã OTP về email! Check inbox nhé.")));
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

// ================== 2. DASHBOARD (MÀN HÌNH CHÍNH) ==================

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  bool _isLocked = true; // Trạng thái khóa

  // Dữ liệu giả lập Log lịch sử
  final List<Map<String, dynamic>> _logs = [
    {"time": "10:30 AM", "date": "Hôm nay", "user": "Bố", "action": "Mở bằng RFID", "success": true},
    {"time": "08:15 AM", "date": "Hôm nay", "user": "Mẹ", "action": "Mở qua App", "success": true},
    {"time": "09:00 PM", "date": "Hôm qua", "user": "Lạ", "action": "Nhập sai mật khẩu 3 lần", "success": false},
    {"time": "06:30 PM", "date": "Hôm qua", "user": "Con trai", "action": "Mở bằng vân tay", "success": true},
  ];

  void _toggleLock() {
    setState(() {
      _isLocked = !_isLocked;
      // Thêm log mới khi bấm nút
      _logs.insert(0, {
        "time": "${DateTime.now().hour}:${DateTime.now().minute}",
        "date": "Vừa xong",
        "user": "Admin",
        "action": _isLocked ? "Đã Khóa cửa qua App" : "Đã Mở cửa qua App",
        "success": true
      });
    });
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
      drawer: const AppDrawer(), // Menu bên trái (được tách ra class riêng bên dưới)
      body: Column(
        children: [
          // --- PHẦN 1: TRẠNG THÁI KHÓA (Card to đẹp) ---
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
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 5))],
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
                // Nút bấm chuyển trạng thái
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

          // --- PHẦN 2: TIÊU ĐỀ LOG ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Lịch sử hoạt động", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                TextButton(onPressed: () {}, child: const Text("Xem tất cả")),
              ],
            ),
          ),

          // --- PHẦN 3: DANH SÁCH LOG ---
          Expanded(
            child: ListView.builder(
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

// ================== 3. APP DRAWER (MENU) ==================

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
            currentAccountPicture: CircleAvatar(backgroundImage: NetworkImage("https://i.pravatar.cc/150?img=12")), // Ảnh giả lập
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
            subtitle: const Text('Mã PIN mở cửa trên thiết bị'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (context) => const ChangeLockPasswordPage()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.wifi),
            title: const Text('Cấu hình Wifi'),
            onTap: () {},
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

// ================== 4. CÁC MÀN HÌNH CHỨC NĂNG KHÁC ==================

// --- Đổi mật khẩu CỦA THIẾT BỊ KHÓA (Mã PIN) ---
class ChangeLockPasswordPage extends StatefulWidget {
  const ChangeLockPasswordPage({super.key});

  @override
  State<ChangeLockPasswordPage> createState() => _ChangeLockPasswordPageState();
}

class _ChangeLockPasswordPageState extends State<ChangeLockPasswordPage> {
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
                    Expanded(child: Text("Mã này dùng để nhập trực tiếp trên bàn phím số của khóa cửa.", style: TextStyle(color: Colors.white))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const TextField(decoration: InputDecoration(labelText: "Mã PIN hiện tại", border: OutlineInputBorder()), keyboardType: TextInputType.number, obscureText: true),
            const SizedBox(height: 15),
            const TextField(decoration: InputDecoration(labelText: "Mã PIN mới (4-6 số)", border: OutlineInputBorder()), keyboardType: TextInputType.number, obscureText: true),
            const SizedBox(height: 15),
            const TextField(decoration: InputDecoration(labelText: "Nhập lại mã PIN mới", border: OutlineInputBorder()), keyboardType: TextInputType.number, obscureText: true),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  // Gửi lệnh MQTT xuống ESP32 ở đây
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Đã cập nhật mã PIN thành công!")));
                  Navigator.pop(context);
                },
                child: const Text("LƯU THAY ĐỔI"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Quản lý thẻ RFID (Giữ nguyên) ---
class RfidManagePage extends StatefulWidget {
  const RfidManagePage({super.key});

  @override
  State<RfidManagePage> createState() => _RfidManagePageState();
}

class _RfidManagePageState extends State<RfidManagePage> {
  List<Map<String, String>> rfids = [
    {"name": "Thẻ của Bố", "id": "A1-B2-C3-D4"},
    {"name": "Thẻ của Mẹ", "id": "E5-F6-G7-H8"},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Quản lý thẻ từ")),
      body: ListView.builder(
        itemCount: rfids.length,
        itemBuilder: (context, index) {
          return ListTile(
            leading: const Icon(Icons.credit_card, size: 40, color: Colors.blue),
            title: Text(rfids[index]['name']!),
            subtitle: Text("ID: ${rfids[index]['id']}"),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => setState(() => rfids.removeAt(index)),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {}, // Thêm logic add thẻ
        child: const Icon(Icons.add),
      ),
    );
  }
}