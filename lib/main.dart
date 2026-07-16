import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';

void main() {
  runApp(const NearChatApp());
}

class NearChatApp extends StatelessWidget {
  const NearChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NearChat Offline',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const ChatHomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  // Netzwerkvariablen
  String _localIP = "Suche IP...";
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final List<Socket> _connectedClients = [];
  final int _port = 4040; // Standard-Port für die Verbindung

  // UI-Status
  bool _isHosting = false;
  bool _isConnected = false;
  String _connectionStatus = "Getrennt";
  
  // Chat-Daten
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchLocalIP();
  }

  @override
  void dispose() {
    _stopServer();
    _disconnectClient();
    _messageController.dispose();
    _ipController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Ermittelt die IP-Adresse des Geräts im lokalen Netzwerk
  Future<void> _fetchLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      
      if (interfaces.isNotEmpty) {
        setState(() {
          // Nimmt die erste gültige IP-Adresse aus dem lokalen Netzwerk
          _localIP = interfaces.first.addresses.first.address;
        });
      } else {
        setState(() {
          _localIP = "Kein WLAN/Hotspot aktiv";
        });
      }
    } catch (e) {
      setState(() {
        _localIP = "Fehler: $e";
      });
    }
  }

  // STARTET DEN SERVER (Gerät 1 wartet auf Verbindung)
  Future<void> _startServer() async {
    if (_isHosting) return;

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      setState(() {
        _isHosting = true;
        _connectionStatus = "Warte auf Partner (Server läuft auf Port $_port)...";
      });

      _serverSocket!.listen((Socket client) {
        _handleIncomingConnection(client);
      });
    } catch (e) {
      _showErrorSnackBar("Fehler beim Hosten: $e");
    }
  }

  // Stoppt den Server
  void _stopServer() {
    _serverSocket?.close();
    for (var client in _connectedClients) {
      client.close();
    }
    _connectedClients.clear();
    setState(() {
      _isHosting = false;
      _isConnected = false;
      _connectionStatus = "Getrennt";
    });
  }

  // Verarbeitet eingehende Verbindungen auf dem Server
  void _handleIncomingConnection(Socket client) {
    if (_connectedClients.isNotEmpty) {
      // Nur 1-zu-1 Verbindung für diesen Messenger erlauben
      client.write(utf8.encode(jsonEncode({'type': 'system', 'message': 'Besetzt'})));
      client.close();
      return;
    }

    _connectedClients.add(client);
    _setupSocketListeners(client, "Partner");
  }

  // VERBINDET SICH ALS CLIENT (Gerät 2 verbindet sich mit Gerät 1)
  Future<void> _connectToPeer(String targetIP) async {
    if (targetIP.isEmpty) {
      _showErrorSnackBar("Bitte eine gültige IP-Adresse eingeben!");
      return;
    }

    setState(() {
      _connectionStatus = "Verbinde mit $targetIP...";
    });

    try {
      _clientSocket = await Socket.connect(targetIP, _port, timeout: const Duration(seconds: 10));
      _setupSocketListeners(_clientSocket!, "Server");
    } catch (e) {
      setState(() {
        _connectionStatus = "Verbindungsfehler";
      });
      _showErrorSnackBar("Verbindung fehlgeschlagen: $e");
    }
  }

  // Trennt die Client-Verbindung
  void _disconnectClient() {
    _clientSocket?.destroy();
    _clientSocket = null;
    setState(() {
      _isConnected = false;
      _connectionStatus = "Getrennt";
    });
  }

  // Konfiguriert die Datenströme für gesendete/empfangene Nachrichten
  void _setupSocketListeners(Socket socket, String peerType) {
    setState(() {
      _isConnected = true;
      _connectionStatus = "Verbunden mit Partner";
    });

    socket.listen(
      (data) {
        final messageString = utf8.decode(data);
        try {
          final Map<String, dynamic> parsedJson = jsonDecode(messageString);
          if (parsedJson['type'] == 'msg') {
            _addMessage(parsedJson['text'], false);
          }
        } catch (e) {
          // Fallback für reinen Text
          _addMessage(messageString, false);
        }
      },
      onError: (error) {
        _handleDisconnect();
      },
      onDone: () {
        _handleDisconnect();
      },
    );
  }

  void _handleDisconnect() {
    _showErrorSnackBar("Verbindung verloren.");
    _stopServer();
    _disconnectClient();
  }

  // Nachricht lokal hinzufügen und via Socket senden
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final messagePayload = jsonEncode({
      'type': 'msg',
      'text': text,
    });

    final encodedPayload = utf8.encode(messagePayload);

    // Entweder an den verbundenen Client (wenn wir Host sind) oder an den Server (wenn wir Client sind) senden
    if (_isHosting && _connectedClients.isNotEmpty) {
      _connectedClients.first.add(encodedPayload);
      _addMessage(text, true);
    } else if (_clientSocket != null) {
      _clientSocket!.add(encodedPayload);
      _addMessage(text, true);
    } else {
      _showErrorSnackBar("Keine aktive Verbindung!");
      return;
    }

    _messageController.clear();
  }

  void _addMessage(String text, bool isMe) {
    setState(() {
      _messages.add({
        'text': text,
        'isMe': isMe,
        'time': DateTime.now(),
      });
    });
    // Nach unten scrollen
    Timer(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('NearChat Offline', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: theme.colorScheme.primaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: "IP aktualisieren",
            onPressed: _fetchLocalIP,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Netzwerk-Status-Bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              color: theme.colorScheme.secondaryContainer,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.between,
                    children: [
                      Text(
                        "Deine IP: $_localIP",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, py: 2),
                        decoration: BoxDecoration(
                          color: _isConnected ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _isConnected ? "Verbunden" : "Bereit",
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Status: $_connectionStatus",
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.onSecondaryContainer.withOpacity(0.8)),
                  ),
                ],
              ),
            ),

            // Setup Screen (falls nicht verbunden)
            if (!_isConnected)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 80,
                            color: theme.colorScheme.primary.withOpacity(0.6),
                          ),
                          const SizedBox(height: 24),
                          
                          // HOST-Option
                          Card(
                            elevation: _isHosting ? 4 : 1,
                            color: _isHosting ? theme.colorScheme.primaryContainer.withOpacity(0.5) : null,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Text(
                                    "Option A: Als Host starten",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Wähle dies auf Gerät 1. Dein Partner muss sich mit deiner IP verbinden.",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: _isHosting ? _stopServer : _startServer,
                                    icon: Icon(_isHosting ? Icons.stop : Icons.play_arrow),
                                    label: Text(_isHosting ? "Hosting beenden" : "Warten auf Partner"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isHosting ? Colors.redAccent : null,
                                      foregroundColor: _isHosting ? Colors.white : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // CONNECT-Option
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Text(
                                    "Option B: Mit Partner verbinden",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Gib die IP-Adresse des anderen Geräts ein (Gerät 1 muss Host sein).",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _ipController,
                                    keyboardType: TextInputType.values[0], // Keyboard mit Punkten für IP
                                    decoration: const InputDecoration(
                                      hintText: "Z.B. 192.168.43.1",
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      labelText: "IP-Adresse des Partners",
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _connectToPeer(_ipController.text.trim()),
                                    icon: const Icon(Icons.swap_horiz_rounded),
                                    label: const Text("Verbindung herstellen"),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              // Chatbereich, wenn verbunden
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final msg = _messages[index];
                          final isMe = msg['isMe'] as bool;
                          final time = msg['time'] as DateTime;
                          
                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe 
                                  ? theme.colorScheme.primary 
                                  : theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 0),
                                  bottomRight: Radius.circular(isMe ? 0 : 16),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    msg['text'],
                                    style: TextStyle(
                                      color: isMe ? Colors.white : theme.colorScheme.onSurface,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                                    style: TextStyle(
                                      color: isMe ? Colors.white60 : Colors.grey,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    
                    // Eingabeleiste unten
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      color: theme.colorScheme.surface,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                hintText: "Offline-Nachricht senden...",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(24)),
                                ),
                                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _sendMessage,
                            icon: const Icon(Icons.send),
                          ),
                          IconButton(
                            onPressed: () {
                              _stopServer();
                              _disconnectClient();
                            },
                            icon: const Icon(Icons.power_settings_new, color: Colors.red),
                            tooltip: "Verbindung trennen",
                          )
                        ],
                      ),
                    )
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

