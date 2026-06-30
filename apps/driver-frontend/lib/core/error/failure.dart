import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:flutter/widgets.dart';

part 'failure.freezed.dart';
part 'failure.g.dart';

@freezed
class Failure with _$Failure {
  const factory Failure({required String message}) = _Failure;

  const factory Failure.error({String? message}) = _OperationFailure;

  const factory Failure.connection({String? message}) = _ConnectionFailure;

  const factory Failure.server({String? message}) = _ServerFailure;

  factory Failure.fromJson(Map<String, dynamic> json) =>
      _$FailureFromJson(json);
}

extension FailureX on Failure {
  String get errorMessage => message ?? 'Ocorreu um erro desconhecido';
  String localizedMessage(BuildContext context) =>
      message ?? 'Ocorreu um erro desconhecido';
}
