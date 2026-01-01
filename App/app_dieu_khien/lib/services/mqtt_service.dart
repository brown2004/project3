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
  
  // Stream Controllers (Broadcast để nhiều màn hình cùng nghe được)
  final StreamController<Map<String, dynamic>> _logController = StreamController.broadcast();
  final StreamController<String> _rfidController = StreamController.broadcast();
  final StreamController<bool> _lockStateController = StreamController.broadcast();

  Stream<Map<String, dynamic>> get logStream => _logController.stream;
  Stream<String> get rfidStream => _rfidController.stream;
  Stream<bool> get lockStateStream => _lockStateController.stream;

  // ================= CẤU HÌNH IP (KHỚP VỚI ESP32) =================
  final String broker = '10.238.213.63'; 
  final int port = 1883;
  
  final String topicCommand = 'smartlock/command';
  final String topicLog = 'smartlock/log';
  final String topicRfid = 'smartlock/rfid';
  final String topicStatus = 'smartlock/status';

  Future<void> connect() async {
    if (client != null && client!.connectionStatus!.state == MqttConnectionState.connected) {
      return;
    }

    String clientId = 'flutter_app_${DateTime.now().millisecondsSinceEpoch}';
    client = MqttServerClient(broker, clientId);
    client!.port = port;
    client!.logging(on: true);
    client!.keepAlivePeriod = 60;
    client!.onDisconnected = () => print('❌ MQTT Disconnected');
    
    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client!.connectionMessage = connMess;

    try {
      print('⏳ Connecting to $broker...');
      await client!.connect();
    } catch (e) {
      print('❌ Connection Exception: $e');
      client!.disconnect();
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      print('✅ MQTT Connected');
      _subscribeTopics();
      
      client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final topic = c[0].topic;
        _handleMessage(topic, payload);
      });
    }
  }

  void _subscribeTopics() {
    client!.subscribe(topicLog, MqttQos.atMostOnce);
    client!.subscribe(topicRfid, MqttQos.atMostOnce);
    client!.subscribe(topicStatus, MqttQos.atMostOnce);
  }

  void _handleMessage(String topic, String payload) {
    try {
      var data;
      try {
        // Cố gắng parse JSON
        data = jsonDecode(payload);
      } catch (e) {
        // Nếu không phải JSON thì để nguyên String
        data = payload;
      }

      // --- ĐOẠN SỬA QUAN TRỌNG ---
      if (topic == topicLog) {
        // Chỉ cần nó là Map (bất kể Map<gì, gì>) là chấp nhận hết
        if (data is Map) {
          // Ép kiểu thủ công sang Map<String, dynamic> để Stream không bị lỗi
          final cleanData = Map<String, dynamic>.from(data);
          
          print("📥 Stream Log nhận được: $cleanData"); // In ra để chắc chắn Stream đã nhận
          _logController.add(cleanData);
        } else {
          print("⚠️ Dữ liệu Log không phải JSON Map: $data");
        }
      } 
      // ---------------------------
      
      else if (topic == topicRfid) {
        String code = (data is Map) ? (data['rfid'] ?? data['code']) : data.toString();
        _rfidController.add(code);
      } else if (topic == topicStatus) {
        bool isLocked = (data is Map) ? (data['locked'] ?? true) : (payload == 'LOCK');
        _lockStateController.add(isLocked);
      }
    } catch (e) {
      print('⚠️ Error parsing message: $e');
    }
  }

  void sendCommand(String command) {
    if (client?.connectionStatus?.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);
      client!.publishMessage(topicCommand, MqttQos.atLeastOnce, builder.payload!);
      print('📤 Sent: $command');
    } else {
      print('⚠️ MQTT not connected. Cannot send: $command');
    }
  }
}