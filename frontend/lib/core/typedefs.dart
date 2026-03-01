import 'package:fpdart/fpdart.dart';
import 'failures.dart';

typedef FutureEither<T> = Future<Either<Failure, T>>;
typedef EitherT<T> = Either<Failure, T>;
