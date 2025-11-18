import 'package:flutter/material.dart';
import '../services/toast_service.dart';
import 'dart:async';

class CustomToastWidget extends StatefulWidget {
  final ToastData toast;
  final VoidCallback onDismissed;
  const CustomToastWidget({super.key, required this.toast, required this.onDismissed});

  @override
  State<CustomToastWidget> createState() => _CustomToastWidgetState();
}

class _CustomToastWidgetState extends State<CustomToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Timer _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(duration: const Duration(milliseconds: 300), vsync: this);
    _offsetAnimation = Tween<Offset>(begin: const Offset(0.0, -1.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
    _dismissTimer = Timer(const Duration(seconds: 4), _startDismiss);
  }

  void _startDismiss() {
    if (mounted) {
      _controller.reverse().then((_) => widget.onDismissed());
    }
  }

  @override
  void dispose() {
    _dismissTimer.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Map<ToastType, Color> colors = {
      ToastType.success: Colors.green.shade600,
      ToastType.error: Colors.red.shade600,
      ToastType.warning: Colors.orange.shade600,
    };
    Map<ToastType, IconData> icons = {
      ToastType.success: Icons.check_circle_outline,
      ToastType.error: Icons.error_outline,
      ToastType.warning: Icons.warning_amber_rounded,
    };

    return Material(
      color: Colors.transparent,
      child: SlideTransition(
        position: _offsetAnimation,
        // --- SỬA LỖI CĂN GIỮA TẠI ĐÂY ---
        // Bọc Container bằng một widget Center.
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors[widget.toast.type]!,
              borderRadius: BorderRadius.circular(2.0),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min, // Giữ cho Row chỉ rộng bằng nội dung
              children: [
                Icon(icons[widget.toast.type]!, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    widget.toast.message,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    softWrap: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}