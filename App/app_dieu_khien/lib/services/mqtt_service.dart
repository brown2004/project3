import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'dart:async';
import 'dart:convert';

class MqttService {
  // Singleton
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  MqttServerClient? client;
  bool isConnected = false;

  // Stream controllers
  final StreamController<Map<String, dynamic>> _logController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<String> _rfidController = 
      StreamController<String>.broadcast();
  final StreamController<bool> _lockStateController = 
      StreamController<bool>.broadcast();

  // Public streams
  Stream<Map<String, dynamic>> get logStream => _logController.stream;
  Stream<String> get rfidStream => _rfidController.stream;
  Stream<bool> get lockStateStream => _lockStateController.stream;

  // Thông tin kết nối
  final String broker = 'broker.hivemq.com';
  final int port = 1883;
  final String clientId = 'flutter_smart_lock_${DateTime.now().millisecondsSinceEpoch}';
  
  // Topics - PHẢI KHỚP VỚI ESP32
  final String topicCommand = 'smartlock/command';
  final String topicLog = 'smartlock/log';
  final String topicRfid = 'smartlock/rfid';
  final String topicStatus = 'smartlock/status';

  Future<void> connect() async {
    if (isConnected && client?.connectionStatus?.state == MqttConnectionState.connected) {
      print(' MQTT đã kết nối rồi!');
      return;
    }

    try {
      client = MqttServerClient.withPort(broker, clientId, port);
      client!.logging(on: false);
      client!.keepAlivePeriod = 60;
      client!.autoReconnect = true;
      client!.onConnected = _onConnected;
      client!.onDisconnected = _onDisconnected;
      client!.onSubscribed = _onSubscribed;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillQos(MqttQos.atMostOnce);
      
      client!.connectionMessage = connMessage;

      print('🔄 Đang kết nối MQTT...');
      await client!.connect();

      if (client!.connectionStatus!.state == MqttConnectionState.connected) {
        print(' MQTT kết nối thành công!');
        isConnected = true;
        _subscribeToTopics();
        client!.updates!.listen(_onMessage);
      } else {
        print(' MQTT kết nối thất bại');
        client!.disconnect();
        isConnected = false;
      }
    } catch (e) {
      print(' Lỗi kết nối MQTT: $e');
      isConnected = false;
    }
  }

  void _subscribeToTopics() {
    client?.subscribe(topicLog, MqttQos.atMostOnce);
    client?.subscribe(topicRfid, MqttQos.atMostOnce);
    client?.subscribe(topicStatus, MqttQos.atMostOnce);
    print('📡 Đã subscribe topics');
  }

  void _onConnected() {
    print(' MQTT Connected');
    isConnected = true;
  }

  void _onDisconnected() {
    print('MQTT Disconnected');
    isConnected = false;
  }

  void _onSubscribed(String topic) {
    print(' Subscribed to: $topic');
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> event) {
    final MqttPublishMessage message = event[0].payload as MqttPublishMessage;
    final String topic = event[0].topic;
    final String payload = MqttPublishPayload.bytesToStringAsString(message.payload.message);

    print(' Message từ $topic: $payload');

    try {
      final data = jsonDecode(payload);

      if (topic == topicLog) {
        _logController.add(data);
      } else if (topic == topicRfid) {
        String rfidCode = data['rfid'] ?? data['code'] ?? payload;
        _rfidController.add(rfidCode);
      } else if (topic == topicStatus) {
        _lockStateController.add(data['locked'] ?? false);
      }
    } catch (e) {
      print(' Lỗi parse JSON: $e');
      if (topic == topicRfid) {
        _rfidController.add(payload);
      }
    }
  }

  // Đổi thành Future<bool>
  Future<bool> sendCommand(String command) async {
    if (!isConnected || client == null) {
      print('MQTT chưa kết nối, không thể gửi lệnh!');
      return false;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(command);
      
      client!.publishMessage(
        topicCommand, 
        MqttQos.atLeastOnce, 
        builder.payload!
      );
      
      print(' Đã gửi lệnh: $command');
      return true;
    } catch (e) {
      print(' Lỗi gửi lệnh: $e');
      return false;
    }
  }

  Future<bool> sendJson(Map<String, dynamic> data) async {
    if (!isConnected || client == null) {
      print(' MQTT chưa kết nối!');
      return false;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(data));
      
      client!.publishMessage(
        topicCommand, 
        MqttQos.atLeastOnce, 
        builder.payload!
      );
      
      print(' Đã gửi JSON: $data');
      return true;
    } catch (e) {
      print(' Lỗi gửi JSON: $e');
      return false;
    }
  }

  void disconnect() {
    client?.disconnect();
    isConnected = false;
    print(' Đã ngắt kết nối MQTT');
  }

  void dispose() {
    disconnect();
    _logController.close();
    _rfidController.close();
    _lockStateController.close();
  }
}