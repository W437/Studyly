import 'package:flutter/material.dart';

import '../../app/navigation/routes.dart';
import '../../features/scan/presentation/custom_camera_screen.dart';
import '../theme/color_tokens.dart';

class AppNavigationItem {
  const AppNavigationItem({
    required this.route,
    required this.icon,
    required this.label,
    this.activeIcon,
    this.badge,
  });

  final AppRoute route;
  final IconData icon;
  final IconData? activeIcon;
  final String label;
  final String? badge;
}

class AppNavigationBar extends StatelessWidget {
  const AppNavigationBar({
    super.key,
    required this.items,
    required this.currentRoute,
    required this.onSelected,
    this.useRail = false,
  });

  final List<AppNavigationItem> items;
  final AppRoute currentRoute;
  final ValueChanged<AppRoute> onSelected;
  final bool useRail;

  @override
  Widget build(BuildContext context) {
    if (useRail) {
      return _NavigationRail(
        items: items,
        currentRoute: currentRoute,
        onSelected: onSelected,
      );
    }

    return _NavigationBottomBar(
      items: items,
      currentRoute: currentRoute,
      onSelected: onSelected,
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.items,
    required this.currentRoute,
    required this.onSelected,
  });

  final List<AppNavigationItem> items;
  final AppRoute currentRoute;
  final ValueChanged<AppRoute> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = items.indexWhere(
      (item) => item.route == currentRoute,
    );

    return NavigationRail(
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onDestinationSelected: (index) => onSelected(items[index].route),
      labelType: NavigationRailLabelType.all,
      leading: const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.psychology_alt, color: StudyColors.primary, size: 32),
      ),
      destinations: [
        for (final item in items)
          NavigationRailDestination(
            icon: Icon(item.icon),
            selectedIcon: Icon(item.activeIcon ?? item.icon),
            label: Text(item.label),
          ),
      ],
    );
  }
}

class _NavigationBottomBar extends StatelessWidget {
  const _NavigationBottomBar({
    required this.items,
    required this.currentRoute,
    required this.onSelected,
  });

  final List<AppNavigationItem> items;
  final AppRoute currentRoute;
  final ValueChanged<AppRoute> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = items.indexWhere(
      (item) => item.route == currentRoute,
    );
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 70,
            child: Row(
              children: [
                _NavItem(
                  item: items[0],
                  isSelected: 0 == selectedIndex,
                  onTap: () => onSelected(items[0].route),
                ),
                _NavItem(
                  item: items[1],
                  isSelected: 1 == selectedIndex,
                  onTap: () => onSelected(items[1].route),
                ),
                Expanded(
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: StudyColors.primary,
                      ),
                      child: IconButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const CustomCameraScreen(),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.crop_free,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ),
                _NavItem(
                  item: items[2],
                  isSelected: 2 == selectedIndex,
                  onTap: () => onSelected(items[2].route),
                ),
                _NavItem(
                  item: items[3],
                  isSelected: 3 == selectedIndex,
                  onTap: () => onSelected(items[3].route),
                ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom > 0 ? 20 : 0),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final AppNavigationItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected ? StudyColors.primary : Colors.grey.shade400;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSelected ? (item.activeIcon ?? item.icon) : item.icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                item.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
