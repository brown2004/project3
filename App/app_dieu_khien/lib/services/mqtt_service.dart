import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;
  
  // Stream Controllers
  final StreamController<Map<String, dynamic>> _logController = StreamController.broadcast();
  final StreamController<String> _rfidController = StreamController.broadcast();
  final StreamController<bool> _lockStateController = StreamController.broadcast();

  // Public Getters
  Stream<Map<String, dynamic>> get logStream => _logController.stream;
  Stream<String> get rfidStream => _rfidController.stream;
  Stream<bool> get lockStateStream => _lockStateController.stream;

  // ================= CẤU HÌNH IP Ở ĐÂY =================
  // 1. Nếu chạy máy ảo Android (Emulator): Dùng '10.0.2.2'
  // 2. Nếu chạy điện thoại thật (cùng Wifi): Dùng IP LAN của máy tính (VD: '192.168.1.12')
  // 3. Mở CMD gõ 'ipconfig' để xem IPv4 Address
  final String broker = '192.168.34.1'; // <--- SỬA DÒNG NÀY
  final int port = 1883;
  
  final String topicCommand = 'smartlock/command';
  final String topicLog = 'smartlock/log';
  final String topicRfid = 'smartlock/rfid';
  final String topicStatus = 'smartlock/status';

  Future<void> connect() async {
    // Nếu đã kết nối thì thôi
    if (client != null && client!.connectionStatus!.state == MqttConnectionState.connected) {
      print('✅ Đã kết nối rồi, không cần connect lại.');
      return;
    }

    // Tạo ID ngẫu nhiên để không bị đá văng khi connect nhiều lần
    String clientId = 'flutter_app_${DateTime.now().millisecondsSinceEpoch}';
    
    client = MqttServerClient(broker, clientId);
    client!.port = port;
    client!.logging(on: true); // Bật log để debug lỗi kết nối
    client!.keepAlivePeriod = 60;
    client!.onDisconnected = _onDisconnected;
    client!.onConnected = _onConnected;
    client!.onSubscribed = _onSubscribed;

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean() // Quan trọng: Start session mới sạch sẽ
        .withWillQos(MqttQos.atLeastOnce);
    client!.connectionMessage = connMess;

    try {
      print('⏳ Đang kết nối tới $broker ...');
      await client!.connect();
    } on NoConnectionException catch (e) {
      print('❌ Client exception: $e');
      client!.disconnect();
    } on SocketException catch (e) {
      print('❌ Socket exception: $e');
      client!.disconnect();
    } catch (e) {
      print('❌ Lỗi lạ: $e');
      client!.disconnect();
    }

    // Kiểm tra lại trạng thái
    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      print('✅ KẾT NỐI THÀNH CÔNG MOSQUITTO LOCAL');
      _subscribeTopics();
      
      // Lắng nghe tin nhắn trả về
      client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final topic = c[0].topic;
        
        print('📩 Nhận tin từ [$topic]: $payload');
        _handleMessage(topic, payload);
      });
    } else {
      print('❌ Kết nối thất bại - Check lại IP và Firewall');
      client!.disconnect();
    }
  }

  void _subscribeTopics() {
    client!.subscribe(topicLog, MqttQos.atMostOnce);
    client!.subscribe(topicRfid, MqttQos.atMostOnce);
    client!.subscribe(topicStatus, MqttQos.atMostOnce);
  }

  void _handleMessage(String topic, String payload) {
    try {
      // Parse JSON nếu có thể
      var data;
      try {
         data = jsonDecode(payload);
      } catch(e) {
         data = payload; // Nếu không phải JSON thì để nguyên String
      }

      if (topic == topicLog && data is Map<String, dynamic>) {
        _logController.add(data);
      } else if (topic == topicRfid) {
        // Xử lý linh hoạt cả JSON lẫn String thuần
        String code = (data is Map) ? (data['rfid'] ?? data['code']) : data.toString();
        _rfidController.add(code);
      } else if (topic == topicStatus) {
        bool isLocked = (data is Map) ? (data['locked'] ?? true) : (payload == 'LOCK');
        _lockStateController.add(isLocked);
      }
    } catch (e) {
      print('⚠️ Lỗi parse data: $e');
    }
  }

  Future<bool> sendCommand(String command) async {
    if (client?.connectionStatus?.state != MqttConnectionState.connected) {
      print('⚠️ Chưa kết nối MQTT, đang thử kết nối lại...');
      await connect();
      if (client?.connectionStatus?.state != MqttConnectionState.connected) return false;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(command);
    
    try {
      client!.publishMessage(topicCommand, MqttQos.atLeastOnce, builder.payload!);
      print('📤 Đã gửi lệnh: $command');
      return true;
    } catch (e) {
      print('❌ Lỗi gửi lệnh: $e');
      return false;
    }
  }

  void _onConnected() => print('Mosquitto Connected');
  void _onDisconnected() => print('Mosquitto Disconnected');
  void _onSubscribed(String topic) => print('Subscribed to $topic');
}