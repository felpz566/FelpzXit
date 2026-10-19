
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window_plus/flutter_overlay_window_plus.dart';

class OverlayPanel extends StatefulWidget {
  const OverlayPanel({super.key});

  @override
  State<OverlayPanel> createState() => _OverlayPanelState();
}

class _OverlayPanelState extends State<OverlayPanel> {
  int _tabIndex = 0;

  // ---- ESP ----
  bool espLinha = false;
  bool espCaixa = false;
  bool caixaInteira = true;
  bool espNome = false;
  bool espDistancia = false;
  bool espVida = false;
  bool espEsqueleto = false;

  // ---- Aimbot ----
  double smooth = 5.0;
  double fovWidth = 120.0;
  bool ignorarDeitados = false;
  bool checkVisible = false;
  bool ativarFov = false;

  // Envia comando para o app principal (que usa Shizuku)
  void _send(String cmd, [dynamic value]) {
    FlutterOverlayWindowPlus.shareData({'cmd': cmd, 'value': value});
  }

  Future<void> _bypass() async {
    await _send('esp_linha', false);
    await _send('esp_caixa', false);
    await _send('esp_nome', false);
    await _send('esp_distancia', false);
    await _send('esp_vida', false);
    await _send('esp_esqueleto', false);
    await _send('aimbot', false);
    await _send('fov', false);
    FlutterOverlayWindowPlus.shareData({'action': 'bypass_clear_logs'});
  }

  Future<void> _closeOnly() async {
    await _send('all_off', true);
    FlutterOverlayWindowPlus.closeOverlay();
  }

  Future<void> _closePanel() async {
    FlutterOverlayWindowPlus.closeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 340,
          height: 460,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            children: [
              _buildTopBar(),
              const Divider(height: 1, color: Colors.white24),
              Expanded(
                child: Row(
                  children: [
                    _buildSideTabs(),
                    const VerticalDivider(width: 1, color: Colors.white24),
                    Expanded(child: _buildContent()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Text('felpz xit',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: _closePanel,
          ),
        ],
      ),
    );
  }

  Widget _buildSideTabs() {
    final tabs = ['ESP', 'Aimbot', 'Config'];
    return Container(
      width: 82,
      color: const Color(0xFF1A1A1A),
      child: Column(
        children: List.generate(tabs.length, (i) {
          final selected = _tabIndex == i;
          return InkWell(
            onTap: () => setState(() => _tabIndex = i),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: selected ? Colors.redAccent : Colors.transparent,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                tabs[i],
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildContent() {
    switch (_tabIndex) {
      case 0: return _buildEsp();
      case 1: return _buildAimbot();
      default: return _buildConfig();
    }
  }

  Widget _buildEsp() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _check('Ativar Linha', espLinha, (v) {
            setState(() => espLinha = v);
            _send('esp_linha', v);
          }),
          _check('Ativar Caixa', espCaixa, (v) {
            setState(() => espCaixa = v);
            _send('esp_caixa', v);
          }),
          if (espCaixa)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 4),
              child: Column(children: [
                _radio('Caixa inteira', caixaInteira, () {
                  setState(() => caixaInteira = true);
                  _send('caixa_modo', 'inteira');
                }),
                _radio('Só cantos', !caixaInteira, () {
                  setState(() => caixaInteira = false);
                  _send('caixa_modo', 'cantos');
                }),
              ]),
            ),
          _check('Ativar Nome', espNome, (v) {
            setState(() => espNome = v);
            _send('esp_nome', v);
          }),
          _check('Ativar Distância', espDistancia, (v) {
            setState(() => espDistancia = v);
            _send('esp_distancia', v);
          }),
          _check('Ativar Vida', espVida, (v) {
            setState(() => espVida = v);
            _send('esp_vida', v);
          }),
          _check('Ativar Esqueleto', espEsqueleto, (v) {
            setState(() => espEsqueleto = v);
            _send('esp_esqueleto', v);
          }),
        ],
      ),
    );
  }

  Widget _buildAimbot() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _slider('Smooth', smooth, 1, 20, (v) {
            setState(() => smooth = v);
            _send('aim_smooth', v);
          }),
          _slider('Largura do FOV', fovWidth, 20, 300, (v) {
            setState(() => fovWidth = v);
            _send('aim_fov_width', v);
          }),
          _check('Ignorar deitados', ignorarDeitados, (v) {
            setState(() => ignorarDeitados = v);
            _send('aim_ignore_prone', v);
          }),
          _check('Check visible', checkVisible, (v) {
            setState(() => checkVisible = v);
            _send('aim_check_visible', v);
          }),
          _check('Ativar FOV', ativarFov, (v) {
            setState(() => ativarFov = v);
            _send('aim_fov_draw', v);
          }),
        ],
      ),
    );
  }

  Widget _buildConfig() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: Column(children: [
        _button('Fechar Painel', _closeOnly),
        const SizedBox(height: 8),
        _button('Ativar Bypass (limpa logs + desativa)', _bypass,
            color: Colors.redAccent),
        const SizedBox(height: 8),
        _button('Fechar Painel (sem limpar logs)', _closeOnly),
      ]),
    );
  }

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) {
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: Colors.redAccent,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }

  Widget _radio(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Row(children: [
        Radio<bool>(
          value: true,
          groupValue: selected,
          onChanged: (_) => onTap(),
          activeColor: Colors.redAccent,
        ),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    );
  }

  Widget _slider(String label, double value, double min, double max, ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.toStringAsFixed(1)}',
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        Slider(
          value: value, min: min, max: max,
          activeColor: Colors.redAccent,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _button(String label, VoidCallback onTap, {Color? color}) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? const Color(0xFF2A2A2A),
          foregroundColor: Colors.white,
        ),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
