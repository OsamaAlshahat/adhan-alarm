import 'dart:async';
import 'package:flutter/material.dart';

/// A stepper icon button that responds to single tap as well as continuous long-press hold
class HoldableIconButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback? onPressed;

  const HoldableIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  @override
  State<HoldableIconButton> createState() => _HoldableIconButtonState();
}

class _HoldableIconButtonState extends State<HoldableIconButton> {
  Timer? _holdTimer;
  Timer? _repeatTimer;

  void _stop() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _start() {
    _stop();
    if (widget.onPressed == null) return;
    // After 300ms initial hold, fire repeatedly every 70ms
    _holdTimer = Timer(const Duration(milliseconds: 300), () {
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 70), (_) {
        if (mounted && widget.onPressed != null) {
          widget.onPressed!();
        } else {
          _stop();
        }
      });
    });
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.onPressed != null ? (_) => _start() : null,
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: IconButton.filledTonal(
        icon: widget.icon,
        onPressed: widget.onPressed,
      ),
    );
  }
}

