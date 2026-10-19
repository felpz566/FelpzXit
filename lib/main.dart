import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window_plus/flutter_overlay_window_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shizuku_api_plugin/shizuku_api.dart';

const bg = Colors.black;
const panel = Color(0xFF171522);
const neon = Color(0xFFB36BFF);
const muted = Color(0xFF9694A8);

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
  final _key = TextEditingController();
  final _shizuku = ShizukuApi();
  StreamSubscription<dynamic>? _subscription;
  bool _showKey = false, _busy = false;
  int _taps = 0;
  DateTime? _lastTap;

  @override
  void initState() {
    super.initState();
    _subscription = FlutterOverlayWindowPlus.overlayListener.listen(
      _onOverlayMessage,
      onError: (Object e) => debugPrint('Overlay listener: $e'),
    );
  }

  @override
  void dispose() {
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
      debugPrint('Falha ao enviar estado via Shizuku: $e');
    }
  }

  void _tap() {
    final now = DateTime.now();
    if (_lastTap == null || now.difference(_lastTap!) > const Duration(milliseconds: 900)) {
      _taps = 1;
    } else {
      _taps++;
    }
    _lastTap = now;
    if (_taps >= 3) {
      _taps = 0;
      setState(() => _showKey = true);
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
        body: jsonEncode({'key': key, 'product': 'MultiKit'}),
      ).timeout(const Duration(seconds: 15));

      dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        debugPrint('Validação HTTP ${response.statusCode}: resposta não JSON: ${response.body}');
        _message('Erro no servidor de validação (HTTP ${response.statusCode}).');
        return;
      }

      if (decoded is! Map) {
        debugPrint('Validação HTTP ${response.statusCode}: resposta inesperada: ${response.body}');
        _message('Resposta inesperada do servidor (HTTP ${response.statusCode}).');
        return;
      }

      if (response.statusCode >= 500) {
        final detail = decoded['message'] ?? decoded['error'];
        debugPrint('Erro do servidor HTTP ${response.statusCode}: $detail');
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
      debugPrint('Falha na validação: $e\n$stack');
      _message('Não foi possível conectar ao servidor de validação.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openOverlay() async {
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
      if (!await FlutterOverlayWindowPlus.isPermissionGranted()) {
        await FlutterOverlayWindowPlus.requestPermission();
      }
      if (!await FlutterOverlayWindowPlus.isPermissionGranted()) {
        _message('Permita a exibição sobre outros aplicativos.');
        return;
      }
      await FlutterOverlayWindowPlus.showOverlay(
        height: 400,
        width: 300,
        alignment: OverlayAlignment.center,
        enableDrag: true,
        flag: OverlayFlag.defaultFlag,
        positionGravity: PositionGravity.auto,
      );
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
      const Text('Valide sua key do MultiKit.', style: TextStyle(color: muted)),
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
    ]),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showKey ? null : _tap,
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
  bool _indicator = false, _focus = false, _settings = false;
  double _scale = 1;
  String _status = 'Pronto';

  Future<void> _send(String name, dynamic value) async {
    try {
      await FlutterOverlayWindowPlus.shareData(jsonEncode({'name': name, 'value': value}));
      if (mounted) setState(() => _status = 'Estado enviado');
    } catch (e) {
      if (mounted) setState(() => _status = 'Falha ao enviar estado');
      debugPrint('Erro de comunicação do overlay: $e');
    }
  }

  Future<void> _reset() async {
    setState(() { _indicator = false; _focus = false; _scale = 1; });
    await _send('indicator', false);
    await _send('focusMode', false);
    await _send('viewScale', 1.0);
    if (mounted) setState(() => _status = 'Controles redefinidos');
  }

  BoxDecoration get _card => BoxDecoration(
    color: panel, borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFF302A3D)),
  );

  Widget _toggle(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> changed) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: _card,
      child: Row(children: [
        Icon(icon, color: neon, size: 21),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(subtitle, style: const TextStyle(color: muted, fontSize: 10)),
        ])),
        Switch.adaptive(value: value, onChanged: changed),
      ]),
    );

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(22),
        border: Border.all(color: neon, width: 1.4),
        boxShadow: [BoxShadow(color: neon.withValues(alpha: 0.16), blurRadius: 18)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
          decoration: const BoxDecoration(
            color: Color(0xFF171321),
            border: Border(bottom: BorderSide(color: Color(0xFF342641))),
          ),
          child: Row(children: [
            const Icon(Icons.bolt_rounded, color: neon),
            const SizedBox(width: 6),
            const Expanded(child: Text('Felpz Xit',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
            IconButton(
              tooltip: 'Configurações', visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _settings = !_settings),
              icon: const Icon(Icons.settings_rounded, size: 20),
            ),
            IconButton(
              tooltip: 'Fechar painel', visualDensity: VisualDensity.compact,
              onPressed: () async {
                try { await FlutterOverlayWindowPlus.closeOverlay(); }
                catch (e) { debugPrint('Erro ao fechar overlay: $e'); }
              },
              icon: const Icon(Icons.close_rounded, size: 22),
            ),
          ]),
        ),
        Expanded(child: ListView(
          padding: const EdgeInsets.all(11),
          children: [
            const Text('CONTROLES', style: TextStyle(
              color: muted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
            const SizedBox(height: 8),
            _toggle(Icons.radio_button_checked_rounded, 'Indicador visual', 'Alternar indicador', _indicator, (v) {
              setState(() => _indicator = v); _send('indicator', v);
            }),
            const SizedBox(height: 8),
            _toggle(Icons.center_focus_strong_rounded, 'Modo foco', 'Controle visual de foco', _focus, (v) {
              setState(() => _focus = v); _send('focusMode', v);
            }),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11), decoration: _card,
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.tune_rounded, color: neon, size: 19),
                  const SizedBox(width: 7),
                  const Expanded(child: Text('Escala de visualização',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                  Text((_scale * 100).round().toString() + '%', style: const TextStyle(color: neon)),
                ]),
                Slider(value: _scale, min: 0.5, max: 1.5, divisions: 10, onChanged: (v) {
                  setState(() => _scale = v); _send('viewScale', v);
                }),
              ]),
            ),
            if (_settings) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(11), decoration: _card,
                child: const Text(
                  'Os controles enviam estados permitidos para /data/local/tmp/felpz_cmd.json via Shizuku.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ),
            ],
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: _reset,
              icon: const Icon(Icons.restart_alt_rounded), label: const Text('Redefinir controles')),
            const SizedBox(height: 5),
            Text(_status, textAlign: TextAlign.center,
              style: const TextStyle(color: muted, fontSize: 10)),
          ],
        )),
      ]),
    ),
  );
}
