import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logger/logger.dart';
import '../../../services/api_service.dart';
import 'game_state.dart';

class GameCubit extends Cubit<GameState> {
  final ApiService apiService;
  final Logger logger;

  GameCubit({required this.apiService, required this.logger})
    : super(const GameInitial());

  Future<void> loadSubjects() async {
    emit(const GameSubjectsLoading());
    try {
      final subjects = await apiService.getSubjects();
      logger.i({
        'feature': 'GameCubit',
        'event': 'subjects.loaded',
        'count': subjects.length,
        'outcome': 'success',
      });
      emit(GameSubjectsLoaded(subjects));
    } catch (e, st) {
      logger.e({
        'feature': 'GameCubit',
        'event': 'subjects.load.failed',
        'currentState': state.runtimeType.toString(),
        'outcome': 'failure',
        'error': e.toString(),
      }, error: e, stackTrace: st);
      emit(const GameError('Не вдалося завантажити предмети'));
    }
  }

  Future<void> createRoom(String subject, int maxPlayers) async {
    emit(const GameCreating());
    try {
      final data = await apiService.createRoom(subject, maxPlayers);
      final code = data['code'] as String;
      logger.i({
        'feature': 'GameCubit',
        'event': 'room.created',
        'roomCode': code,
        'subject': subject,
        'maxPlayers': maxPlayers,
        'outcome': 'success',
      });
      emit(GameCreated(code));
    } catch (e, st) {
      logger.e({
        'feature': 'GameCubit',
        'event': 'room.create.failed',
        'subject': subject,
        'maxPlayers': maxPlayers,
        'outcome': 'failure',
        'error': e.toString(),
      }, error: e, stackTrace: st);
      emit(const GameError('Не вдалося створити кімнату'));
    }
  }
}
