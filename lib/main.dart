import 'package:comic_read/router/app_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter_common/flutter_common.dart';

void main() {
  setUrlStrategy(PathUrlStrategy());
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shadow Comic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      initialRoute: '/',
      onGenerateRoute: (settings) => AppRoutes.generateRoute(context, settings),
    );
  }
}

