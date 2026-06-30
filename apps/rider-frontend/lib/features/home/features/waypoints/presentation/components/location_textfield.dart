import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:flutter_common/core/color_palette/color_palette.dart';
import 'package:flutter_common/core/entities/place.dart';
import 'package:rider_flutter/core/extensions/extensions.dart';
import 'package:flutter_common/core/utils/uppi_haptics.dart';
import 'package:rider_flutter/features/home/features/waypoints/presentation/blocs/selected_location_field.dart';
import 'package:rider_flutter/config/locator/locator.dart';

class LocationTextfield extends StatefulWidget {
  final int index;
  final int totalCount;
  final Function(String?) onChanged;
  final PlaceEntity? initialValue;
  final Function() onFocused;
  final Function() onRemoveStop;
  final Function(int) onMapPressed;
  final bool? isFocused;

  const LocationTextfield({
    super.key,
    required this.onChanged,
    required this.index,
    required this.totalCount,
    required this.initialValue,
    required this.onFocused,
    required this.onRemoveStop,
    required this.onMapPressed,
    this.isFocused,
  });

  @override
  State<LocationTextfield> createState() => _LocationTextfieldState();
}

class _LocationTextfieldState extends State<LocationTextfield> {
  bool isFocused = false;
  final focusNode = FocusNode();
  late TextEditingController _controller;
  String? value;

  @override
  void initState() {
    super.initState();
    value = widget.initialValue?.address;
    isFocused = widget.isFocused ?? false;
    _controller = TextEditingController(text: widget.initialValue?.address);
    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        UppiHaptics.selection();
        widget.onFocused();
      }
      setState(() {
        isFocused = focusNode.hasFocus;
      });
    });
    if (isFocused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && focusNode.canRequestFocus) {
            focusNode.requestFocus();
          }
        });
      });
    }
  }

  @override
  void didUpdateWidget(covariant LocationTextfield oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isFocused != oldWidget.isFocused && widget.isFocused != null) {
      setState(() {
        isFocused = widget.isFocused!;
      });
      if (isFocused) {
        if (!focusNode.hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (focusNode.canRequestFocus) {
              focusNode.requestFocus();
            }
          });
        }
      } else {
        if (focusNode.hasFocus) {
          focusNode.unfocus();
        }
      }
    }
    if (widget.initialValue?.address != oldWidget.initialValue?.address) {
      final newAddress = widget.initialValue?.address ?? '';
      if (_controller.text != newAddress) {
        setState(() {
          value = newAddress;
          _controller.text = newAddress;
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        });
      }
    }
  }

  @override
  void dispose() {
    focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.theme.brightness == Brightness.dark;
    
    // Cores e acabamento integrado com o tema do Uppi, sem custos de GPU de blur.
    final fillColor = context.theme.inputDecorationTheme.fillColor ??
        (isDark ? Colors.grey[900]! : Colors.grey[100]!);
    final borderColor = isFocused 
        ? context.theme.colorScheme.primary.withValues(alpha: 0.4) 
        : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.05));

    final hasText = value?.isNotEmpty ?? false;
    final showClearButton = hasText && isFocused;

    return Row(
      children: [
        // 🧪 A Barra de Pesquisa Animada
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.fastOutSlowIn,
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: borderColor,
                width: 1.5,
              ),
              boxShadow: isFocused ? [
                BoxShadow(
                  color: context.theme.colorScheme.primary.withValues(alpha: 0.08),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 2),
                )
              ] : null,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Label Text Animada
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: (isFocused || hasText) ? 1.0 : 0.0,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: (isFocused || hasText) ? 16 : 0,
                            child: Text(
                              labelText(context),
                              style: context.bodySmall?.copyWith(
                                color: labelColor(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        TextFormField(
                          onChanged: (newValue) {
                            widget.onChanged(newValue);
                            setState(() {
                              value = newValue;
                            });
                          },
                          focusNode: focusNode,
                          controller: _controller,
                          textAlign: (isFocused || hasText) ? TextAlign.left : TextAlign.center,
                          style: context.bodyLarge?.copyWith(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 4),
                            hintText: hintText(context),
                            hintStyle: context.bodyLarge?.copyWith(
                              color: ColorPalette.neutralVariant70,
                              fontWeight: FontWeight.w400,
                            ),
                            suffix: Transform.translate(
                              offset: const Offset(0, 0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Botão de Limpar com Escala e Opacidade Animadas (Mola)
                                  AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: showClearButton ? 1.0 : 0.0,
                                    child: AnimatedScale(
                                      duration: const Duration(milliseconds: 300),
                                      scale: showClearButton ? 1.0 : 0.0,
                                      curve: Curves.easeOutBack,
                                      child: showClearButton 
                                        ? CupertinoButton(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            onPressed: () {
                                              UppiHaptics.selection();
                                              _controller.clear();
                                              widget.onChanged(null);
                                              setState(() {
                                                value = '';
                                              });
                                            },
                                            minimumSize: Size.zero,
                                            child: const Icon(
                                              Ionicons.close_circle,
                                              size: 18,
                                              color: ColorPalette.neutralVariant80,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                    ),
                                  ),
                                  if (isFocused)
                                    Container(
                                      width: 1,
                                      height: 20,
                                      margin: const EdgeInsets.symmetric(horizontal: 6),
                                      color: isDark ? Colors.white24 : Colors.black12,
                                    ),
                                  CupertinoButton(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    onPressed: () {
                                      UppiHaptics.mechanicalClick();
                                      widget.onMapPressed(widget.index);
                                    },
                                    minimumSize: Size.zero,
                                    child: Icon(
                                      Ionicons.map,
                                      size: 20,
                                      color: context.theme.colorScheme.primary,
                                    ),
                                  )
                                ],
                              ),
                            ),
                            fillColor: Colors.transparent,
                            focusColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 🚀 Botão Cancelar Estilo iOS com Física de Mola na Largura
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.fastOutSlowIn,
          width: isFocused ? 90 : 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isFocused ? 1.0 : 0.0,
            child: isFocused
              ? Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      UppiHaptics.selection();
                      focusNode.unfocus();
                      locator<SelectedLocationFieldCubit>().onLocationFieldSelected(null);
                    },
                    child: Text(
                      context.translate.cancel,
                      style: context.bodyLarge?.copyWith(
                        color: context.theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                    ),
                  ),
                )
              : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }

  Color labelColor(BuildContext context) => isFocused
      ? context.theme.colorScheme.primary
      : context.theme.colorScheme.onSurfaceVariant;

  String labelText(BuildContext context) => widget.index == 0
      ? context.translate.pickupPoint
      : ((widget.index < (widget.totalCount - 1))
          ? context.translate.stopPoint
          : context.translate.dropoffPoint);

  String hintText(BuildContext context) => widget.index == 0
      ? context.translate.enterPickupPoint
      : ((widget.index < (widget.totalCount - 1))
          ? context.translate.enterStopPoint
          : context.translate.enterDropoffPoint);
}
