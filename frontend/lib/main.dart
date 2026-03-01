import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';
import 'config/router.dart';
import 'services/supabase_service.dart';
import 'services/api_service.dart';
import 'presentation/cubits/room_cubit/room_cubit.dart';
import 'presentation/cubits/quiz_cubit/quiz_cubit.dart';
import 'presentation/cubits/game_cubit/game_cubit.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase (reads SUPABASE_URL + SUPABASE_ANON_KEY from --dart-define)
  await SupabaseService.initialize();

  final logger = Logger();
  final supabaseService = SupabaseService(logger: logger);
  final apiService = ApiService(logger: logger);

  final roomCubit = RoomCubit(
    supabaseService: supabaseService,
    apiService: apiService,
    logger: logger,
  );
  final quizCubit = QuizCubit(
    supabaseService: supabaseService,
    apiService: apiService,
    logger: logger,
  );

  // Forward playerId + roomCode to QuizCubit after join so it can track "my" answer
  roomCubit.stream.listen((_) {
    if (roomCubit.myPlayerId != null && roomCubit.state.code.isNotEmpty) {
      quizCubit.setContext(roomCubit.myPlayerId!, roomCubit.state.code);
    }
  });

  runApp(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: roomCubit),
        BlocProvider.value(value: quizCubit),
        BlocProvider(
          create: (_) => GameCubit(apiService: apiService, logger: logger),
        ),
      ],
      child: const NmtQuizApp(),
    ),
  );
}

class NmtQuizApp extends StatelessWidget {
  const NmtQuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData.dark(useMaterial3: true);
    return MaterialApp.router(
      title: 'НМТ Квіз',
      theme: base.copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4ECDC4),
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(base.textTheme),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardTheme: CardThemeData(
          color: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
      ),
      routerConfig: goRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}
