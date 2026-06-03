import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router.dart';
import 'shared/theme/app_theme.dart';

const supabaseUrl = 'https://sqynhyvomvaavuoheisl.supabase.co';
const supabaseKey = 'sb_publishable_0qupKD46jfKrkYUSkELXvQ_oBxpOBlA';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);

  runApp(const ProviderScope(child: FabFoodsApp()));
}

class FabFoodsApp extends StatelessWidget {
  const FabFoodsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'FabFoods',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
