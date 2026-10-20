import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_overlay_window/src/models/overlay_position.dart';
import 'package:http/http.dart' as http;
import 'package:shizuku_api_plugin/shizuku_api.dart';

const bg = Colors.black;
const panel = Color(0xFF171522);
const neon = Color(0xFFB36BFF);
const muted = Color(0xFF9694A8);


Future<File> _appLogFile() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}/felpz_xit.log');
}

Future<void> _recordAppLog(Object message) async {
  final line = '${DateTime.now().toIso8601String()} $message\n';
  try {
    final file = await _appLogFile();
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  } catch (_) {
    // A falha no arquivo de log não deve interromper o aplicativo.
  }
  debugPrint(message.toString());
}

void main() => runApp(const FelpzXitApp());

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: OverlayPanel()));
}

class FelpzXitApp extends StatelessWidget {
  const FelpzXitApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Felpz Xit',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: neon, brightness: Brightness.dark),
      useMaterial3: true,
    ),
    home: const SecretScreen(),
  );
}

class SecretScreen extends StatefulWidget {
  const SecretScreen({super.key});
  @override
  State<SecretScreen> createState() => _SecretScreenState();
}

class _SecretScreenState extends State<SecretScreen> {
  static final _endpoint = Uri.parse('https://key-manager-fawn.vercel.app/api/keys/validate');
  static const _shortcutChannel = MethodChannel('felpz_xit/shortcut');
  final _key = TextEditingController();
  final _shizuku = ShizukuApi();
  StreamSubscription<dynamic>? _subscription;
  bool _showKey = false, _busy = false;
  final Set<int> _activePointers = <int>{};
  int _multiTapCount = 0;
  DateTime? _lastMultiTap;
  bool _currentGestureCounted = false;

  @override
  void initState() {
    super.initState();
    _shortcutChannel.setMethodCallHandler(_handleShortcutCommand);
    _subscription = FlutterOverlayWindow.overlayListener.listen(
      _onOverlayMessage,
      onError: (Object e) => _recordAppLog('Overlay listener: $e'),
    );
  }

  Future<dynamic> _handleShortcutCommand(MethodCall call) async {
    switch (call.method) {
      case 'openPanel':
        await _openOverlay(launchGame: false);
        return true;
      case 'closePanel':
        await FlutterOverlayWindow.closeOverlay();
        return true;
      case 'disableShortcut':
        return true;
      default:
        throw MissingPluginException('Ação de atalho desconhecida: ${call.method}');
    }
  }

  @override
  void dispose() {
    _shortcutChannel.setMethodCallHandler(null);
    _subscription?.cancel();
    _key.dispose();
    super.dispose();
  }

  // Lista de permissões explícita: nunca executa comandos arbitrários do overlay.
  Future<void> _onOverlayMessage(dynamic message) async {
    if (message is! Map) return;
    final name = message['name'];
    final value = message['value'];
    const allowed = {'indicator', 'focusMode', 'viewScale'};
    if (!allowed.contains(name)) return;
    if ((name == 'indicator' || name == 'focusMode') && value is! bool) return;
    if (name == 'viewScale' &&
        (value is! num || value < 0.5 || value > 1.5)) return;
    try {
      final encoded = jsonEncode({name.toString(): value});
      await _shizuku.runCommand(
        "printf '%s' '$encoded' > /data/local/tmp/felpz_cmd.json",
      );
    } catch (e) {
      _recordAppLog('Falha ao enviar estado via Shizuku: $e');
    }
  }

  void _pointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);
    if (_activePointers.length >= 3 && !_currentGestureCounted) {
      _currentGestureCounted = true;
      final now = DateTime.now();
      if (_lastMultiTap == null ||
          now.difference(_lastMultiTap!) > const Duration(milliseconds: 1500)) {
        _multiTapCount = 1;
      } else {
        _multiTapCount++;
      }
      _lastMultiTap = now;
      if (_multiTapCount >= 3 && mounted) {
        setState(() => _showKey = true);
      }
    }
  }

  void _pointerEnd(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.isEmpty) {
      _currentGestureCounted = false;
    }
  }

  Future<void> _validate() async {
    final key = _key.text.trim();
    if (key.isEmpty || _busy) {
      _message('Digite sua key.');
      return;
    }

    setState(() => _busy = true);
    try {
      final response = await http.post(
        _endpoint,
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'key': key, 'product': 'FelpzXit'}),
      ).timeout(const Duration(seconds: 15));

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        _recordAppLog('Validação HTTP ${response.statusCode}: resposta não JSON: ${response.body}');
        _message('Erro no servidor de validação (HTTP ${response.statusCode}).');
        return;
      }

      if (decoded is! Map) {
        _recordAppLog('Validação HTTP ${response.statusCode}: resposta inesperada: ${response.body}');
        _message('Resposta inesperada do servidor (HTTP ${response.statusCode}).');
        return;
      }

      if (response.statusCode >= 500) {
        final detail = decoded['message'] ?? decoded['error'];
        _recordAppLog('Erro do servidor HTTP ${response.statusCode}: $detail');
        _message('Servidor com erro (HTTP ${response.statusCode}). Tente novamente mais tarde.');
        return;
      }

      final valid = decoded['valid'] == true || decoded['success'] == true;
      if (response.statusCode >= 200 && response.statusCode < 300 && valid) {
        await _openOverlay();
        return;
      }

      final error = (decoded['error'] ?? decoded['status'] ?? decoded['message'] ?? '').toString().toLowerCase();
      _message(switch (error) {
        'expired' => 'Key expirada.',
        'revoked' => 'Key revogada.',
        'wrong_product' => 'Key pertence a outro produto.',
        'invalid_key' || 'invalid' => 'Key inválida.',
        _ when response.statusCode == 404 => 'Rota de validação não encontrada (HTTP 404).',
        _ when response.statusCode == 401 || response.statusCode == 403 => 'Key recusada pelo servidor (HTTP ${response.statusCode}).',
        _ when response.statusCode >= 400 => 'Falha ao validar a key (HTTP ${response.statusCode}).',
        _ => 'Key não validada pelo servidor.',
      });
    } on TimeoutException {
      _message('Tempo limite ao validar a key. Tente novamente.');
    } catch (e, stack) {
      _recordAppLog('Falha na validação: $e\n$stack');
      _message('Não foi possível conectar ao servidor de validação.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOverlay({bool launchGame = true}) async {
    try {
      if (await _shizuku.pingBinder() != true) {
        _message('Inicie o Shizuku antes de abrir o painel.');
        return;
      }
      if (await _shizuku.checkPermission() != true &&
          await _shizuku.requestPermission() != true) {
        _message('Permissão do Shizuku negada.');
        return;
      }
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        await FlutterOverlayWindow.requestPermission();
      }
      if (!await FlutterOverlayWindow.isPermissionGranted()) {
        _message('Permita a exibição sobre outros aplicativos.');
        return;
      }
      // Ask for notification permission before launching the game so the dialog
      // does not unexpectedly appear over gameplay.
      var notificationsAllowed = false;
      try {
        var notificationStatus = await Permission.notification.status;
        if (launchGame && !notificationStatus.isGranted) {
          notificationStatus = await Permission.notification.request();
        }
        notificationsAllowed = notificationStatus.isGranted;
      } catch (e) {
        _recordAppLog('Não foi possível verificar a permissão de notificação: $e');
      }

      // Só inicia o jogo no primeiro acesso; atalhos apenas reabrem o painel.
      if (launchGame) {
        try {
          await _shizuku.runCommand('monkey -p com.dts.freefireth 1');
          await Future.delayed(const Duration(milliseconds: 900));
        } catch (e) {
          _recordAppLog('Não foi possível iniciar o Free Fire automaticamente: $e');
        }
      }
      await FlutterOverlayWindow.showOverlay(
        height: 420,
        width: 600,
        alignment: OverlayAlignment.center,
        overlayTitle: 'Felpz Xit',
        overlayContent: 'Painel flutuante ativo',
        enableDrag: true,
        flag: OverlayFlag.defaultFlag,
        positionGravity: PositionGravity.none,
      );
      if (!notificationsAllowed) {
        _message('Painel aberto. Para usar o gatilho, permita as notificações do Felpz Xit.');
      }
      // Não minimizar a Activity: o overlay deve surgir sem minimizar o app.
    } catch (e) {
      _message('Não foi possível abrir o overlay: $e');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _brand() => Container(
    width: 62, height: 62,
    decoration: BoxDecoration(
      color: neon.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: neon),
    ),
    child: const Icon(Icons.bolt_rounded, color: neon, size: 35),
  );

  Widget _secretScreen() => Column(mainAxisSize: MainAxisSize.min, children: [
    _brand(),
    const SizedBox(height: 20),
    const Text('Felpz Xit', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    const Text('Toque três vezes rapidamente para continuar.',
      textAlign: TextAlign.center, style: TextStyle(color: muted)),
  ]);

  Widget _keyForm() => Container(
    margin: const EdgeInsets.all(22),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: panel, borderRadius: BorderRadius.circular(24),
      border: Border.all(color: neon),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _brand(),
      const SizedBox(height: 16),
      const Text('Ativação', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Valide sua key do FelpzXit.', style: TextStyle(color: muted)),
      const SizedBox(height: 10),
      const SizedBox(height: 18),
      TextField(
        controller: _key, enabled: !_busy, autocorrect: false, enableSuggestions: false,
        decoration: const InputDecoration(
          labelText: 'Key de acesso', border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.key_rounded),
        ),
        onSubmitted: (_) => _validate(),
      ),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton(
        onPressed: _busy ? null : _validate,
        child: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('Validar key'),
      )),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, child: OutlinedButton.icon(
        onPressed: _busy ? null : () async {
          try {
            final configured = await _shortcutChannel.invokeMethod<bool>('configureComboTrigger') ?? false;
            if (mounted && configured) {
              _message('Gatilho ativado. Ligue Não Perturbe e rotação automática em até 2 segundos.');
            } else if (mounted) {
              _message('Conceda acesso a Não Perturbe nas configurações e volte ao Felpz Xit.');
            }
          } on PlatformException catch (e) {
            _recordAppLog('Falha ao configurar gatilho: $e');
            _message('Não foi possível configurar o gatilho.');
          }
        },
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Configurar gatilho de notificação'),
      )),
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _showKey ? null : _pointerDown,
      onPointerUp: _showKey ? null : _pointerEnd,
      onPointerCancel: _showKey ? null : _pointerEnd,
      child: SizedBox.expand(
        child: _showKey
          ? SafeArea(child: Center(child: _keyForm()))
          : const ColoredBox(color: Colors.black),
      ),
    ),
  );
}

class OverlayPanel extends StatefulWidget {
  const OverlayPanel({super.key});
  @override
  State<OverlayPanel> createState() => _OverlayPanelState();
}

class _OverlayPanelState extends State<OverlayPanel> {
  int _page = 0;
  bool _indicator = false, _focus = false;
  bool _espEnabled = false, _espLine = true, _espBox = true;
  bool _espHealth = true, _espName = true, _espDistance = true;
  bool _aimbotEnabled = false, _fovEnabled = false;
  double _fovSize = 120;
  OverlayPosition? _dragStart;
  Offset? _dragOrigin;
  double _scale = 1;
  String _status = 'Pronto';

  Future<void> _send(String name, dynamic value) async {
    try {
      await FlutterOverlayWindow.shareData(jsonEncode({'name': name, 'value': value}));
      if (mounted) setState(() => _status = 'Estado enviado');
    } catch (e) {
      if (mounted) setState(() => _status = 'Falha ao enviar estado');
      _recordAppLog('Erro de comunicação do overlay: $e');
    }
  }

  Future<void> _reset() async {
    setState(() {
      _indicator = false; _focus = false; _scale = 1;
      _espEnabled = false; _espLine = true; _espBox = true;
      _espHealth = true; _espName = true; _espDistance = true;
      _aimbotEnabled = false; _fovEnabled = false; _fovSize = 120;
    });
    await _send('indicator', false);
    await _send('focusMode', false);
    await _send('viewScale', 1.0);
    if (mounted) setState(() => _status = 'Controles redefinidos');
  }

  Future<void> _startCustomDrag(DragStartDetails details) async {
    _dragOrigin = details.globalPosition;
    try {
      _dragStart = await FlutterOverlayWindow.getOverlayPosition();
    } catch (e) {
      _recordAppLog('Não foi possível iniciar o arraste do painel: $e');
    }
  }

  Future<void> _updateCustomDrag(DragUpdateDetails details) async {
    final start = _dragStart;
    final origin = _dragOrigin;
    if (start == null || origin == null) return;
    final dx = details.globalPosition.dx - origin.dx;
    final dy = details.globalPosition.dy - origin.dy;
    try {
      await FlutterOverlayWindow.moveOverlay(OverlayPosition(start.x + dx, start.y + dy));
    } catch (e) {
      _recordAppLog('Falha ao mover painel: $e');
    }
  }

  void _endCustomDrag(DragEndDetails details) {
    _dragStart = null;
    _dragOrigin = null;
  }

  BoxDecoration get _card => BoxDecoration(
    color: panel, borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFF302A3D)),
  );

  Widget _toggle(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> changed) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _card,
      child: Row(children: [
        Icon(icon, color: neon, size: 23),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: muted, fontSize: 11)),
        ])),
        Switch.adaptive(value: value, onChanged: changed),
      ]),
    );

  Widget _navItem(int index, IconData icon, String label) {
    final selected = _page == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Material(
        color: selected ? neon.withValues(alpha: 0.17) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _page = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: selected ? neon : muted, size: 18),
              const SizedBox(width: 7),
              Text(label, style: TextStyle(color: selected ? Colors.white : muted, fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _espPage() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('ESP', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      const Text('Preferências visuais do painel. Estas opções ainda não estão ligadas ao jogo.', style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 16),
      _toggle(Icons.visibility_rounded, 'Ativar ESP', 'Ativa as opções visuais abaixo', _espEnabled, (v) => setState(() => _espEnabled = v)),
      const SizedBox(height: 10),
      Opacity(opacity: _espEnabled ? 1 : 0.48, child: IgnorePointer(ignoring: !_espEnabled, child: Column(children: [
        _toggle(Icons.show_chart_rounded, 'Linha', 'Linha indicadora', _espLine, (v) => setState(() => _espLine = v)),
        const SizedBox(height: 8),
        _toggle(Icons.crop_square_rounded, 'Caixa', 'Contorno de caixa', _espBox, (v) => setState(() => _espBox = v)),
        const SizedBox(height: 8),
        _toggle(Icons.favorite_border_rounded, 'Vida', 'Indicador de vida', _espHealth, (v) => setState(() => _espHealth = v)),
        const SizedBox(height: 8),
        _toggle(Icons.person_outline_rounded, 'Nome', 'Exibir nome', _espName, (v) => setState(() => _espName = v)),
        const SizedBox(height: 8),
        _toggle(Icons.social_distance_rounded, 'Distância', 'Exibir distância', _espDistance, (v) => setState(() => _espDistance = v)),
      ]))),
    ],
  );

  Widget _aimbotPage() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Aimbot', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      const Text('Controles de interface; não executam mira automática no jogo.', style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 16),
      _toggle(Icons.my_location_rounded, 'Ativar aimbot', 'Alternar opção da interface', _aimbotEnabled, (v) => setState(() => _aimbotEnabled = v)),
      const SizedBox(height: 10),
      _toggle(Icons.circle_outlined, 'Ativar FOV', 'Mostrar prévia visual do campo de visão', _fovEnabled, (v) => setState(() => _fovEnabled = v)),
      const SizedBox(height: 10),
      Container(padding: const EdgeInsets.all(14), decoration: _card, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.tune_rounded, color: neon, size: 20), const SizedBox(width: 9), const Expanded(child: Text('Tamanho do FOV', style: TextStyle(fontWeight: FontWeight.w600)))]),
        const SizedBox(height: 12),
        Slider(value: _fovSize, min: 30, max: 300, divisions: 27, onChanged: _fovEnabled ? (v) => setState(() => _fovSize = v) : null),
        const SizedBox(height: 8),
        Center(child: SizedBox(width: 150, height: 150, child: Center(child: Container(
          width: 30 + (_fovSize / 300 * 120), height: 30 + (_fovSize / 300 * 120),
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _fovEnabled ? neon : muted, width: 1.5)),
        )))),
      ])),
    ],
  );

  Widget _homePage() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      const Text('Bem-vindo ao Felpz Xit',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Acesse os controles pelo menu lateral.',
        style: TextStyle(color: muted, fontSize: 13)),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: _card,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.dashboard_customize_rounded, color: neon, size: 22),
            SizedBox(width: 9),
            Text('Resumo do painel', style: TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          _summaryRow(Icons.radio_button_checked_rounded, 'Indicador visual', _indicator ? 'Ativado' : 'Desativado'),
          const SizedBox(height: 12),
          _summaryRow(Icons.center_focus_strong_rounded, 'Modo foco', _focus ? 'Ativado' : 'Desativado'),
          const SizedBox(height: 12),
          _summaryRow(Icons.tune_rounded, 'Escala', '${(_scale * 100).round()}%'),
        ]),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: () => setState(() => _page = 1),
        icon: const Icon(Icons.tune_rounded),
        label: const Text('Abrir controles'),
      ),
      const SizedBox(height: 10),
      Text(_status, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );

  Widget _summaryRow(IconData icon, String label, String value) => Row(children: [
    Icon(icon, size: 18, color: muted),
    const SizedBox(width: 9),
    Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
    Text(value, style: const TextStyle(color: neon, fontWeight: FontWeight.w700, fontSize: 12)),
  ]);

  Widget _controlsPage() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('Controles', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      const Text('Ative ou ajuste os controles visuais.',
        style: TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 18),
      _toggle(Icons.radio_button_checked_rounded, 'Indicador visual', 'Alternar indicador', _indicator, (v) {
        setState(() => _indicator = v); _send('indicator', v);
      }),
      const SizedBox(height: 10),
      _toggle(Icons.center_focus_strong_rounded, 'Modo foco', 'Controle visual de foco', _focus, (v) {
        setState(() => _focus = v); _send('focusMode', v);
      }),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14), decoration: _card,
        child: Column(children: [
          Row(children: [
            const Icon(Icons.tune_rounded, color: neon, size: 20),
            const SizedBox(width: 9),
            const Expanded(child: Text('Escala de visualização',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            Text('${(_scale * 100).round()}%', style: const TextStyle(color: neon, fontWeight: FontWeight.bold)),
          ]),
          Slider(value: _scale, min: 0.5, max: 1.5, divisions: 10, onChanged: (v) {
            setState(() => _scale = v); _send('viewScale', v);
          }),
        ]),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _reset,
        icon: const Icon(Icons.restart_alt_rounded), label: const Text('Redefinir controles')),
      const SizedBox(height: 8),
      Text(_status, textAlign: TextAlign.center,
        style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );

  Future<void> _closePanel() async {
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (e) {
      _recordAppLog('Não foi possível fechar o painel: $e');
      if (mounted) setState(() => _status = 'Falha ao fechar o painel');
    }
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: neon, width: 1.4), boxShadow: [BoxShadow(color: neon.withValues(alpha: 0.18), blurRadius: 20)]),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        GestureDetector(
          onPanStart: _startCustomDrag, onPanUpdate: _updateCustomDrag, onPanEnd: _endCustomDrag,
          child: Container(
            height: 46, padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: const BoxDecoration(color: Color(0xFF171321), border: Border(bottom: BorderSide(color: Color(0xFF342641)))),
            child: Row(children: [
              const Icon(Icons.drag_indicator_rounded, color: muted, size: 20), const SizedBox(width: 8),
              const Icon(Icons.bolt_rounded, color: neon, size: 22), const SizedBox(width: 8),
              const Expanded(child: Text('FELPZ XIT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.8))),
              Icon(Icons.circle, size: 8, color: _status == 'Falha ao enviar estado' ? Colors.redAccent : Colors.greenAccent),
              const SizedBox(width: 8),
              IconButton(tooltip: 'Fechar painel', onPressed: _closePanel, icon: const Icon(Icons.close_rounded, size: 22), visualDensity: VisualDensity.compact),
            ]),
          ),
        ),
        SizedBox(height: 48, child: SingleChildScrollView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(children: [
            _navItem(0, Icons.home_rounded, 'Início'),
            _navItem(1, Icons.tune_rounded, 'Controles'),
            _navItem(2, Icons.visibility_rounded, 'ESP'),
            _navItem(3, Icons.my_location_rounded, 'Aimbot'),
          ]),
        )),
        const Divider(height: 1, color: Color(0xFF342641)),
        Expanded(child: IndexedStack(index: _page.clamp(0, 3), children: [_homePage(), _controlsPage(), _espPage(), _aimbotPage()])),
      ]),
    ),
  );
}
