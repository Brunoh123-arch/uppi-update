import 'package:flutter/material.dart';

class CountUpText extends StatefulWidget {
  final double begin;
  final double end;
  final Duration duration;
  final String Function(double value) formatValue;
  final TextStyle? style;

  const CountUpText({
    super.key,
    required this.begin,
    required this.end,
    this.duration = const Duration(milliseconds: 1500),
    required this.formatValue,
    this.style,
  });

  @override
  State<CountUpText> createState() => _CountUpTextState();
}

class _CountUpTextState extends State<CountUpText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late double _currentBegin;
  late double _currentEnd;

  @override
  void initState() {
    super.initState();
    _currentBegin = widget.begin;
    _currentEnd = widget.end;

    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _animation = Tween<double>(begin: _currentBegin, end: _currentEnd).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _controller.forward();
  }

  @override
  void didUpdateWidget(CountUpText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.end != oldWidget.end) {
      _currentBegin = _animation.value;
      _currentEnd = widget.end;

      _animation = Tween<double>(begin: _currentBegin, end: _currentEnd).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      );

      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Text(
          widget.formatValue(_animation.value),
          style: widget.style,
        );
      },
    );
  }
}
