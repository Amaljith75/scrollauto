import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const ScrollAutoApp());

class ScrollAutoApp extends StatelessWidget {
  const ScrollAutoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScrollAuto',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.pinkAccent,
      ),
      home: const HomePage(),
    );
  }
}

/// Thin wrapper around the native (Kotlin) side.
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  Map<String, dynamic> s = {};
  Timer? _poll;
  double? _sliderDrag;

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
    } catch (_) {
      // Native side not available (e.g. widget tests) – ignore.
    }
  }

  Future<void> _set(String key, dynamic value) async {
    setState(() => s[key] = value);
    await Native.setSettings({key: value});
    await _refresh();
  }

  bool b(String k, [bool d = false]) => (s[k] as bool?) ?? d;
  int n(String k, [int d = 0]) => (s[k] as num?)?.toInt() ?? d;
  String str(String k, [String d = '']) => (s[k] as String?) ?? d;

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final serviceOn = b('serviceEnabled');
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ScrollAuto'),
        actions: [
          if (serviceOn)
            IconButton(
              tooltip: b('paused') ? 'Resume' : 'Pause',
              icon: Icon(b('paused') ? Icons.play_arrow : Icons.pause),
              onPressed: () async {
                await Native.call('togglePause');
                _refresh();
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(serviceOn, theme),
          const SizedBox(height: 12),
          _autoScrollCard(theme),
          const SizedBox(height: 12),
          _gestureCard(theme),
          const SizedBox(height: 12),
          _appsCard(),
          const SizedBox(height: 12),
          _testCard(serviceOn),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statusCard(bool serviceOn, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  serviceOn ? Icons.check_circle : Icons.error_outline,
                  color: serviceOn ? Colors.greenAccent : Colors.orangeAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    serviceOn
                        ? (b('paused') ? 'Service on — paused' : 'Service on')
                        : 'Accessibility service is off',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Status: ${str('lastEvent', '—')}',
                style: theme.textTheme.bodySmall),
            if (!serviceOn) ...[
              const SizedBox(height: 12),
              const Text(
                'ScrollAuto needs its Accessibility service to see the reel '
                'player and perform swipes.\n\n'
                'If the toggle is greyed out ("Restricted setting"): open App '
                'info → ⋮ menu → "Allow restricted settings", then try again.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.accessibility_new),
                    label: const Text('Enable service'),
                    onPressed: () => Native.call('openAccessibilitySettings'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.info_outline),
                    label: const Text('App info'),
                    onPressed: () => Native.call('openAppSettings'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _autoScrollCard(ThemeData theme) {
    final fallback = _sliderDrag ?? n('fallbackSeconds').toDouble();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Scroll when reel ends'),
            subtitle: const Text(
                'Watches the video progress bar and swipes to the next reel '
                'when it finishes.'),
            value: b('autoEnabled', true),
            onChanged: (v) => _set('autoEnabled', v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              fallback == 0
                  ? 'Fallback timer: off'
                  : 'Fallback timer: ${fallback.round()} s',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Many Instagram reels (and some YouTube versions) don\'t expose a '
              'progress bar. When none is found, swipe after this many seconds.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Slider(
            value: fallback.clamp(0, 120),
            min: 0,
            max: 120,
            divisions: 24,
            label: fallback == 0 ? 'Off' : '${fallback.round()} s',
            onChanged: (v) => setState(() => _sliderDrag = v),
            onChangeEnd: (v) {
              _sliderDrag = null;
              _set('fallbackSeconds', v.round());
            },
          ),
          SwitchListTile(
            title: const Text('Only on Reels / Shorts screen'),
            subtitle: const Text(
                'Recommended. Turn off only if auto-scroll never starts.'),
            value: b('strictScreen', true),
            onChanged: (v) => _set('strictScreen', v),
          ),
        ],
      ),
    );
  }

  Widget _gestureCard(ThemeData theme) {
    final mode = str('gestureMode', 'off');
    final cameraMode = mode == 'camera';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hand gesture', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'off', label: Text('Off'), icon: Icon(Icons.block)),
                  ButtonSegment(
                      value: 'proximity',
                      label: Text('Wave'),
                      icon: Icon(Icons.waving_hand)),
                  ButtonSegment(
                      value: 'camera',
                      label: Text('Air swipe'),
                      icon: Icon(Icons.videocam)),
                ],
                selected: {mode},
                onSelectionChanged: (sel) => _setGestureMode(sel.first),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              switch (mode) {
                'proximity' =>
                  'Wave your hand over the top of the phone (proximity sensor) '
                      '→ next reel.\nCover the sensor for ~1.5 s → pause / '
                      'resume auto-scroll.\nLow battery use.',
                'camera' =>
                  'Move your hand UP in front of the selfie camera → next reel.\n'
                      'Move it DOWN → previous reel.\nUses the camera while '
                      'active, so it uses more battery.',
                _ => 'Gesture control is off.',
              },
              style: theme.textTheme.bodySmall,
            ),
            if (mode != 'off') ...[
              const SizedBox(height: 8),
              Text(
                b('gestureRunning')
                    ? 'Gesture listener running'
                    : 'Gesture listener not running',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: b('gestureRunning')
                        ? Colors.greenAccent
                        : Colors.orangeAccent),
              ),
            ],
            if (cameraMode && !b('cameraGranted')) ...[
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: () => Native.call('requestCameraPermission'),
                child: const Text('Grant camera permission'),
              ),
            ],
            if (cameraMode)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Invert up / down'),
                subtitle: const Text(
                    'Turn on if moving your hand up goes to the previous reel.'),
                value: b('invertCamera'),
                onChanged: (v) => _set('invertCamera', v),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setGestureMode(String mode) async {
    if (mode != 'off') {
      if (!b('notificationsGranted')) {
        await Native.call('requestNotificationPermission');
      }
      if (mode == 'camera' && !b('cameraGranted')) {
        await Native.call('requestCameraPermission');
      }
    }
    await _set('gestureMode', mode);
  }

  Widget _appsCard() {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.camera_alt_outlined),
            title: const Text('Instagram Reels'),
            value: b('igEnabled', true),
            onChanged: (v) => _set('igEnabled', v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.smart_display_outlined),
            title: const Text('YouTube Shorts'),
            value: b('ytEnabled', true),
            onChanged: (v) => _set('ytEnabled', v),
          ),
        ],
      ),
    );
  }

  Widget _testCard(bool serviceOn) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.swipe_up),
        title: const Text('Test swipe'),
        subtitle: const Text(
            'Swipes up once after 5 seconds — switch to Reels/Shorts now.'),
        enabled: serviceOn,
        onTap: () async {
          await Native.call('testScroll');
          _snack('Swiping in 5 s — open Reels or Shorts');
        },
      ),
    );
  }
}
