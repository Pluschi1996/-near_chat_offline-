import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:ui'; // Für den Weichzeichner (Frosted Glass Effect)
import 'package:flutter/material';

void main() {
  runApp(const NearChatApp());
}

class NearChatApp extends StatelessWidget {
  const NearChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NearChat',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1015),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1), // Modernes Indigo
          secondary: Color(0xFFEC4899), // Pinker Akzent
          surface: Color(0xFF1E1F28), // Dunkles Schiefer
          error: Color(0xFFEF4444),
        ),
      ),
      home: const ProfileSetupScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Profil-Auswahl beim Start der App
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedAvatar = "🐱"; // Standard-Avatar

  // Eine Auswahl an coolen Emojis für das Profil
  final List<String> _avatars = ["🐱", "🏎️", "🤖", "🚀", "👾", "🦊", "🎧", "⚡"];

  void _saveProfile() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Bitte gib einen Benutzernamen ein!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // Weiterleitung zum Hauptbildschirm mit Übergabe der Profildaten
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => ChatHomeScreen(
          userName: name,
          avatar: _selectedAvatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                      ),
                    ),
                    child: const Icon(Icons.bolt, size: 60, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "NearChat",
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                  ),
                  const Text(
                    "Offline. Sicher. Direkt.",
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  const SizedBox(height: 40),

                  // Avatar-Vorschau & Auswahl
                  Text(
                    _selectedAvatar,
                    style: const TextStyle(fontSize: 70),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 60,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      itemCount: _avatars.length,
                      itemBuilder: (context, index) {
                        final avatar = _avatars[index];
                        final isSelected = avatar == _selectedAvatar;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedAvatar = avatar;
                            });
                          },
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? theme.colorScheme.primary.withOpacity(0.3) : Colors.transparent,
                              border: Border.all(
                                color: isSelected ? theme.colorScheme.primary : Colors.grey.withOpacity(0.3),
                                width: 2,
                              ),
                            ),
                            child: Text(avatar, style: const TextStyle(fontSize: 24)),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Namenseingabe
                  TextField(
                    controller: _nameController,
                    maxLength: 15,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: "Dein Name",
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      counterText: "",
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Start-Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Los geht's",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatHomeScreen extends StatefulWidget {
  final String userName;
  final String avatar;

  const ChatHomeScreen({
    super.key,
    required this.userName,
    required this.avatar,
  });

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  // Netzwerkvariablen
  String _localIP = "Suche IP...";
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  final List<Socket> _connectedClients = [];
  final int _port = 4040;

  // Partner-Informationen
  String _partnerName = "Partner";
  String _partnerAvatar = "👤";

  // UI-Status
  bool _isHosting = false;
  bool _isConnected = false;
  String _connectionStatus = "Bereit zum Koppeln";

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

  Future<void> _fetchLocalIP() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      if (interfaces.isNotEmpty) {
        setState(() {
          _localIP = interfaces.first.addresses.first.address;
        });
      } else {
        setState(() {
          _localIP = "Kein WLAN aktiv";
        });
      }
    } catch (e) {
      setState(() {
        _localIP = "Fehler: $e";
      });
    }
  }

  // STARTET DEN SERVER
  Future<void> _startServer() async {
    if (_isHosting) return;

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, _port);
      setState(() {
        _isHosting = true;
        _connectionStatus = "Warte auf Partner...";
      });

      _serverSocket!.listen((Socket client) {
        _handleIncomingConnection(client);
      });
    } catch (e) {
      _showErrorSnackBar("Fehler beim Hosten: $e");
    }
  }

  void _stopServer() {
    _serverSocket?.close();
    for (var client in _connectedClients) {
      client.close();
    }
    _connectedClients.clear();
    setState(() {
      _isHosting = false;
      _isConnected = false;
      _connectionStatus = "Bereit zum Koppeln";
    });
  }

  void _handleIncomingConnection(Socket client) {
    if (_connectedClients.isNotEmpty) {
      client.write(utf8.encode(jsonEncode({'type': 'system', 'message': 'Besetzt'})));
      client.close();
      return;
    }

    _connectedClients.add(client);
    _setupSocketListeners(client);

    // Profil direkt nach Verbindungsaufbau an den neuen Partner senden
    _sendProfileHandshake(client);
  }

  // VERBINDET SICH ALS CLIENT
  Future<void> _connectToPeer(String targetIP) async {
    if (targetIP.isEmpty) {
      _showErrorSnackBar("Bitte eine gültige IP eingeben!");
      return;
    }

    setState(() {
      _connectionStatus = "Verbinde mit $targetIP...";
    });

    try {
      _clientSocket = await Socket.connect(targetIP, _port, timeout: const Duration(seconds: 10));
      _setupSocketListeners(_clientSocket!);
      _sendProfileHandshake(_clientSocket!);
    } catch (e) {
      setState(() {
        _connectionStatus = "Verbindung fehlgeschlagen";
      });
      _showErrorSnackBar("Verbindung fehlgeschlagen: $e");
    }
  }

  void _disconnectClient() {
    _clientSocket?.destroy();
    _clientSocket = null;
    setState(() {
      _isConnected = false;
      _connectionStatus = "Bereit zum Koppeln";
    });
  }

  // Sendet den eigenen Namen & Avatar an den Partner
  void _sendProfileHandshake(Socket socket) {
    final handshake = jsonEncode({
      'type': 'handshake',
      'name': widget.userName,
      'avatar': widget.avatar,
    });
    socket.write(handshake);
  }

  void _setupSocketListeners(Socket socket) {
    setState(() {
      _isConnected = true;
      _connectionStatus = "Verbunden";
    });

    socket.listen(
      (data) {
        final messageString = utf8.decode(data);
        try {
          final Map<String, dynamic> parsedJson = jsonDecode(messageString);
          
          if (parsedJson['type'] == 'handshake') {
            setState(() {
              _partnerName = parsedJson['name'] ?? "Partner";
              _partnerAvatar = parsedJson['avatar'] ?? "👤";
            });
          } else if (parsedJson['type'] == 'msg') {
            _addMessage(parsedJson['text'], false);
          }
        } catch (e) {
          _addMessage(messageString, false);
        }
      },
      onError: (error) => _handleDisconnect(),
      onDone: () => _handleDisconnect(),
    );
  }

  void _handleDisconnect() {
    _showErrorSnackBar("Verbindung beendet.");
    _stopServer();
    _disconnectClient();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final messagePayload = jsonEncode({
      'type': 'msg',
      'text': text,
    });

    final encodedPayload = utf8.encode(messagePayload);

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
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: Text(_isConnected ? _partnerAvatar : widget.avatar, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConnected ? _partnerName : "NearChat Offline",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  _connectionStatus,
                  style: TextStyle(fontSize: 11, color: _isConnected ? Colors.greenAccent : Colors.grey),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F1015),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.grey),
            tooltip: "IP aktualisieren",
            onPressed: _fetchLocalIP,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Moderne Netzwerk-Status-Bar (Einfache schwebende Infobox)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1F28),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Deine IP: $_localIP",
                      style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isConnected ? Colors.greenAccent : Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isConnected ? "Verbunden" : "Bereit",
                          style: TextStyle(
                            color: _isConnected ? Colors.greenAccent : Colors.orangeAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),

            // Wenn noch nicht verbunden: Kopplungs-Zentrale
            if (!_isConnected)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.sensors,
                            size: 70,
                            color: Color(0xFF6366F1),
                          ),
                          const SizedBox(height: 24),

                          // Option A: Hosten
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1F28),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: _isHosting ? const Color(0xFF6366F1).withOpacity(0.5) : Colors.white10,
                                width: 1.5,
                              ),
                            ),
                            child: Column(
                              children: [
                                const Text(
                                  "Als Host warten",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  "Dein Partner muss sich mit deiner IP-Adresse verbinden.",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: ElevatedButton.icon(
                                    onPressed: _isHosting ? _stopServer : _startServer,
                                    icon: Icon(_isHosting ? Icons.stop_rounded : Icons.play_arrow_rounded),
                                    label: Text(_isHosting ? "Hosting beenden" : "Kopplung starten"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _isHosting ? Colors.redAccent : const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Option B: Verbinden
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0x
