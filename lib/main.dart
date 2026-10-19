import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window_plus/flutter_overlay_window_plus.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shizuku_api_plugin/shizuku_api.dart';

// ⚠️ Entry point do overlay (OBRIGATÓRIO para o flutter_overlay_window_plus 1.0.1+)
@pragma("vm:entry-point")
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: OverlayPanel(),
  ));
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Felpz Xit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const SecretScreen(),
    );
  }
}

class OverlayPanel extends StatelessWidget {
  const OverlayPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(
          'Felpz Xit',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class SecretScreen extends StatefulWidget {
  const SecretScreen({super.key});

  @override
  State<SecretScreen> createState() => _SecretScreenState();
}

class _SecretScreenState extends State<SecretScreen> {
  final ShizukuApi _shizuku = ShizukuApi();
  final TextEditingController _keyController = TextEditingController();

  bool _permissionsGranted = false;
  bool _keyValid = false;
  bool _isValidating = false;

  // ⚠️ SUBSTITUA pela URL real do seu site
  static const String _validateUrl = 'https://key-manager-fawn.vercel.app/api/keys/validate';
  static const String _productName = 'FelpzXit';

  // ---------------------------------------------------------------
  // 1) Gatilho: 2 toques de 3 dedos
  // ---------------------------------------------------------------
  Future<void> _onSecretTriggered() async {
    if (!await Permission.systemAlertWindow.isGranted) {
      await Permission.systemAlertWindow.request();
    }

    final bool? binderRunning = await _shizuku.pingBinder();
    if (binderRunning != true) {
      _showMessage('Shizuku não está rodando.');
      return;
    }

    final bool? hasPermission = await _shizuku.checkPermission();
    if (hasPermission != true) {
      final bool? granted = await _shizuku.requestPermission();
      if (granted != true) {
        _showMessage('Permissão do Shizuku negada.');
        return;
      }
    }

    setState(() => _permissionsGranted = true);
    _showMessage('Permissões concedidas. Insira sua key.');
  }

  // ---------------------------------------------------------------
  // 2) Validação da key (CORRIGIDA)
  // ---------------------------------------------------------------
  Future<void> _validateKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      _showMessage('Digite uma key.');
      return;
    }

    setState(() => _isValidating = true);

    try {
      final response = await http.post(
        Uri.parse(_validateUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'key': key, 'product': _productName}),
      );

      // Verifica se é HTML antes de tentar parsear
      if (response.body.startsWith('<!DOCTYPE') || !response.body.contains('{')) {
         setState(() => _isValidating = false);
         _showMessage('Erro no servidor: Resposta não é JSON.\n${response.body.substring(0, 50)}...');
         return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && data['valid'] == true) {
        setState(() {
          _keyValid = true;
          _isValidating = false;
        });
        _openOverlay();
      } else {
        final error = data['error'] ?? data['status'] ?? 'invalid_key';
        String message;
        switch (error) {
          case 'expired': message = 'Key expirada.'; break;
          case 'revoked': message = 'Key revogada.'; break;
          case 'wrong_product': message = 'Key pertence a outro produto.'; break;
          default: message = 'Key inválida.';
        }
        setState(() => _isValidating = false);
        _showMessage(message);
      }
    } catch (e) {
      setState(() => _isValidating = false);
      _showMessage('Erro ao validar: $e');
    }
  }

  // ---------------------------------------------------------------
  // 3) Abrir overlay
  // ---------------------------------------------------------------
  Future<void> _openOverlay() async {
    if (!await FlutterOverlayWindowPlus.isPermissionGranted()) {
      await FlutterOverlayWindowPlus.requestPermission();
    }

    await FlutterOverlayWindowPlus.showOverlay(
      height: 480,
      width: 360,
      alignment: OverlayAlignment.center,
      enableDrag: true,
      flag: OverlayFlag.defaultFlag,
      positionGravity: PositionGravity.auto,
    );

    await FlutterOverlayWindowPlus.minimizeApp();
  }

  // ---------------------------------------------------------------
  // 4) Listener: recebe comandos do overlay e executa via Shizuku
  // ---------------------------------------------------------------
  void _setupOverlayListener() {
    FlutterOverlayWindowPlus.overlayListener.listen((data) async {
      if (data is Map && data['cmd'] != null) {
        final cmd = data['cmd'];
        final value = data['value'];

        // Envia comando para o motor .dex via arquivo temporário
        final json = jsonEncode({'cmd': cmd, 'value': value});
        final shellCmd = 'echo \'$json\' > /data/local/tmp/felpz_cmd.json';

        try {
          await _shizuku.runCommand(shellCmd);
        } catch (e) {
          debugPrint('Erro ao enviar comando: $e');
        }
      }

      // Bypass: limpar logs
      if (data is Map && data['action'] == 'bypass_clear_logs') {
        try {
          await _shizuku.runCommand('logcat -c');
          await _shizuku.runCommand('rm -rf /sdcard/Android/data/com.dts.freefireth/cache/*');
        } catch (e) {
          debugPrint('Erro no bypass: $e');
        }
      }
    });
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    _setupOverlayListener();
  }

  // ---------------------------------------------------------------
  // 5) Build
  // ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_keyValid) {
      return const Scaffold(
        body: Center(
          child: Text(
            'Painel aberto. Use Volume + para abrir, Volume - para fechar.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    if (_permissionsGranted) {
      return Scaffold(
        appBar: AppBar(title: const Text('Ativação')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextField(
                controller: _keyController,
                decoration: const InputDecoration(
                  labelText: 'Key',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _isValidating
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _validateKey,
                      child: const Text('Validar Key'),
                    ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: ThreeFingerTrigger(
        onTriggered: _onSecretTriggered,
        child: Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}

// =================================================================
// Widget do gatilho: 2 toques de 3 dedos simultâneos
// =================================================================
class ThreeFingerTrigger extends StatefulWidget {
  final VoidCallback onTriggered;
  final Widget child;

  const ThreeFingerTrigger({
    super.key,
    required this.onTriggered,
    required this.child,
  });

  @override
  State<ThreeFingerTrigger> createState() => _ThreeFingerTriggerState();
}

class _ThreeFingerTriggerState extends State<ThreeFingerTrigger> {
  final Set<int> _activePointers = {};
  int _taps = 0;
  DateTime? _lastTapTime;

  static const int _requiredTaps = 2; 
  static const Duration _resetTimeout = Duration(seconds: 2);

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        _activePointers.add(event.pointer);

        if (_activePointers.length == 3) {
          final now = DateTime.now();

          if (_lastTapTime != null &&
              now.difference(_lastTapTime!) > _resetTimeout) {
            _taps = 0;
          }

          _lastTapTime = now;
          _taps++;

          if (_taps >= _requiredTaps) {
            _taps = 0;
            widget.onTriggered();
          }
        }
      },
      onPointerUp: (event) => _activePointers.remove(event.pointer),
      onPointerCancel: (event) => _activePointers.remove(event.pointer),
      child: widget.child,
    );
  }
}
