
import 'package:go_router/go_router.dart';
import 'features/auth/loggin_screen.dart';
import 'features/shifts/shift_start_screen.dart';
import 'features/shifts/shift_end_screen.dart';
import 'features/sales/sale_entry_screen.dart';
import 'features/stock/stock_count_screen.dart';
import 'features/export/export_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/settings/products_screen.dart';
import 'features/settings/staff_screen.dart';
import 'features/settings/clients_screen.dart';

final router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login',     builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/shift/start', builder: (_, __) => const ShiftStartScreen()),
    GoRoute(
      path: '/shift/active',
      builder: (context, state) {
        final shiftId = state.extra as String;
        return SaleEntryScreen(shiftId: shiftId);
      },
    ),
    GoRoute(
      path: '/shift/end',
      builder: (context, state) {
        final shiftId = state.extra as String;
        return ShiftEndScreen(shiftId: shiftId);
      },
    ),
    GoRoute(
      path: '/stock',
      builder: (context, state) {
        final shiftId = state.extra as String;
        return StockCountScreen(shiftId: shiftId);
      },
),
    GoRoute(path: '/login',      builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/shift/start', builder: (context, state) => const ShiftStartScreen()),
    GoRoute(path: '/export',     builder: (context, state) => const ExportScreen()),
    GoRoute(path: '/dashboard',  builder: (context, state) => const DashboardScreen()),
    GoRoute(path: '/settings/products', builder: (context, state) => const ProductsScreen()),
    GoRoute(path: '/settings/staff',    builder: (context, state) => const StaffScreen()),
    GoRoute(path: '/settings/clients',  builder: (context, state) => const ClientsScreen()),
  ],
);