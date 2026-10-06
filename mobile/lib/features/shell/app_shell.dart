import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

/// Bottom bar from the UI concept: Home, Transactions, a round "+" in the
/// middle, and Settings.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  static const _tabs = ['/', '/transactions', null, '/settings'];

  @override
  Widget build(BuildContext context) {
    final index = _tabs.indexOf(location);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (i) {
          final tab = _tabs[i];
          if (tab == null) {
            context.push('/add');
          } else {
            context.go(tab);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Transactions',
          ),
          NavigationDestination(
            key: Key('add'),
            icon: CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.add, color: Colors.white),
            ),
            label: 'Add',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
