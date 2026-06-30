import 'package:freezed_annotation/freezed_annotation.dart';

part 'failure.freezed.dart';

class OperationException {
  final String? message;
  final String? code;

  const OperationException({this.message, this.code});

  @override
  String toString() => 'OperationException(code: $code, message: $message)';

  String get errorMessage => message ?? code ?? 'Unknown error';
}

@freezed
class Failure with _$Failure {
  const factory Failure({required String message}) = _Failure;
  const factory Failure.operation({OperationException? exception}) =
      _OperationFailure;
  const factory Failure.connection({String? message}) = _ConnectionFailure;
  const factory Failure.server({String? message}) = _ServerFailure;

  const Failure._();

  // Non-const convenience used throughout codebase
  static Failure serverError(String? message) =>
      Failure.server(message: message);

  // Alias for backwards-compat - treated as a server error
  static Failure error(String? message) => Failure.server(message: message);

  String get errorMessage {
    return when(
      (msg) => msg,
      operation: (ex) => ex?.errorMessage ?? 'Operation failed',
      connection: (msg) => msg ?? 'Connection error',
      server: (msg) => msg ?? 'Server error',
    );
  }
}
