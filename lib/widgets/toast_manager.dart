import 'package:flutter/material.dart';
import '../services/toast_service.dart';
import 'custom_toast.dart';

class ToastManager extends StatefulWidget {
  final Widget child;
  const ToastManager({super.key, required this.child});

  @override
  State<ToastManager> createState() => _ToastManagerState();
}

class _ToastManagerState extends State<ToastManager> {
  final ToastService _toastService = ToastService();
  final List<ToastData> _toasts = [];
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();

  @override
  void initState() {
    super.initState();
    _toastService.addListener(_onToastChanged);
  }

  @override
  void dispose() {
    _toastService.removeListener(_onToastChanged);
    super.dispose();
  }

  void _onToastChanged() {
    final serviceToasts = _toastService.toasts;

    for (int i = _toasts.length - 1; i >= 0; i--) {
      if (!serviceToasts.contains(_toasts[i])) {
        final removedToast = _toasts.removeAt(i);
        _listKey.currentState?.removeItem(
          i,
              (context, animation) => _buildToastItem(removedToast, animation),
        );
      }
    }

    for (final toast in serviceToasts) {
      if (!_toasts.contains(toast)) {
        final insertIndex = serviceToasts.indexOf(toast);
        _toasts.insert(insertIndex, toast);
        _listKey.currentState?.insertItem(insertIndex);
      }
    }
  }

  Widget _buildToastItem(ToastData toast, Animation<double> animation) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          child: CustomToastWidget(
            toast: toast,
            // onDismissed không còn cần thiết vì service đã quản lý
            onDismissed: () {},
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. Nội dung chính của ứng dụng
        widget.child,

        // 2. Lớp phủ chứa các thông báo
        // SỬ DỤNG ALIGN ĐỂ CĂN GIỮA
        Align(
          alignment: Alignment.topCenter,
          child: SafeArea( // Đảm bảo không bị tai thỏ/thanh trạng thái che
            child: Padding(
              padding: const EdgeInsets.only(top: 20.0),
              child: IgnorePointer(
                child: AnimatedList(
                  key: _listKey,
                  initialItemCount: _toasts.length,
                  shrinkWrap: true,
                  itemBuilder: (context, index, animation) {
                    return _buildToastItem(_toasts[index], animation);
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}