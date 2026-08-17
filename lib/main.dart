import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/rxdart.dart';
import 'core/services/auth_service.dart';
import 'core/services/notification_badge_service.dart';
import 'core/services/notification_navigation_service.dart';
import 'core/services/version_check_service.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';
import 'widgets/update_dialog.dart';

// TODO: Add stream controller
// Used to pass messages from event handlers to the UI.
final _messageStreamController = BehaviorSubject<RemoteMessage>();
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _androidNotificationChannel =
    AndroidNotificationChannel(
      'zwacop_notifications',
      'Notifications Zwacop',
      description: 'Notifications des messages et activités Zwacop.',
      importance: Importance.high,
    );

// TODO: Define the background message handler
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (kDebugMode) {
    debugPrint('Handling a background message: ${message.messageId}');
    debugPrint('Message data: ${message.data}');
    debugPrint('Message notification: ${message.notification?.title}');
    debugPrint('Message notification: ${message.notification?.body}');
  }
}

Future<void> _initializeLocalNotifications() async {
  const initializationSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _localNotifications.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: (response) {
      if (kDebugMode) {
        debugPrint('[Notification tap] payload=${response.payload}');
      }
      final payload = response.payload;
      if (payload == null || payload.trim().isEmpty) return;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          unawaited(
            NotificationNavigationService.instance.handlePayload(decoded),
          );
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('[Notification tap] invalid payload: $error');
        }
      }
    },
  );

  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_androidNotificationChannel);
  await _localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.requestNotificationsPermission();
}

Future<void> _showForegroundNotification(RemoteMessage message) async {
  final notification = message.notification;
  final title = notification?.title ?? message.data['title']?.toString();
  final body = notification?.body ?? message.data['body']?.toString();
  if ((title == null || title.trim().isEmpty) &&
      (body == null || body.trim().isEmpty)) {
    return;
  }

  await _localNotifications.show(
    id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
    title: title?.trim().isEmpty == true ? 'Zwacop' : title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _androidNotificationChannel.id,
        _androidNotificationChannel.name,
        channelDescription: _androidNotificationChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

void _handleNotificationInteraction(RemoteMessage message) {
  if (kDebugMode) {
    debugPrint('[FCM interaction] message=${message.messageId}');
    debugPrint('[FCM interaction] data=${message.data}');
  }
  unawaited(NotificationNavigationService.instance.handlePayload(message.data));
}

//zwacop-44925
// Platform  Firebase App Id
// android   1:434434525946:android:cb4c310f99538c4a69d743
// ios       1:434434525946:ios:4d4fa420af03dfe069d743
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Restore saved session before the app renders
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // TODO: Request permission
  final messaging = FirebaseMessaging.instance;
  await _initializeLocalNotifications();

  final settings = await messaging.requestPermission(
    alert: true,
    announcement: false,
    badge: true,
    carPlay: false,
    criticalAlert: false,
    provisional: false,
    sound: true,
  );

  if (kDebugMode) {
    debugPrint('Permission granted: ${settings.authorizationStatus}');
  }
  await messaging.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // TODO: Set up foreground message handler
  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    if (kDebugMode) {
      debugPrint('Handling a foreground message: ${message.messageId}');
      debugPrint('Message data: ${message.data}');
      debugPrint('Message notification: ${message.notification?.title}');
      debugPrint('Message notification: ${message.notification?.body}');
    }

    _messageStreamController.sink.add(message);
    NotificationBadgeService.instance.applyRemoteMessageData(message.data);
    await _showForegroundNotification(message);
  });

  // TODO: Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  FirebaseMessaging.instance.onTokenRefresh.listen((
    refreshedFirebaseRegistrationToken,
  ) {
    AuthService.instance.syncFcmToken(refreshedFirebaseRegistrationToken);
  });
  FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationInteraction);

  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationInteraction(initialMessage);
  }

  await AuthService.instance.loadSession();
  await VersionCheckService.instance.loadInstalledVersion();
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const ZwacopApp());
}

class ZwacopApp extends StatefulWidget {
  const ZwacopApp({super.key});

  @override
  State<ZwacopApp> createState() => _ZwacopAppState();
}

class _ZwacopAppState extends State<ZwacopApp> {
  StreamSubscription<RemoteMessage>? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _messageSubscription = _messageStreamController.listen(_showMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationNavigationService.instance.flushPending();
    });
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _showMessage(RemoteMessage message) {
    final notification = message.notification;
    final text = notification == null
        ? 'Nouvelle notification'
        : [
            notification.title,
            notification.body,
          ].where((value) => value?.trim().isNotEmpty == true).join('\n');
    final displayText = text.trim().isEmpty ? 'Nouvelle notification' : text;
    debugPrint('[FCM foreground] $displayText');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: NotificationNavigationService.instance.navigatorKey,
      title: 'Zwacop',
      locale: Locale('fr', 'FR'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: VersionCheckGate(child: HomeScreen()),
    );
  }
}
