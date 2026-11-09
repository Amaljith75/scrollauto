import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.black,
  ));
  runApp(const DoomApp());
}

// ------------------------------------------------------------------ theme

class C {
  static const bg = Colors.black;
  static const card = Color(0xFF161618);
  static const cardHi = Color(0xFF222226);
  static const border = Color(0x1FFFFFFF);
  static const dim = Color(0xFF8E8E93);
  static const blue = Color(0xFF1E9BFF);
  static const blueDeep = Color(0xFF0A6CFF);
  static const green = Color(0xFF34C759);
  static const orange = Color(0xFFFF9F0A);
}

class DoomApp extends StatelessWidget {
  const DoomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Doom',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: C.bg,
        colorScheme: const ColorScheme.dark(primary: C.blue, surface: C.card),
        sliderTheme: const SliderThemeData(
          activeTrackColor: C.blue,
          thumbColor: Colors.white,
          inactiveTrackColor: C.cardHi,
          trackHeight: 6,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ------------------------------------------------------------------ native

class Native {
  static const _ch = MethodChannel('scrollauto/control');

  static Future<Map<String, dynamic>> status() async {
    final r = await _ch.invokeMapMethod<String, dynamic>('getStatus');
    return r ?? <String, dynamic>{};
  }

  static Future<void> setSettings(Map<String, dynamic> m) =>
      _ch.invokeMethod('setSettings', m);

  static Future<dynamic> call(String method) => _ch.invokeMethod(method);
}

// ------------------------------------------------------------------ page

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Map<String, dynamic> s = {};
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final st = await Native.status();
      if (mounted) setState(() => s = st);
    } catch (_) {}
  }

  Future<void> _set(String key, dynamic value) async {
    HapticFeedback.selectionClick();
    setState(() => s[key] = value);
    try {
      await Native.setSettings({key: value});
    } catch (_) {}
    await _refresh();
  }

  bool b(String k, [bool d = false]) => (s[k] as bool?) ?? d;
  int n(String k, [int d = 0]) => (s[k] as num?)?.toInt() ?? d;
  String str(String k, [String d = '']) => (s[k] as String?) ?? d;

  bool get _on => b('serviceEnabled');
  String get _mode => str('gestureMode', 'off');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
              children: [
                _header(),
                const SizedBox(height: 18),
                _on ? _heroCard() : _setupCard(),
                const SizedBox(height: 22),
                const _Label('Auto scroll'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _autoTile()),
                  const SizedBox(width: 12),
                  Expanded(child: _timerTile()),
                ]),
                const SizedBox(height: 22),
                const _Label('Hand gesture'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _waveTile()),
                  const SizedBox(width: 12),
                  Expanded(child: _airTile()),
                ]),
                const SizedBox(height: 22),
                const _Label('Apps'),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _AppPill(
                      label: 'Instagram',
                      icon: Icons.camera_alt_rounded,
                      on: b('igEnabled', true),
                      onTap: () => _set('igEnabled', !b('igEnabled', true)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _AppPill(
                      label: 'YouTube',
                      icon: Icons.smart_display_rounded,
                      on: b('ytEnabled', true),
                      onTap: () => _set('ytEnabled', !b('ytEnabled', true)),
                    ),
                  ),
                ]),
              ],
            ),
            Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar()),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _header() {
    return Row(
      children: [
        const Text('Doom',
            style: TextStyle(
                fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
        const Spacer(),
        _CircleBtn(
          icon: Icons.tune_rounded,
          onTap: _openMore,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- hero

  Widget _heroCard() {
    final paused = b('paused');
    final event = str('lastEvent').split('\n').first;
    return _Card(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0E3A4F), Color(0xFF101418)],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('${n('countToday')}',
                  style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -2)),
              const SizedBox(width: 12),
              const Text('reels\ntoday',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, height: 1.1)),
              const Spacer(),
              _StatusDot(
                color: paused ? C.orange : C.green,
                label: paused ? 'Paused' : 'Live',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _MiniStat('${n('countAutoToday')}', 'Auto')),
            const SizedBox(width: 10),
            Expanded(child: _MiniStat('${n('countGestureToday')}', 'Gesture')),
            const SizedBox(width: 10),
            Expanded(child: _MiniStat('${n('countTotal')}', 'All time')),
          ]),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.bolt_rounded, size: 16, color: C.dim),
              const SizedBox(width: 6),
              Expanded(
                child: Text(event,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: C.dim, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _setupCard() {
    return _Card(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [C.blue, C.blueDeep],
      ),
      onTap: () => Native.call('openAccessibilitySettings'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.power_settings_new_rounded,
              size: 40, color: Colors.white),
          const SizedBox(height: 14),
          const Text('Turn on Doom',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Accessibility → Doom → On',
              style: TextStyle(fontSize: 15, color: Colors.white70)),
          const SizedBox(height: 18),
          Row(
            children: [
              _WhitePill(
                label: 'Open settings',
                icon: Icons.arrow_forward_rounded,
                onTap: () => Native.call('openAccessibilitySettings'),
              ),
              const SizedBox(width: 10),
              _GhostPill(
                label: 'Greyed out?',
                onTap: _showRestrictedHelp,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- tiles

  Widget _autoTile() {
    final on = b('autoEnabled', true);
    return _Tile(
      active: on,
      icon: Icons.play_circle_fill_rounded,
      title: 'Reel ends',
      value: on ? 'On' : 'Off',
      onTap: () => _set('autoEnabled', !on),
    );
  }

  Widget _timerTile() {
    final sec = n('fallbackSeconds');
    return _Tile(
      active: false,
      icon: Icons.timer_rounded,
      title: 'Backup timer',
      value: sec == 0 ? 'Off' : '$sec',
      unit: sec == 0 ? null : 's',
      trailing: const Icon(Icons.chevron_right_rounded, color: C.dim),
      onTap: _openTimer,
    );
  }

  Widget _waveTile() {
    final on = _mode == 'proximity';
    return _Tile(
      active: on,
      icon: Icons.waving_hand_rounded,
      title: 'Wave',
      value: on ? 'On' : 'Off',
      hint: 'Wave over the top',
      onTap: () => _setMode(on ? 'off' : 'proximity'),
    );
  }

  Widget _airTile() {
    final on = _mode == 'camera';
    final needsCam = on && !b('cameraGranted');
    return _Tile(
      active: on,
      icon: Icons.back_hand_rounded,
      title: 'Air swipe',
      value: needsCam ? 'Allow' : (on ? 'On' : 'Off'),
      hint: 'Hand up / down',
      trailing: on
          ? GestureDetector(
              onTap: () => _set('invertCamera', !b('invertCamera')),
              child: Icon(Icons.swap_vert_rounded,
                  color: b('invertCamera') ? Colors.white : Colors.white54),
            )
          : null,
      onTap: () {
        if (needsCam) {
          Native.call('requestCameraPermission');
        } else {
          _setMode(on ? 'off' : 'camera');
        }
      },
    );
  }

  Future<void> _setMode(String mode) async {
    if (mode != 'off') {
      try {
        if (!b('notificationsGranted')) {
          await Native.call('requestNotificationPermission');
        }
        if (mode == 'camera' && !b('cameraGranted')) {
          await Native.call('requestCameraPermission');
        }
      } catch (_) {}
    }
    await _set('gestureMode', mode);
  }

  // ---------------------------------------------------------------- bottom bar

  Widget _bottomBar() {
    final paused = b('paused');
    return Padding(
      padding: EdgeInsets.fromLTRB(
          40, 0, 40, 16 + MediaQuery.of(context).padding.bottom),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xEE1C1C1F),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: C.border),
          boxShadow: const [
            BoxShadow(color: Colors.black, blurRadius: 24, spreadRadius: 8)
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _BarBtn(
                icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: paused ? 'Resume' : 'Pause',
                highlighted: true,
                enabled: _on,
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  await Native.call('togglePause');
                  _refresh();
                },
              ),
            ),
            Expanded(
              child: _BarBtn(
                icon: Icons.swipe_up_rounded,
                label: 'Test',
                enabled: _on,
                onTap: () async {
                  await Native.call('testScroll');
                  if (!mounted) return;
                  _toast('Swiping in 5 s — open Reels');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- sheets

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 100),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ));
  }

  void _openTimer() {
    double v = n('fallbackSeconds').toDouble();
    _sheet(StatefulBuilder(builder: (ctx, setLocal) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Backup timer',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Used when a reel has no progress bar',
              style: TextStyle(color: C.dim)),
          const SizedBox(height: 22),
          Center(
            child: Text(v == 0 ? 'Off' : '${v.round()} s',
                style: const TextStyle(
                    fontSize: 48, fontWeight: FontWeight.w800, height: 1)),
          ),
          Slider(
            value: v,
            min: 0,
            max: 90,
            divisions: 18,
            onChanged: (x) => setLocal(() => v = x),
            onChangeEnd: (x) => _set('fallbackSeconds', x.round()),
          ),
          Wrap(
            spacing: 8,
            children: [0, 15, 20, 30, 45, 60].map((x) {
              final sel = v.round() == x;
              return ChoiceChip(
                label: Text(x == 0 ? 'Off' : '${x}s'),
                selected: sel,
                showCheckmark: false,
                selectedColor: C.blue,
                backgroundColor: C.cardHi,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onSelected: (_) {
                  setLocal(() => v = x.toDouble());
                  _set('fallbackSeconds', x);
                },
              );
            }).toList(),
          ),
        ],
      );
    }));
  }

  void _openMore() {
    _sheet(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetRow(
          icon: Icons.crop_portrait_rounded,
          title: 'Only on Reels / Shorts',
          trailing: Switch(
            value: b('strictScreen', true),
            activeTrackColor: C.blue,
            onChanged: (v) {
              _set('strictScreen', v);
              Navigator.pop(context);
            },
          ),
        ),
        _SheetRow(
          icon: Icons.accessibility_new_rounded,
          title: 'Accessibility settings',
          onTap: () => Native.call('openAccessibilitySettings'),
        ),
        _SheetRow(
          icon: Icons.info_outline_rounded,
          title: 'App info',
          onTap: () => Native.call('openAppSettings'),
        ),
      ],
    ));
  }

  void _showRestrictedHelp() {
    _sheet(Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Toggle greyed out?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        const _Step(1, 'App info → ⋮ → Allow restricted settings'),
        const _Step(2, 'Come back and tap Open settings'),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: C.blue,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: const StadiumBorder(),
            ),
            onPressed: () => Native.call('openAppSettings'),
            child: const Text('Open App info',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    ));
  }

  void _sheet(Widget child) {
    showModalBottomSheet(
      context: context,
      backgroundColor: C.card,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
            22, 0, 22, 24 + MediaQuery.of(context).padding.bottom),
        child: child,
      ),
    );
  }
}

// ------------------------------------------------------------------ widgets

class _Card extends StatelessWidget {
  final Widget child;
  final Gradient? gradient;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  const _Card({
    required this.child,
    this.gradient,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? C.card : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: C.border),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, child: box);
  }
}

class _Tile extends StatelessWidget {
  final bool active;
  final IconData icon;
  final String title;
  final String value;
  final String? unit;
  final String? hint;
  final Widget? trailing;
  final VoidCallback onTap;

  const _Tile({
    required this.active,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.unit,
    this.hint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 128,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: active ? null : C.card,
          gradient: active
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [C.blue, C.blueDeep])
              : null,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: active ? Colors.transparent : C.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            if (hint != null)
              Text(hint!,
                  style: TextStyle(
                      fontSize: 12,
                      color: active ? Colors.white70 : C.dim)),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(icon, size: 26, color: Colors.white),
                const SizedBox(width: 8),
                Text(value,
                    style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -0.5)),
                if (unit != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 2),
                    child: Text(unit!,
                        style: TextStyle(
                            fontSize: 15,
                            color: active ? Colors.white70 : C.dim)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;

  const _MiniStat(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x33000000),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: C.border),
      ),
      child: Column(
        children: [
          Text(value,
              style:
                  const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, color: C.dim)),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;
  final String label;

  const _StatusDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _AppPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  const _AppPill(
      {required this.label,
      required this.icon,
      required this.on,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: on ? C.cardHi : C.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: on ? C.blue : C.border, width: 1.4),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: on ? Colors.white : C.dim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: on ? Colors.white : C.dim)),
            ),
            Icon(on ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20, color: on ? C.blue : C.dim),
          ],
        ),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: C.card,
          shape: BoxShape.circle,
          border: Border.all(color: C.border),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _BarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlighted;
  final bool enabled;
  final VoidCallback onTap;

  const _BarBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: highlighted ? const Color(0xFF2C2C30) : Colors.transparent,
            borderRadius: BorderRadius.circular(34),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhitePill extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _WhitePill(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(30)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    color: C.blueDeep, fontWeight: FontWeight.w800)),
            const SizedBox(width: 6),
            Icon(icon, size: 18, color: C.blueDeep),
          ],
        ),
      ),
    );
  }
}

class _GhostPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _GhostPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white54),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;

  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SheetRow(
      {required this.icon, required this.title, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: C.cardHi, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing:
          trailing ?? const Icon(Icons.chevron_right_rounded, color: C.dim),
      onTap: onTap,
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;

  const _Step(this.n, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration:
                const BoxDecoration(color: C.blue, shape: BoxShape.circle),
            child: Text('$n',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
    );
  }
}
