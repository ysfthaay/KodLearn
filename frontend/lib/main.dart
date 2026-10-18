import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/editor_page.dart';
import 'pages/profile_page.dart';
import 'pages/context_page.dart';
import 'widgets/command_palette.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const KodLearnApp());
}

// Short fade that uses easeOut so the new page's container is fully on screen
// before its children start their staggered fade-in. That gives the
// "Apple-style" effect: zero layout shift, then content streams in.
CustomTransitionPage<T> _fadePage<T>(GoRouterState state, Widget child) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
    transitionsBuilder: (context, animation, _, c) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(opacity: curved, child: c);
    },
  );
}

final _router = GoRouter(
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final loggedIn = user != null;
    final path = state.matchedLocation;
    final atLogin = path == '/';
    final needsVerify = loggedIn && !user.emailVerified;

    // Not signed in → only the login screen is reachable.
    if (!loggedIn) return atLogin ? null : '/';

    // Signed in, but email unverified → route to /. The login page now
    // renders the verify-email card as an overlay on top of itself, so
    // we don't need a separate /verify route anymore.
    if (needsVerify) return atLogin ? null : '/';

    // Signed in & verified → push them off the login screen.
    if (atLogin) return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(path: '/',          pageBuilder: (c, s) => _fadePage(s, const LoginPage())),
    GoRoute(path: '/dashboard', pageBuilder: (c, s) => _fadePage(s, const DashboardPage())),
    GoRoute(path: '/editor',    pageBuilder: (c, s) => _fadePage(s, const EditorPage())),
    GoRoute(path: '/profile',   pageBuilder: (c, s) => _fadePage(s, const ProfilePage())),
    GoRoute(
      path: '/context/:topicId',
      pageBuilder: (c, s) => _fadePage(
        s,
        ContextPage(topicId: s.pathParameters['topicId'] ?? ''),
      ),
    ),
  ],
);

class KodLearnApp extends StatelessWidget {
  const KodLearnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'KodLearn',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 175, 76, 0)),
        useMaterial3: true,
      ),
      routerConfig: _router,
      // Wrap every routed page so Cmd/Ctrl+K opens the command palette from
      // anywhere. Lives above the Navigator, below MaterialApp's overlays.
      builder: (context, child) => GlobalShortcuts(child: child ?? const SizedBox.shrink()),
    );
  }
}