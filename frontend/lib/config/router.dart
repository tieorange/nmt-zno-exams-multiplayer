import 'package:go_router/go_router.dart';
import '../presentation/pages/home_screen.dart';
import '../presentation/pages/create_room_screen.dart';
import '../presentation/pages/room_lobby_screen.dart';
import '../presentation/pages/gameplay_screen.dart';
import '../presentation/pages/round_reveal_screen.dart';
import '../presentation/pages/results_screen.dart';

final goRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
    GoRoute(path: '/create', builder: (_, __) => const CreateRoomScreen()),
    GoRoute(
      path: '/room/:roomCode',
      builder: (_, state) =>
          RoomLobbyScreen(roomCode: state.pathParameters['roomCode']!),
      routes: [
        GoRoute(
          path: 'game',
          builder: (_, state) =>
              GameplayScreen(roomCode: state.pathParameters['roomCode']!),
        ),
        GoRoute(
          path: 'reveal',
          builder: (_, state) =>
              RoundRevealScreen(roomCode: state.pathParameters['roomCode']!),
        ),
        GoRoute(
          path: 'results',
          builder: (_, state) =>
              ResultsScreen(roomCode: state.pathParameters['roomCode']!),
        ),
      ],
    ),
  ],
);
