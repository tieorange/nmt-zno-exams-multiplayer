import 'package:equatable/equatable.dart';
import '../../../data/models/player_model.dart';

enum RoomStatus { initial, waiting, playing, finished, error }

class RoomState extends Equatable {
  final String code;
  final String subject;
  final RoomStatus status;
  final int maxPlayers;
  final List<PlayerModel> players;
  final String? errorMessage;

  // Sentinel value to detect if errorMessage was explicitly passed
  static const _errorMessageUnset = Object();

  const RoomState({
    this.code = '',
    this.subject = '',
    this.status = RoomStatus.initial,
    this.maxPlayers = 4,
    this.players = const [],
    this.errorMessage,
  });

  RoomState copyWith({
    String? code,
    String? subject,
    RoomStatus? status,
    int? maxPlayers,
    List<PlayerModel>? players,
    Object? errorMessage = _errorMessageUnset,
  }) => RoomState(
    code: code ?? this.code,
    subject: subject ?? this.subject,
    status: status ?? this.status,
    maxPlayers: maxPlayers ?? this.maxPlayers,
    players: players ?? this.players,
    errorMessage: identical(errorMessage, _errorMessageUnset)
        ? this.errorMessage
        : errorMessage as String?,
  );

  @override
  List<Object?> get props => [code, subject, status, maxPlayers, players, errorMessage];
}
