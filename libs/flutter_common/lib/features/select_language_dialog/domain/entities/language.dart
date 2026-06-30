import 'package:freezed_annotation/freezed_annotation.dart';

part 'language.freezed.dart';

@freezed
class Language with _$Language {
  const Language._();
  const factory Language({
    required String imagePath,
    required String name,
    required String code,
  }) = _Language;
}