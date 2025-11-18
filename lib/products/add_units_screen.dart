import 'package:flutter/material.dart';
import '../models/unit_model.dart';
import '../theme/app_theme.dart';
import '../services/toast_service.dart';
import '../theme/number_utils.dart';
import '../widgets/custom_text_form_field.dart';

class AddUnitsScreen extends StatefulWidget {
  final String baseUnitName;
  final String? productType;
  final List<UnitModel> initialUnits;
  final bool manageStockSeparately;

  const AddUnitsScreen({
    super.key,
    required this.baseUnitName,
    this.productType,
    required this.initialUnits,
    this.manageStockSeparately = false,
  });

  @override
  State<AddUnitsScreen> createState() => _AddUnitsScreenState();
}

class _AddUnitsScreenState extends State<AddUnitsScreen> {
  late List<UnitModel> _units;
  bool _manageStockSeparately = false;

  @override
  void initState() {
    super.initState();
    _units = List.from(widget.initialUnits);
    _manageStockSeparately = widget.manageStockSeparately;
    if (_units.isEmpty) {
      _addNewUnit();
    }
  }

  void _addNewUnit() {
    setState(() {
      _units.add(UnitModel(
        unitName: '',
        sellPrice: 0,
        costPrice: 0,
        stock: 0,
        conversionFactor: 1.0,
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    bool isFinishedGood = widget.productType == 'Thành phẩm/Combo';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final validUnits = _units.where((u) {
          return u.unitName.trim().isNotEmpty;
        }).toList();
        final hasInvalidConversion = validUnits.any((u) {
          return !_manageStockSeparately && u.conversionFactor <= 0;
        });

        if (hasInvalidConversion) {
          ToastService().show(
            message: 'Hệ số quy đổi phải lớn hơn 0',
            type: ToastType.error,
          );
          return;
        }
        Navigator.of(context).pop({
          'units': validUnits,
          'manageStockSeparately': _manageStockSeparately,
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('ĐVT quy đổi cho "${widget.baseUnitName}"'),
          actions: [
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            const double mobileBreakpoint = 800;
            bool isDesktop = constraints.maxWidth >= mobileBreakpoint;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (!isFinishedGood)
                        Expanded(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Quản lý tồn kho riêng',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.black),
                              ),
                              const SizedBox(width: 8),
                              Transform.scale(
                                scale: 1,
                                child: Switch(
                                  value: _manageStockSeparately,
                                  onChanged: (value) {
                                    setState(() {
                                      _manageStockSeparately = value;
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _units.length,
                    itemBuilder: (context, index) {
                      return UnitInputCard(
                        key: ValueKey(_units[index].id),
                        unit: _units[index],
                        baseUnitName: widget.baseUnitName,
                        isDesktop: isDesktop,
                        manageStockSeparately: _manageStockSeparately,
                        showDeleteButton: _units.length > 1,
                        onRemove: () {
                          setState(() => _units.removeAt(index));
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _addNewUnit,
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm đơn vị tính'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primaryColor,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class UnitInputCard extends StatefulWidget {
  final UnitModel unit;
  final String baseUnitName;
  final bool isDesktop;
  final bool manageStockSeparately;
  final bool showDeleteButton;
  final VoidCallback onRemove;

  const UnitInputCard({
    super.key,
    required this.unit,
    required this.baseUnitName,
    required this.isDesktop,
    required this.manageStockSeparately,
    required this.showDeleteButton,
    required this.onRemove,
  });

  @override
  State<UnitInputCard> createState() => _UnitInputCardState();
}

class _UnitInputCardState extends State<UnitInputCard> {
  late TextEditingController _unitNameController;
  late TextEditingController _sellPriceController;
  late TextEditingController _costPriceController;
  late TextEditingController _stockController;
  late TextEditingController _conversionFactorController;

  @override
  void initState() {
    super.initState();
    _unitNameController = TextEditingController(text: widget.unit.unitName);
    _sellPriceController = TextEditingController(
      text:
          widget.unit.sellPrice == 0 ? '' : formatNumber(widget.unit.sellPrice),
    );
    _costPriceController = TextEditingController(
      text:
          widget.unit.costPrice == 0 ? '' : formatNumber(widget.unit.costPrice),
    );
    _stockController = TextEditingController(
      text: widget.unit.stock == 0 ? '' : formatNumber(widget.unit.stock),
    );
    _conversionFactorController = TextEditingController(
      text: widget.unit.conversionFactor == 0
          ? '1'
          : (widget.unit.conversionFactor % 1 == 0
              ? widget.unit.conversionFactor.toInt().toString()
              : widget.unit.conversionFactor.toString()),
    );
  }

  @override
  void dispose() {
    _unitNameController.dispose();
    _sellPriceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _conversionFactorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Đơn vị tính phụ',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.black)),
                  if (widget.showDeleteButton)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: widget.onRemove,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              widget.isDesktop
                  ? _buildDesktopInputLayout()
                  : _buildMobileInputLayout(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileInputLayout() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildUnitNameField()),
            const SizedBox(width: 16),
            Expanded(child: _buildSellPriceField()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildCostPriceField()),
            const SizedBox(width: 16),
            Expanded(child: _buildStockOrConversionField()), // theo flag chung
          ],
        ),
      ],
    );
  }

  Widget _buildDesktopInputLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildUnitNameField()),
        const SizedBox(width: 16),
        Expanded(child: _buildSellPriceField()),
        const SizedBox(width: 16),
        Expanded(child: _buildCostPriceField()),
        const SizedBox(width: 16),
        Expanded(child: _buildStockOrConversionField()), // theo flag chung
      ],
    );
  }

  // --- HELPER INPUT ---
  Widget _buildUnitNameField() {
    return CustomTextFormField(
      controller: _unitNameController,
      decoration: const InputDecoration(
        labelText: 'Đơn vị tính (Vd: Lốc/Thùng)',
        prefixIcon: Icon(Icons.straighten_outlined),
      ),
      onChanged: (value) => widget.unit.unitName = value,
    );
  }

  Widget _buildSellPriceField() {
    return CustomTextFormField(
      controller: _sellPriceController,
      decoration: const InputDecoration(
        labelText: 'Giá bán',
        prefixIcon: Icon(Icons.attach_money),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandDecimalInputFormatter()],
      onChanged: (value) => widget.unit.sellPrice = parseVN(value),
    );
  }

  Widget _buildCostPriceField() {
    return CustomTextFormField(
      controller: _costPriceController,
      decoration: const InputDecoration(
        labelText: 'Giá vốn',
        prefixIcon: Icon(Icons.money_off),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandDecimalInputFormatter()],
      onChanged: (value) => widget.unit.costPrice = parseVN(value),
    );
  }

  Widget _buildStockOrConversionField() {
    if (widget.manageStockSeparately) {
      return CustomTextFormField(
        controller: _stockController,
        decoration: const InputDecoration(
          labelText: 'Tồn kho',
          prefixIcon: Icon(Icons.inventory_2_outlined),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [ThousandDecimalInputFormatter()],
        onChanged: (value) => widget.unit.stock = parseVN(value),
      );
    } else {
      return CustomTextFormField(
        controller: _conversionFactorController,
        decoration: InputDecoration(
          labelText: 'Hệ số quy đổi',
          hintText:
              '1 ${_unitNameController.text.isNotEmpty ? _unitNameController.text : 'ĐVT phụ'} = ? ${widget.baseUnitName}',
          prefixIcon: const Icon(Icons.sync_alt_rounded),
        ),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (value) =>
            widget.unit.conversionFactor = double.tryParse(value) ?? 0,
      );
    }
  }
}
