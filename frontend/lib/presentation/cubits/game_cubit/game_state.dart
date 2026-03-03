import 'package:equatable/equatable.dart';

abstract class GameState extends Equatable {
  const GameState();
}

class GameInitial extends GameState {
  const GameInitial();
  @override
  List<Object?> get props => [];
}

class GameCreating extends GameState {
  const GameCreating();
  @override
  List<Object?> get props => [];
}

class GameCreated extends GameState {
  final String roomCode;
  const GameCreated(this.roomCode);
  @override
  List<Object?> get props => [roomCode];
}

class GameError extends GameState {
  final String message;
  const GameError(this.message);
  @override
  List<Object?> get props => [message];
}

class GameSubjectsLoading extends GameState {
  const GameSubjectsLoading();
  @override
  List<Object?> get props => [];
}

class GameSubjectsLoaded extends GameState {
  final List<Map<String, dynamic>> subjects;
  const GameSubjectsLoaded(this.subjects);
  @override
  List<Object?> get props => [subjects];
}
