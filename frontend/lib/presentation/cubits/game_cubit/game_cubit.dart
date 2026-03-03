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
      logger.i('[GameCubit] subjects loaded | count=${subjects.length}');
      emit(GameSubjectsLoaded(subjects));
    } catch (e) {
      logger.e('[GameCubit] loadSubjects failed | err=$e');
      emit(const GameError('Не вдалося завантажити предмети'));
    }
  }

  Future<void> createRoom(String subject, int maxPlayers) async {
    emit(const GameCreating());
    try {
      final data = await apiService.createRoom(subject, maxPlayers);
      final code = data['code'] as String;
      logger.i('[GameCubit] room created | code=$code');
      emit(GameCreated(code));
    } catch (e) {
      logger.e('[GameCubit] ERROR create room failed | err=$e');
      emit(const GameError('Не вдалося створити кімнату'));
    }
  }
}
