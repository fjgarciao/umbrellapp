// UmbrellApp — Flutter MVP single-file implementation
// Package: com.fjgarciao.umbrellapp
// -------------------------------------------------
// What this file includes:
// - Material 3 theming + brand colors
// - go_router navigation: /onboarding → /setup → /home
// - Riverpod state for config (origen, destino, hora) + weather mode
// - Local notifications scheduled daily (15 min antes de la hora configurada)
// - Tapping notification opens Home
// - Simple UI matching the mock
// -------------------------------------------------
// Pubspec (add these under dependencies):
//   flutter:
//     sdk: flutter
//   go_router:
//   flutter_riverpod:
//   shared_preferences:
//   flutter_local_notifications:
//   timezone:
//
// Android setup (AndroidManifest.xml):
//   <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//   <application ...>
//     <!-- Required for notifications -->
//   </application>
// iOS setup (Info.plist):
//   <key>NSUserNotificationUsageDescription</key>
//   <string>Necesitamos enviar recordatorios sobre el clima.</string>
//
// NOTE: For timezone correctness we set Europe/Zurich explicitly.
//       You can integrate flutter_native_timezone to auto-detect later.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;

// --------------------------- GLOBALS ---------------------------
final _routerKey = GlobalKey<NavigatorState>();

final GoRouter _router = GoRouter(
  navigatorKey: _routerKey,
  initialLocation: '/onboarding',
  refreshListenable: GoRouterRefreshStream(_routerController.stream),
  routes: [
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
    GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
  ],
  redirect: (context, state) {
    final ref = ProviderScope.containerOf(context, listen: false);
    final cfg = ref.read(appConfigProvider);
    final isConfigured = cfg.isConfigured;
    final loggingIn =
        state.matchedLocation == '/onboarding' ||
        state.matchedLocation == '/setup';
    if (!isConfigured && state.matchedLocation == '/home') {
      return '/onboarding';
    }
    if (isConfigured && loggingIn) {
      return '/home';
    }
    return null;
  },
);

// Notify router to refresh when config changes
final _routerController = StreamController<void>.broadcast();

// --------------------------- MODELS & STATE ---------------------------
enum WeatherCondition { sunny, rain, snow }

class AppConfig {
  final String origen;
  final String destino;
  final TimeOfDay horaSalida;
  final bool isConfigured;
  const AppConfig({
    this.origen = '',
    this.destino = '',
    this.horaSalida = const TimeOfDay(hour: 8, minute: 15),
    this.isConfigured = false,
  });

  AppConfig copyWith({
    String? origen,
    String? destino,
    TimeOfDay? horaSalida,
    bool? isConfigured,
  }) => AppConfig(
    origen: origen ?? this.origen,
    destino: destino ?? this.destino,
    horaSalida: horaSalida ?? this.horaSalida,
    isConfigured: isConfigured ?? this.isConfigured,
  );
}

class AppConfigNotifier extends StateNotifier<AppConfig> {
  AppConfigNotifier() : super(const AppConfig());

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final o = p.getString('origen') ?? '';
    final d = p.getString('destino') ?? '';
    final h = p.getInt('horaSalidaH') ?? 8;
    final m = p.getInt('horaSalidaM') ?? 15;
    final configured = p.getBool('configured') ?? false;
    state = AppConfig(
      origen: o,
      destino: d,
      horaSalida: TimeOfDay(hour: h, minute: m),
      isConfigured: configured,
    );
    _routerController.add(null);
  }

  Future<void> save(String origen, String destino, TimeOfDay hora) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('origen', origen);
    await p.setString('destino', destino);
    await p.setInt('horaSalidaH', hora.hour);
    await p.setInt('horaSalidaM', hora.minute);
    await p.setBool('configured', true);
    state = state.copyWith(
      origen: origen,
      destino: destino,
      horaSalida: hora,
      isConfigured: true,
    );
    _routerController.add(null);
  }
}

final appConfigProvider = StateNotifierProvider<AppConfigNotifier, AppConfig>((
  ref,
) {
  return AppConfigNotifier();
});

final weatherProvider = StateProvider<WeatherCondition>(
  (ref) => WeatherCondition.rain,
);

// --------------------------- NOTIFICATIONS ---------------------------
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (details) {
        // On tap → go Home
        _router.go('/home');
      },
    );

    // Timezone setup
    tz.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Zurich'));
    } catch (_) {
      // Fallback: keep default
    }

    // Android channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'umbrella_daily',
      'UmbrellApp Daily',
      description: 'Recordatorios diarios 15 min antes de la hora de salida',
      importance: Importance.high,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  Future<void> scheduleDailyReminder(
    TimeOfDay salida,
    WeatherCondition cond,
  ) async {
    final now = tz.TZDateTime.now(tz.local);
    final scheduledToday = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      salida.hour,
      salida.minute,
    ).subtract(const Duration(minutes: 15));

    tz.TZDateTime scheduled = scheduledToday.isAfter(now)
        ? scheduledToday
        : scheduledToday.add(const Duration(days: 1));

    final text = switch (cond) {
      WeatherCondition.rain => '🌧️ Hoy lloverá, no olvides tu paraguas',
      WeatherCondition.snow => '❄️ Hoy nevará, no olvides tu paraguas',
      WeatherCondition.sunny => '🌤️ Hoy no lloverá. No necesitas paraguas.',
    };

    final androidDetails = const AndroidNotificationDetails(
      'umbrella_daily',
      'UmbrellApp Daily',
      channelDescription:
          'Recordatorios diarios 15 min antes de la hora de salida',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      1001,
      'UmbrellApp',
      text,
      scheduled,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'home',
    );
  }

  Future<void> cancelAll() => _plugin.cancelAll();
}

// --------------------------- UI ---------------------------
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await NotificationService.instance.init();
  }
  runApp(const ProviderScope(child: UmbrellApp()));
}

class UmbrellApp extends ConsumerStatefulWidget {
  const UmbrellApp({super.key});
  @override
  ConsumerState<UmbrellApp> createState() => _UmbrellAppState();
}

class _UmbrellAppState extends ConsumerState<UmbrellApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(appConfigProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'UmbrellApp',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0EA5E9),
        ), // sky-500
        appBarTheme: const AppBarTheme(centerTitle: true),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
      ),
      routerConfig: _router,
    );
  }
}

class BrandHeader extends StatelessWidget implements PreferredSizeWidget {
  const BrandHeader({super.key, this.title});
  final String? title;
  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.umbrella, color: Color(0xFF0EA5E9)),
          const SizedBox(width: 8),
          Text(
            title ?? 'UmbrellApp',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      actions: const [SizedBox(width: 8)],
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandHeader(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE), // sky-100
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.umbrella,
                  size: 72,
                  color: Color(0xFF0EA5E9),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'UmbrellApp',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Te recordamos llevar el paraguas los días de lluvia.\nConfigura tus datos en 1 minuto.',
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/setup'),
                  child: const Text('Comenzar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});
  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _origenCtrl = TextEditingController();
  final _destinoCtrl = TextEditingController();
  TimeOfDay _hora = const TimeOfDay(hour: 8, minute: 15);

  @override
  void dispose() {
    _origenCtrl.dispose();
    _destinoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime(BuildContext context) async {
    final picked = await showTimePicker(context: context, initialTime: _hora);
    if (picked != null) setState(() => _hora = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(appConfigProvider.notifier)
        .save(_origenCtrl.text.trim(), _destinoCtrl.text.trim(), _hora);
    final cond = ref.read(weatherProvider);
    if (!kIsWeb) {
      await NotificationService.instance.scheduleDailyReminder(_hora, cond);
    }
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(appConfigProvider);
    if (cfg.isConfigured &&
        _origenCtrl.text.isEmpty &&
        _destinoCtrl.text.isEmpty) {
      _origenCtrl.text = cfg.origen;
      _destinoCtrl.text = cfg.destino;
      _hora = cfg.horaSalida;
    }

    return Scaffold(
      appBar: const BrandHeader(title: 'Configuración inicial'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Completa estos datos rápidos.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),

                const Text(
                  'Ubicación de origen (casa)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _origenCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Ej. Rue de Lausanne 123, Genève',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Introduce tu origen'
                      : null,
                ),
                const SizedBox(height: 16),

                const Text(
                  'Ubicación de destino (trabajo)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _destinoCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Ej. Chemin Industriel 45, Vernier',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Introduce tu destino'
                      : null,
                ),
                const SizedBox(height: 16),

                const Text(
                  'Hora de salida',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _pickTime(context),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.schedule),
                    ),
                    child: Text(_hora.format(context)),
                  ),
                ),

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('Guardar y activar recordatorio'),
                  ),
                ),

                const SizedBox(height: 12),
                const Text(
                  'Privacidad: No compartimos tu ubicación. Solo se usa para consultar el pronóstico.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(appConfigProvider);
    final weather = ref.watch(weatherProvider);
    final date = _formatDate(DateTime.now());

    final (emoji, text, cardColor) = switch (weather) {
      WeatherCondition.sunny => (
        '🌤️',
        'Hoy no lloverá. No necesitas paraguas.',
        const Color(0xFFE0F2FE),
      ),
      WeatherCondition.rain => (
        '🌧️',
        'Hoy lloverá. ¡No olvides tu paraguas!',
        const Color(0xFFBAE6FD),
      ),
      WeatherCondition.snow => (
        '❄️',
        'Hoy nevará. ¡No olvides tu paraguas!',
        const Color(0xFFE5E7EB),
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.umbrella, color: Color(0xFF0EA5E9)),
            const SizedBox(width: 8),
            const Text(
              'UmbrellApp',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Configurar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/setup'),
          ),
          PopupMenuButton<WeatherCondition>(
            tooltip: 'Simular clima',
            onSelected: (v) {
              ref.read(weatherProvider.notifier).state = v;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Clima actualizado (simulación)'),
                  ),
                );
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: WeatherCondition.sunny,
                child: Text('Simular: Soleado'),
              ),
              PopupMenuItem(
                value: WeatherCondition.rain,
                child: Text('Simular: Lluvia'),
              ),
              PopupMenuItem(
                value: WeatherCondition.snow,
                child: Text('Simular: Nieve'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$date · ${_cityFrom(cfg.origen) ?? 'Tu ciudad'}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _WeatherCard(color: cardColor, condition: weather),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.tune),
                  label: const Text('Configurar'),
                  onPressed: () => context.go('/setup'),
                ),
              ),

              const Spacer(),
              // MVP+ mini menú
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  _MiniIcon(text: 'Notifs', icon: Icons.notifications_none),
                  _MiniIcon(text: 'Premium', icon: Icons.star_border),
                  _MiniIcon(text: 'Privacidad', icon: Icons.info_outline),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({required this.text, required this.icon});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.black54),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.color, required this.condition});
  final Color color;
  final WeatherCondition condition;

  @override
  Widget build(BuildContext context) {
    IconData bigIcon;
    String caption;
    switch (condition) {
      case WeatherCondition.sunny:
        bigIcon = Icons.wb_sunny_outlined;
        caption = 'Cielo despejado';
        break;
      case WeatherCondition.rain:
        bigIcon = Icons.umbrella_outlined;
        caption = 'Lluvia prevista';
        break;
      case WeatherCondition.snow:
        bigIcon = Icons.ac_unit_outlined;
        caption = 'Nieve prevista';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white,
          width: 1,
          strokeAlign: BorderSide.strokeAlignCenter,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(bigIcon, size: 64, color: const Color(0xFF0EA5E9)),
          const SizedBox(height: 8),
          Text(caption, style: const TextStyle(color: Colors.black87)),
        ],
      ),
    );
  }
}

// --------------------------- HELPERS ---------------------------
String _formatDate(DateTime d) {
  const days = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  // Adjust to Spanish order (Mon-first). DateTime.weekday: 1=Mon..7=Sun
  final name = days[d.weekday - 1];
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$name $dd/$mm';
}

String? _cityFrom(String address) {
  if (address.isEmpty) return null;
  // naive city extraction: last token after comma
  final parts = address.split(',');
  final last = parts.isNotEmpty ? parts.last.trim() : '';
  return last.isEmpty ? null : last;
}

// --------------------------- UTIL ---------------------------
// Helper to use Riverpod with GoRouter refresh
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// --------------------------- END ---------------------------
