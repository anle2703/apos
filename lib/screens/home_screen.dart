// lib/screens/home_screen.dart

import 'dart:async';
import 'package:app_4cash/products/order/purchase_orders_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../products/product_list_screen.dart';
import '../bills/bill_history_screen.dart';
import 'auth_gate.dart';
import '../tables/table_list_screen.dart';
import '../tables/table_selection_screen.dart';
import 'settings/settings_screen.dart';
import '../services/print_queue_service.dart';
import 'promotions/promotions_screen.dart';
import 'users/employee_management_screen.dart';
import 'report/report_screen.dart';
import 'contacts/contacts_screen.dart';
import '../screens/payment_methods_screen.dart';
import 'invoice/e_invoice_settings_screen.dart';
import '../tables/qr_order_management_screen.dart';
import 'tax_management_screen.dart';
import 'sales/retail_order_screen.dart';
import '../products/labels/product_label_print_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel? user;

  const HomeScreen({super.key, this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();

  UserModel? _currentUser;
  int _selectedIndex = 2;
  Future<void>? _initializationFuture;
  StreamSubscription? _userStatusSubscription;

  bool _canViewPurchaseOrder = false;
  bool _canViewPromotions = false;
  bool _canViewListTable = false;
  bool _canViewEmployee = false;
  bool _canPrintLabel = false;
  bool _canEditTax = false;
  bool _isShowingTypePicker = false;
  bool _canViewContacts = false;

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeUserAndSettings();
  }

  @override
  void dispose() {
    PrintQueueService().dispose();
    _userStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeUserAndSettings() async {
    UserModel? loadedUser;

    if (widget.user != null) {
      loadedUser = widget.user;
    } else {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        loadedUser = await _firestoreService.getUserProfile(uid);
      }
    }

    if (loadedUser == null) return;

    if (loadedUser.role != 'owner' && loadedUser.ownerUid != null) {
      final ownerProfile =
          await _firestoreService.getUserProfile(loadedUser.ownerUid!);
      if (ownerProfile != null) {
        loadedUser =
            loadedUser.copyWith(businessType: ownerProfile.businessType);
      }
    }

    if (mounted) {
      setState(() {
        _currentUser = loadedUser;
      });
    }

    _listenForUserStatusChanges();

    if (_currentUser != null) {
      await PrintQueueService().initialize(_currentUser!.storeId);
      _checkAndShowBusinessTypePicker();
    }
  }

  void _checkAndShowBusinessTypePicker() {
    if (_currentUser == null) return;
    if (_isShowingTypePicker) return;

    if (_currentUser!.role == 'owner' &&
        (_currentUser!.businessType == null ||
            _currentUser!.businessType!.isEmpty)) {
      _isShowingTypePicker = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showBusinessTypePicker(context);
      });
    }
  }

  void _listenForUserStatusChanges() {
    _userStatusSubscription?.cancel();

    if (_currentUser != null) {
      final navigator = Navigator.of(context);
      _userStatusSubscription = _firestoreService
          .streamUserProfile(_currentUser!.uid)
          .listen((userProfile) {
        if (userProfile == null) {
          _authService.signOut().then((_) {
            navigator.pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const AuthGate()),
                (route) => false);
          });
          return;
        }

        if (!userProfile.active) {
          ToastService().show(
              message: 'Tài khoản của bạn đã bị quản trị viên vô hiệu hóa.',
              type: ToastType.error,
              duration: const Duration(seconds: 4));

          Future.delayed(const Duration(milliseconds: 500), () {
            _authService.signOut().then((_) {
              navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AuthGate()),
                  (route) => false);
            });
          });
          return;
        }

        if (userProfile.role == 'owner') {
          _canViewPurchaseOrder = true;
          _canViewPromotions = true;
          _canViewListTable = true;
          _canViewEmployee = true;
          _canPrintLabel = true;
          _canEditTax = true;
          _canViewContacts = true;
        } else {
          _canViewPurchaseOrder = userProfile.permissions?['purchaseOrder']
                  ?['canViewPurchaseOrder'] ??
              false;
          _canViewPromotions = userProfile.permissions?['promotions']
                  ?['canViewPromotions'] ??
              false;
          _canViewListTable = userProfile.permissions?['listTable']
                  ?['canViewListTable'] ??
              false;
          _canViewEmployee =
              userProfile.permissions?['employee']?['canViewEmployee'] ?? false;
          _canPrintLabel =
              userProfile.permissions?['products']?['canPrintLabel'] ?? false;
          _canEditTax =
              userProfile.permissions?['products']?['canEditTax'] ?? false;
          _canViewContacts =
              userProfile.permissions?['contacts']?['canViewContacts'] ?? false;
        }

        if (mounted) {
          setState(() {
            _currentUser = userProfile.copyWith(
              businessType:
                  userProfile.businessType ?? _currentUser?.businessType,
            );
          });
          _checkAndShowBusinessTypePicker();
        }
      });
    }
  }

  void _showBusinessTypePicker(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return BusinessTypePickerPopup(
          onConfirm: (type) async {
            final navigator = Navigator.of(dialogContext);
            try {
              await _firestoreService
                  .updateUserField(_currentUser!.uid, {'businessType': type});

              navigator.pop();

              if (mounted) {
                setState(() {
                  _currentUser = _currentUser!.copyWith(businessType: type);
                  _isShowingTypePicker = false;
                  _selectedIndex = 0;
                });
              }
            } catch (e) {
              ToastService()
                  .show(message: "Lỗi cập nhật: $e", type: ToastType.error);
            }
          },
        );
      },
    ).then((_) {
      _isShowingTypePicker = false;
    });
  }

  void _onItemTapped(int index) {
    // [MỚI] Kiểm tra quyền truy cập Tab "Đơn hàng" (Index = 2)
    if (index == 1) {
      if (_currentUser?.role == 'order') {
        ToastService().show(
          message: 'Bạn không có quyền truy cập lịch sử Đơn hàng.',
          type: ToastType.warning,
        );
        return; // Dừng lại, không chuyển tab
      }
    }

    // Nếu thỏa mãn điều kiện thì mới chuyển tab
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildCurrentPage() {
    if (_currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // [CẤU TRÚC MỚI]: 0:Sản phẩm, 1:Đơn hàng, 2:Bán hàng, 3:Báo cáo, 4:Khác
    switch (_selectedIndex) {
      case 0: // Vị trí 1 cũ -> Giờ là Sản phẩm
        return ProductListScreen(currentUser: _currentUser!);
      case 1: // Vị trí 2 cũ -> Giờ là Đơn hàng
        return BillHistoryScreen(currentUser: _currentUser!);
      case 2: // Vị trí 0 cũ -> Giờ là Bán hàng (Ở Giữa)
        if (_currentUser!.businessType == 'fnb') {
          return TableSelectionScreen(currentUser: _currentUser!);
        } else {
          return RetailOrderScreen(currentUser: _currentUser!);
        }
      case 3:
        return ReportScreen(currentUser: _currentUser!);
      case 4:
        return Scaffold(
          appBar: AppBar(title: const Text('Khác')),
          body: ListView(
            children: [
              // [MỚI] Nếu là role 'order', ẨN HẾT các mục quản lý
              if (_currentUser?.role != 'order') ...[
                ListTile(
                  leading: const Icon(Icons.add_business_outlined),
                  title: const Text('Quản lý nhập hàng'),
                  onTap: () {
                    if (_currentUser != null && _canViewPurchaseOrder) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => PurchaseOrdersListScreen(
                                currentUser: _currentUser!)),
                      );
                    } else {
                      ToastService().show(
                          message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                if (_currentUser?.businessType == 'retail')
                  ListTile(
                    leading: const Icon(Icons.print_outlined),
                    title: const Text('In tem sản phẩm'),
                    onTap: () {
                      if (_currentUser != null && _canPrintLabel) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => ProductLabelPrintScreen(
                                  currentUser: _currentUser!)),
                        );
                      } else {
                        ToastService().show(
                            message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                            type: ToastType.warning);
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('Phụ thu & Khuyến mãi'),
                  onTap: () {
                    if (_currentUser != null && _canViewPromotions) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                PromotionsScreen(currentUser: _currentUser!)),
                      );
                    } else {
                      ToastService().show(
                          message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                if (_currentUser?.businessType == 'fnb') ...[
                  ListTile(
                    leading: const Icon(Icons.chair_outlined),
                    title: const Text('Quản lý phòng bàn'),
                    onTap: () {
                      if (_currentUser != null && _canViewListTable) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => TableListScreen(
                              currentUser: _currentUser!,
                            ),
                          ),
                        );
                      } else {
                        ToastService().show(
                            message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                            type: ToastType.warning);
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.qr_code_2_outlined),
                    title: const Text('Quản lý QR Order'),
                    onTap: () {
                      if (_currentUser != null && _canViewListTable) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => QrOrderManagementScreen(
                              currentUser: _currentUser!,
                            ),
                          ),
                        );
                      } else {
                        ToastService().show(
                            message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                            type: ToastType.warning);
                      }
                    },
                  ),
                ],
                ListTile(
                  leading: const Icon(Icons.people_alt_outlined),
                  title: const Text('Quản lý nhân viên'),
                  onTap: () {
                    if (_currentUser != null && _canViewEmployee) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => EmployeeManagementScreen(
                            currentUser: _currentUser!,
                          ),
                        ),
                      );
                    } else {
                      ToastService().show(
                          message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.business_center_outlined),
                  title: const Text('Quản lý đối tác'),
                  onTap: () {
                    if (_currentUser != null && _canViewContacts) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ContactsScreen(
                            currentUser: _currentUser!,
                          ),
                        ),
                      );
                    } else {
                      ToastService().show(
                          message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                if (_currentUser!.role == 'owner')
                  ListTile(
                    leading: const Icon(Icons.payment_outlined),
                    title: const Text('Phương thức thanh toán'),
                    onTap: () {
                      if (_currentUser != null) {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) =>
                              PaymentMethodsScreen(currentUser: _currentUser!),
                        ));
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: const Text('Thuế & Kê khai'),
                  onTap: () {
                    if (_currentUser != null && _canEditTax) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) =>
                            TaxManagementScreen(currentUser: _currentUser!),
                      ));
                    } else {
                      ToastService().show(
                          message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Kết nối HĐĐT'),
                  onTap: () {
                    if (_currentUser != null && _canEditTax) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) =>
                            EInvoiceSettingsScreen(currentUser: _currentUser!),
                      ));
                    } else {
                      ToastService().show(
                          message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                const Divider(height: 4, thickness: 0.5, color: Colors.grey),
              ], // --- HẾT PHẦN ẨN ---

              // Hai mục này LUÔN HIỆN cho tất cả role
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Cài đặt'),
                onTap: () {
                  if (_currentUser != null) {
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                      builder: (context) =>
                          SettingsScreen(currentUser: _currentUser!),
                    ))
                        .then((_) {
                      setState(() {
                        _initializationFuture = _initializeUserAndSettings();
                      });
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Đăng xuất'),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await _authService.signOut();
                  navigator.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const AuthGate()),
                        (route) => false,
                  );
                },
              ),
            ],
          ),
        );
      default:
      // Default trả về Bán hàng để an toàn
        if (_currentUser!.businessType == 'fnb') {
          return TableSelectionScreen(currentUser: _currentUser!);
        } else {
          return RetailOrderScreen(currentUser: _currentUser!);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Đã xảy ra lỗi: ${snapshot.error}')),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            const double mobileBreakpoint = 700;
            if (constraints.maxWidth < mobileBreakpoint) {
              return _buildMobileLayout();
            } else {
              return _buildDesktopLayout();
            }
          },
        );
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Icon(Icons.shopping_bag_outlined,
                  size: 40, color: Theme.of(context).primaryColor),
            ),
            destinations: const <NavigationRailDestination>[
              // Index 0: Sản phẩm
              NavigationRailDestination(
                  icon: Icon(Icons.inventory_2),
                  selectedIcon: Icon(Icons.inventory_2_outlined),
                  label: Text('Sản phẩm')),
              // Index 1: Đơn hàng
              NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: Text('Đơn hàng')),
              // Index 2: Bán hàng (Ở giữa)
              NavigationRailDestination(
                  icon: Icon(Icons.add_shopping_cart_outlined),
                  selectedIcon: Icon(Icons.add_shopping_cart),
                  label: Text('Bán hàng')),
              // Index 3: Báo cáo
              NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: Text('Báo cáo')),
              // Index 4: Khác
              NavigationRailDestination(
                  icon: Icon(Icons.more_horiz_outlined),
                  selectedIcon: Icon(Icons.more_horiz),
                  label: Text('Khác')),
            ],
          ),
          Expanded(
            child: _buildCurrentPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      body: _buildCurrentPage(),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          // Index 0: Sản phẩm
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2),
              label: 'Sản phẩm'),
          // Index 1: Đơn hàng
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Đơn hàng'),
          // Index 2: Bán hàng (Ở giữa) - Có thể làm icon to hơn hoặc màu khác nếu muốn
          BottomNavigationBarItem(
              icon: Icon(Icons.add_shopping_cart_outlined),
              activeIcon: Icon(Icons.add_shopping_cart),
              label: 'Bán hàng'),
          // Index 3: Báo cáo
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: 'Báo cáo'),
          // Index 4: Khác
          BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz_outlined),
              activeIcon: Icon(Icons.more_horiz),
              label: 'Khác'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

class BusinessTypePickerPopup extends StatefulWidget {
  final Function(String) onConfirm;

  const BusinessTypePickerPopup({super.key, required this.onConfirm});

  @override
  State<BusinessTypePickerPopup> createState() =>
      _BusinessTypePickerPopupState();
}

class _BusinessTypePickerPopupState extends State<BusinessTypePickerPopup> {
  String? _selectedType;
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title:
          const Text('Chọn Ngành nghề Kinh doanh', textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Lựa chọn này sẽ giúp tối ưu hóa các tính năng cho cửa hàng của bạn.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTypeCard(context,
                  icon: Icons.restaurant_menu, title: 'F&B', value: 'fnb'),
              const SizedBox(width: 16),
              _buildTypeCard(context,
                  icon: Icons.shopping_bag, title: 'Bán lẻ', value: 'retail'),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: (_selectedType == null || _isUpdating)
              ? null
              : () async {
                  setState(() {
                    _isUpdating = true;
                  });

                  await widget.onConfirm(_selectedType!);

                  if (mounted) {
                    setState(() {
                      _isUpdating = false;
                    });
                  }
                },
          child: _isUpdating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Xác nhận'),
        ),
      ],
    );
  }

  Widget _buildTypeCard(BuildContext context,
      {required IconData icon, required String title, required String value}) {
    final bool isSelected = _selectedType == value;
    final color = Theme.of(context).primaryColor;

    return InkWell(
      onTap: _isUpdating ? null : () => setState(() => _selectedType = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(25) : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: isSelected ? color : Colors.grey[600]),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
