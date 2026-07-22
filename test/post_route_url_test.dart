import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Shell + root /post/:id — adres çubuğu Twitter gibi güncellenir mi?
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('butonla go(/post/id) → path /post/…', (tester) async {
    final rootKey = GlobalKey<NavigatorState>();
    late final GoRouter router;
    router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/post/:id',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const Text('DETAIL'),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(body: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) => Center(
                    child: ElevatedButton(
                      onPressed: () => router.go('/post/test_mt_kickoff'),
                      child: const Text('open-post'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/home');

    await tester.tap(find.text('open-post'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL'), findsOneWidget);
    expect(router.state.uri.path, '/post/test_mt_kickoff');
  });

  testWidgets('go API: /home → /post/abc → /home', (tester) async {
    final rootKey = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: rootKey,
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/post/:id',
          parentNavigatorKey: rootKey,
          builder: (context, state) => const Text('DETAIL'),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => Scaffold(body: shell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) => const Text('HOME'),
                ),
              ],
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    router.go('/post/abc');
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/post/abc');

    router.go('/home');
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/home');
  });
}
