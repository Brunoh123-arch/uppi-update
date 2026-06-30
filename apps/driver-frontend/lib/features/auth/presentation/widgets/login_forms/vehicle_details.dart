import 'package:uppi_motorista/config/locator/locator.dart';
import 'package:uppi_motorista/core/extensions/extensions.dart';
import 'package:uppi_motorista/features/auth/presentation/blocs/login.dart';
import 'package:uppi_motorista/core/entities/vehicle_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_common/core/presentation/buttons/app_primary_button.dart';
import 'package:flutter_common/core/utils/uppercase_input_formatter.dart';

class VehicleDetails extends StatefulWidget {
  final LoginState state;

  const VehicleDetails({super.key, required this.state});

  @override
  State<VehicleDetails> createState() => _VehicleDetailsState();
}

class _VehicleDetailsState extends State<VehicleDetails> {
  final GlobalKey<FormState> formKey = GlobalKey();

  bool _showCustomModel = false;
  bool _showCustomColor = false;

  final TextEditingController _customModelController = TextEditingController();
  final TextEditingController _customColorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkInitialCustomValues();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.state.vehicleModels.isEmpty || widget.state.vehicleColors.isEmpty) {
        locator<LoginBloc>().loadRegistrationData();
      }
    });
  }

  void _checkInitialCustomValues() {
    final modelId = widget.state.profileFullEntity?.vehicleModelId;
    if (modelId != null && modelId.isNotEmpty) {
      final isOfficial = widget.state.vehicleModels.any((e) => e.id == modelId);
      final isOutro = widget.state.vehicleModels.any((e) => e.id == modelId && e.name.toLowerCase() == 'outro');
      if (!isOfficial || isOutro) {
        _showCustomModel = true;
        _customModelController.text = isOutro ? '' : modelId;
      }
    }

    final colorId = widget.state.profileFullEntity?.vehicleColorId;
    if (colorId != null && colorId.isNotEmpty) {
      final isOfficial = widget.state.vehicleColors.any((e) => e.id == colorId);
      final isOutra = widget.state.vehicleColors.any((e) => e.id == colorId && e.name.toLowerCase() == 'outra');
      if (!isOfficial || isOutra) {
        _showCustomColor = true;
        _customColorController.text = isOutra ? '' : colorId;
      }
    }
  }

  @override
  void dispose() {
    _customModelController.dispose();
    _customColorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loginBloc = locator<LoginBloc>();

    // Definir valor controlado para o Dropdown do Modelo (trata strings livres do banco)
    final selectedCategory = widget.state.profileFullEntity?.vehicleCategory ?? 'carro';
    final filteredModels = widget.state.vehicleModels
        .where((e) => e.category == selectedCategory)
        .toList();

    String? currentModelValue;
    final dbModelId = widget.state.profileFullEntity?.vehicleModelId;
    if (dbModelId != null && dbModelId.isNotEmpty) {
      if (filteredModels.any((e) => e.id == dbModelId)) {
        currentModelValue = dbModelId;
      } else {
        // Se for string livre digitada antes, seleciona 'Outro'
        final outroItem = filteredModels.firstWhere(
          (e) => e.name.toLowerCase() == 'outro',
          orElse: () => filteredModels.isNotEmpty ? filteredModels.first : VehicleModelEntity(id: '', name: ''),
        );
        currentModelValue = outroItem.id.isNotEmpty ? outroItem.id : null;
      }
    }

    // Definir valor controlado para o Dropdown da Cor
    String? currentColorValue;
    final dbColorId = widget.state.profileFullEntity?.vehicleColorId;
    if (dbColorId != null && dbColorId.isNotEmpty) {
      if (widget.state.vehicleColors.any((e) => e.id == dbColorId)) {
        currentColorValue = dbColorId;
      } else {
        final outraItem = widget.state.vehicleColors.firstWhere(
          (e) => e.name.toLowerCase() == 'outra',
          orElse: () => widget.state.vehicleColors.first,
        );
        currentColorValue = outraItem.id;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Para alterar estas informações no futuro, você precisará contatar o suporte.",
                    style: context.bodyMedium?.copyWith(
                      color: context.theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FormField<String>(
                    initialValue: widget.state.profileFullEntity?.vehicleCategory ?? 'carro',
                    validator: (value) => value == null || value.isEmpty
                        ? "Selecione o tipo de veículo"
                        : null,
                    onSaved: loginBloc.onVehicleCategoryChanged,
                    builder: (FormFieldState<String> formState) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Tipo de Veículo",
                            style: context.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _buildVehicleTypeCard(
                                context,
                                type: 'carro',
                                label: 'Carro',
                                icon: Icons.directions_car_rounded,
                                isSelected: formState.value == 'carro',
                                onTap: () {
                                  formState.didChange('carro');
                                  loginBloc.onVehicleCategoryChanged('carro');
                                  loginBloc.onVehicleModelIdChanged(null);
                                  setState(() { _showCustomModel = false; _customModelController.clear(); });
                                },
                              ),
                              const SizedBox(width: 10),
                              _buildVehicleTypeCard(
                                context,
                                type: 'moto',
                                label: 'Moto',
                                icon: Icons.motorcycle_rounded,
                                isSelected: formState.value == 'moto',
                                onTap: () {
                                  formState.didChange('moto');
                                  loginBloc.onVehicleCategoryChanged('moto');
                                  loginBloc.onVehicleModelIdChanged(null);
                                  setState(() { _showCustomModel = false; _customModelController.clear(); });
                                },
                              ),
                              const SizedBox(width: 10),
                              _buildVehicleTypeCard(
                                context,
                                type: 'eletrico',
                                label: 'Elétrico',
                                icon: Icons.electric_car_rounded,
                                isSelected: formState.value == 'eletrico',
                                onTap: () {
                                  formState.didChange('eletrico');
                                  loginBloc.onVehicleCategoryChanged('eletrico');
                                  loginBloc.onVehicleModelIdChanged(null);
                                  setState(() { _showCustomModel = false; _customModelController.clear(); });
                                },
                              ),
                            ],
                          ),
                          if (formState.hasError) ...[
                            const SizedBox(height: 8),
                            Text(
                              formState.errorText ?? '',
                              style: context.bodySmall?.copyWith(
                                color: context.theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    initialValue: widget.state.profileFullEntity?.vehiclePlateNumber,
                    inputFormatters: [UpperCaseTextFormatter()],
                    textCapitalization: TextCapitalization.characters,
                    validator: (value) => value?.isEmpty == true
                        ? context.translate.fieldIsRequired
                        : null,
                    onSaved: loginBloc.onPlateNumberChanged,
                    decoration: InputDecoration(
                      hintText: context.translate.vehiclePlateNumber,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      DateInputFormatter(),
                    ],
                    keyboardType: TextInputType.number,
                    initialValue: () {
                      final val = widget.state.profileFullEntity?.vehicleProductionYear;
                      if (val == null) return null;
                      final s = val.toString();
                      if (s.length == 8) {
                        return '${s.substring(0, 2)}/${s.substring(2, 4)}/${s.substring(4, 8)}';
                      }
                      return s;
                    }(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return context.translate.fieldIsRequired;
                      }
                      final digits = value.replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 4 && digits.length != 8) {
                        return "Digite o ano (Ex: 2023) ou data (Ex: 25/10/2026)";
                      }
                      if (digits.length == 4) {
                        final year = int.tryParse(digits);
                        if (year == null || year < 1900 || year > DateTime.now().year + 2) {
                          return "Ano inválido (Ex: 2023)";
                        }
                      } else if (digits.length == 8) {
                        final day = int.tryParse(digits.substring(0, 2));
                        final month = int.tryParse(digits.substring(2, 4));
                        final year = int.tryParse(digits.substring(4, 8));
                        if (day == null || day < 1 || day > 31 ||
                            month == null || month < 1 || month > 12 ||
                            year == null || year < 1900 || year > DateTime.now().year + 10) {
                          return "Data inválida (Ex: 25/10/2026)";
                        }
                      }
                      return null;
                    },
                    onSaved: (value) {
                      if (value != null && value.isNotEmpty) {
                        final digits = value.replaceAll(RegExp(r'\D'), '');
                        final intVal = int.tryParse(digits);
                        if (intVal != null) {
                          loginBloc.onVehicleProductionYearChanged(intVal);
                        }
                      }
                    },
                    decoration: InputDecoration(
                      hintText: '${context.translate.vehicleProductionYear} (Ex: 25/10/2026 ou 2023)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    style: context.labelLarge,
                    initialValue: currentModelValue,
                    items: filteredModels
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e.id,
                            child: Text(e.name, style: context.labelLarge),
                          ),
                        )
                        .toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        final selected = widget.state.vehicleModels.firstWhere((e) => e.id == newValue);
                        setState(() {
                          _showCustomModel = selected.name.toLowerCase() == 'outro';
                          if (!_showCustomModel) {
                            _customModelController.clear();
                          }
                        });
                        loginBloc.onVehicleModelIdChanged(newValue);
                      }
                    },
                    onSaved: (newValue) {
                      if (_showCustomModel && _customModelController.text.isNotEmpty) {
                        loginBloc.onVehicleModelIdChanged(_customModelController.text);
                      } else {
                        loginBloc.onVehicleModelIdChanged(newValue);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: context.translate.vehicleModelAndMake,
                    ),
                  ),
                  if (_showCustomModel) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customModelController,
                      validator: (value) => value?.isEmpty == true
                          ? "Digite o modelo e marca do veículo"
                          : null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: "Modelo e Marca (Ex: Chevrolet Celta 1.0)",
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    style: context.labelLarge,
                    initialValue: currentColorValue,
                    items: widget.state.vehicleColors
                        .map(
                          (e) => DropdownMenuItem<String>(
                            value: e.id,
                            child: Text(e.name, style: context.labelLarge),
                          ),
                        )
                        .toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        final selected = widget.state.vehicleColors.firstWhere((e) => e.id == newValue);
                        setState(() {
                          _showCustomColor = selected.name.toLowerCase() == 'outra';
                          if (!_showCustomColor) {
                            _customColorController.clear();
                          }
                        });
                        loginBloc.onVehicleColorIdChanged(newValue);
                      }
                    },
                    onSaved: (newValue) {
                      if (_showCustomColor && _customColorController.text.isNotEmpty) {
                        loginBloc.onVehicleColorIdChanged(_customColorController.text);
                      } else {
                        loginBloc.onVehicleColorIdChanged(newValue);
                      }
                    },
                    decoration: InputDecoration(
                      hintText: context.translate.vehicleColor,
                    ),
                  ),
                  if (_showCustomColor) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _customColorController,
                      validator: (value) => value?.isEmpty == true
                          ? "Digite a cor do veículo"
                          : null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: "Cor do Veículo (Ex: Vermelho Metálico)",
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        AppPrimaryButton(
          onPressed: () {
            if (formKey.currentState?.validate() == true) {
              formKey.currentState?.save();
              loginBloc.onConfirmVehicleDetailsPressed();
            }
          },
          child: Text(context.translate.confirm),
        ),
      ],
    );
  }

  Widget _buildVehicleTypeCard(
    BuildContext context, {
    required String type,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = context.theme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 28,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: context.labelMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String newText = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (newText.length > 8) {
      newText = newText.substring(0, 8);
    }

    String formattedText = '';
    for (int i = 0; i < newText.length; i++) {
      if (i == 2 || i == 4) {
        formattedText += '/';
      }
      formattedText += newText[i];
    }

    return TextEditingValue(
      text: formattedText,
      selection: TextSelection.collapsed(offset: formattedText.length),
    );
  }
}
