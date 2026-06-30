part of 'earnings.dart';

@freezed
class EarningsState with _$EarningsState {
  const factory EarningsState({
    required EarningsTimeFrame timeframe,
    required DateTime startDate,
    required DateTime endDate,
    required EarningsPageState pageState,
  }) = _EarningsState;

  const EarningsState._();

  // Permite voltar até no máximo 1 ano atrás.
  bool get canGoBack {
    final now = DateTime.now();
    return startDate.isAfter(DateTime(now.year - 1, now.month, now.day));
  }

  // Só permite avançar se o período exibido terminar antes de hoje.
  bool get canGoForward {
    final now = DateTime.now();
    return endDate.isBefore(DateTime(now.year, now.month, now.day));
  }

  // Estado inicial = dia de HOJE (00:00 → 23:59), com datas na ordem correta
  // (start <= end). A versão antiga invertia start/end e a consulta nunca
  // retornava registros ("Nenhum registro encontrado") até trocar de filtro.
  factory EarningsState.initial() {
    final now = DateTime.now();
    return EarningsState(
      timeframe: EarningsTimeFrame.daily,
      startDate: DateTime(now.year, now.month, now.day),
      endDate: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
      pageState: const EarningsPageState.initial(),
    );
  }
}

@freezed
class EarningsPageState with _$EarningsPageState {
  const factory EarningsPageState.initial() = _Initial;
  const factory EarningsPageState.loading() = _Loading;
  const factory EarningsPageState.loaded({required EarningsDataset dataset}) =
      _Loaded;
  const factory EarningsPageState.empty() = _Empty;
  const factory EarningsPageState.error({required String errorMessage}) =
      _Error;
}
