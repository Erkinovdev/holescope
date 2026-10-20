import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Ключ корневого навигатора: из оверлеев поверх приложения (окно вопроса, подсказки) можно открыть любой экран.
final rootNavKey = GlobalKey<NavigatorState>();

void openRoute(String path) {
  final ctx = rootNavKey.currentContext;
  if (ctx != null) GoRouter.of(ctx).push(path);
}
