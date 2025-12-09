import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/service_setup_model.dart';
import '../models/user_model.dart';
import '../widgets/app_dropdown.dart';
import '../theme/number_utils.dart';
import '../services/toast_service.dart';
import '../widgets/custom_text_form_field.dart';

extension TimeOfDayExtension on TimeOfDay {
  String to24hourFormat() {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class ServiceSetupScreen extends StatefulWidget {
  final ServiceSetupModel initialSetup;
  final UserModel currentUser;

  const ServiceSetupScreen({
    super.key,
    required this.initialSetup,
    required this.currentUser,
  });

  @override
  State<ServiceSetupScreen> createState() => _ServiceSetupScreenState();
}

class _ServiceSetupScreenState extends State<ServiceSetupScreen> {
  late ServiceSetupModel _localSetup;

  late final TextEditingController _commissionL1Controller;
  late final TextEditingController _commissionL2Controller;
  late final TextEditingController _commissionL3Controller;

  final _initialDurationController = TextEditingController();
  final _updateIntervalController = TextEditingController();
  final _initialPriceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _localSetup = ServiceSetupModel.fromMap(widget.initialSetup.toMap());

    _commissionL1Controller = TextEditingController(
        text: _formatDouble(_localSetup.commissionLevels['level1']!.value));
    _commissionL2Controller = TextEditingController(
        text: _formatDouble(_localSetup.commissionLevels['level2']!.value));
    _commissionL3Controller = TextEditingController(
        text: _formatDouble(_localSetup.commissionLevels['level3']!.value));
    _initialDurationController.text =
        _localSetup.timePricing.initialDurationMinutes.toString();
    _updateIntervalController.text =
        _localSetup.timePricing.priceUpdateInterval.toString();
    final double initPrice = _localSetup.timePricing.initialPrice;
    _initialPriceController.text = initPrice == 0 ? '0' : formatNumber(initPrice);
  }

  @override
  void dispose() {
    _commissionL1Controller.dispose();
    _commissionL2Controller.dispose();
    _commissionL3Controller.dispose();
    _initialDurationController.dispose();
    _updateIntervalController.dispose();
    _initialPriceController.dispose();
    super.dispose();
  }

  bool _validateTimeFrames({int? ignoreIndex}) {
    final frames = _localSetup.timePricing.timeFrames;
    for (int i = 0; i < frames.length; i++) {
      if (i == ignoreIndex) continue;
      final startInMinutes =
          frames[i].startTime.hour * 60 + frames[i].startTime.minute;
      final endInMinutes =
          frames[i].endTime.hour * 60 + frames[i].endTime.minute;
      if (startInMinutes == endInMinutes) {
        ToastService().show(
            message:
                "Khung giờ #${i + 1}: Giờ bắt đầu và kết thúc không được trùng nhau.",
            type: ToastType.error);
        return false;
      }

      for (int j = i + 1; j < frames.length; j++) {
        if (j == ignoreIndex) continue;
        final bool overlaps = frames[i].overlaps(frames[j]);
        if (overlaps) {
          ToastService().show(
              message:
                  "Khung giờ #${i + 1} và #${j + 1} bị trùng lặp thời gian.",
              type: ToastType.error);
          return false;
        }
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_validateTimeFrames()) {
          Navigator.of(context).pop(_localSetup);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Thiết lập giá dịch vụ'),
          actions: [],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                title: const Text('Kích hoạt tính tiền theo thời gian'),
                value: _localSetup.isTimeBased,
                onChanged: (value) {
                  setState(() => _localSetup.isTimeBased = value);
                },
              ),
              const SizedBox(height: 16),
              if (_localSetup.isTimeBased)
                _buildTimeBasedView()
              else
                _buildCommissionView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeBasedView() {
    // Định nghĩa các input fields ra biến để tái sử dụng
    final intervalField = CustomTextFormField(
      controller: _updateIntervalController,
      decoration: const InputDecoration(labelText: 'Cập nhật giá mỗi (Phút)'),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        _localSetup.timePricing.priceUpdateInterval = int.tryParse(value) ?? 1;
      },
    );

    final durationField = CustomTextFormField(
      controller: _initialDurationController,
      decoration: const InputDecoration(labelText: 'Thời gian tối thiểu (Phút)'),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) {
        _localSetup.timePricing.initialDurationMinutes = int.tryParse(value) ?? 0;
      },
    );

    final initialPriceField = CustomTextFormField(
      controller: _initialPriceController,
      decoration: const InputDecoration(labelText: 'Giá tối thiểu'),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandDecimalInputFormatter()],
      onChanged: (value) {
        _localSetup.timePricing.initialPrice = parseVN(value);
      },
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Desktop (> 600px): 1 hàng 3 cột
            if (constraints.maxWidth > 600) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: intervalField),
                  const SizedBox(width: 16),
                  Expanded(child: durationField),
                  const SizedBox(width: 16),
                  Expanded(child: initialPriceField),
                ],
              );
            } else {
              // Mobile: 3 hàng dọc (Mỗi mục 1 hàng)
              return Column(
                children: [
                  intervalField,
                  const SizedBox(height: 16),
                  durationField,
                  const SizedBox(height: 16),
                  initialPriceField,
                ],
              );
            }
          },
        ),

        const SizedBox(height: 24),
        Text('Giá bán thay đổi theo khung giờ',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.black)),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _localSetup.timePricing.timeFrames.length,
          itemBuilder: (context, index) {
            final frame = _localSetup.timePricing.timeFrames[index];
            return _TimeFrameRow(
              key: ValueKey(frame),
              frame: frame,
              onDelete: () {
                setState(
                        () => _localSetup.timePricing.timeFrames.removeAt(index));
              },
              onChanged: (updatedFrame) {
                final originalFrame = _localSetup.timePricing.timeFrames[index];
                setState(() =>
                _localSetup.timePricing.timeFrames[index] = updatedFrame);
                if (!_validateTimeFrames(ignoreIndex: index)) {
                  setState(() => _localSetup.timePricing.timeFrames[index] =
                      originalFrame);
                }
              },
            );
          },
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Thêm khung giờ'),
          onPressed: () {
            setState(() {
              _localSetup.timePricing.timeFrames.add(TimeFrameModel(
                startTime: const TimeOfDay(hour: 0, minute: 0),
                endTime: const TimeOfDay(hour: 0, minute: 0),
              ));
            });
          },
        )
      ],
    );
  }

  Widget _buildCommissionView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hoa hồng cho nhân viên',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _buildCommissionLevelCard(
            'Nhân viên cấp 1', 'level1', _commissionL1Controller),
        _buildCommissionLevelCard(
            'Nhân viên cấp 2', 'level2', _commissionL2Controller),
        _buildCommissionLevelCard(
            'Nhân viên cấp 3', 'level3', _commissionL3Controller),
      ],
    );
  }

  Widget _buildCommissionLevelCard(
      String title, String levelKey, TextEditingController controller) {
    final commission =
        _localSetup.commissionLevels[levelKey] ?? CommissionValue();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: CustomTextFormField(
                      controller: controller,
                      decoration:
                          const InputDecoration(labelText: 'Giá trị hoa hồng'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandDecimalInputFormatter()],
                      onChanged: (value) {
                        commission.value = parseVN(value);
                      }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: AppDropdown(
                    labelText: 'Đơn vị',
                    value: commission.unit,
                    items: ['VND', '%']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) {
                      // setState ở đây là ĐÚNG, vì ta cần rebuild để cập nhật Dropdown
                      if (v != null) {
                        setState(() {
                          commission.unit = v;
                          _localSetup.commissionLevels[levelKey] = commission;
                        });
                      }
                    },
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }

  String _formatDouble(double value) {
    if (value == 0) return '';
    return formatNumber(value);
  }
}

class _TimeFrameRow extends StatefulWidget {
  final TimeFrameModel frame;
  final VoidCallback onDelete;
  final ValueChanged<TimeFrameModel> onChanged;

  const _TimeFrameRow(
      {super.key,
      required this.frame,
      required this.onDelete,
      required this.onChanged});

  @override
  __TimeFrameRowState createState() => __TimeFrameRowState();
}

class __TimeFrameRowState extends State<_TimeFrameRow> {
  final _priceChangeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _priceChangeController.text = _formatDouble(widget.frame.priceChangeValue);
  }

  @override
  void dispose() {
    _priceChangeController.dispose();
    super.dispose();
  }

  // SỬA LỖI: Cải thiện luồng chọn giờ
  Future<void> _selectTime(bool isStartTime) async {
    final initialTime =
        isStartTime ? widget.frame.startTime : widget.frame.endTime;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText:
          isStartTime ? 'CHỌN THỜI GIAN BẮT ĐẦU' : 'CHỌN THỜI GIAN KẾT THÚC',
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (pickedTime == null) return;

    if (!context.mounted) return;

    if (isStartTime) {
      final tempFrame = widget.frame.copyWith(startTime: pickedTime);
      widget.onChanged(tempFrame);

      final BuildContext safeContext = context;

      final pickedEndTime = await showTimePicker(
        context: safeContext,
        initialTime: widget.frame.endTime,
        helpText: 'CHỌN THỜI GIAN KẾT THÚC',
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          );
        },
      );

      if (!context.mounted) return;

      if (pickedEndTime != null) {
        final finalFrame = tempFrame.copyWith(endTime: pickedEndTime);
        widget.onChanged(finalFrame);
      }
    } else {
      final tempFrame = widget.frame.copyWith(endTime: pickedTime);
      widget.onChanged(tempFrame);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const webBreakpoint = 500.0;
        if (constraints.maxWidth > webBreakpoint) {
          return _buildWebLayout();
        }
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildSharedFields() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: CustomTextFormField(
            controller: _priceChangeController,
            decoration: const InputDecoration(labelText: 'Giá trị + hoặc -'),
            keyboardType: const TextInputType.numberWithOptions(
                signed: true, decimal: true),
            inputFormatters: [ThousandDecimalInputFormatter(allowSigned: true)],
            onChanged: (value) {
              widget.frame.priceChangeValue = parseVN(value);
              widget.onChanged(widget.frame);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: AppDropdown(
            labelText: 'Đơn vị',
            value: widget.frame.priceChangeUnit,
            items: ['VND', '%']
                .map((String v) =>
                    DropdownMenuItem<String>(value: v, child: Text(v)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                // setState ở đây để cập nhật UI cho Dropdown là ĐÚNG
                setState(() {
                  widget.frame.priceChangeUnit = v;
                  widget.onChanged(widget.frame);
                });
              }
            },
          ),
        )
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Khung giờ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: widget.onDelete,
                  splashRadius: 20,
                  visualDensity: VisualDensity.compact,
                )
              ],
            ),
            Row(
              children: [
                Expanded(
                    flex: 2,
                    child: TextButton(
                        onPressed: () => _selectTime(true),
                        child: Text(widget.frame.startTime.to24hourFormat()))),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text('đến')),
                Expanded(
                    flex: 2,
                    child: TextButton(
                        onPressed: () => _selectTime(false),
                        child: Text(widget.frame.endTime.to24hourFormat()))),
              ],
            ),
            const SizedBox(height: 8),
            _buildSharedFields(), // Sử dụng widget chung
          ],
        ),
      ),
    );
  }

  Widget _buildWebLayout() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
                flex: 2,
                child: TextButton(
                    onPressed: () => _selectTime(true),
                    child: Text(widget.frame.startTime.to24hourFormat()))),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Text('Đến')),
            Expanded(
                flex: 2,
                child: TextButton(
                    onPressed: () => _selectTime(false),
                    child: Text(widget.frame.endTime.to24hourFormat()))),
            const SizedBox(width: 16),
            Expanded(flex: 6, child: _buildSharedFields()),
            // Sử dụng widget chung
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: widget.onDelete,
              splashRadius: 20,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDouble(double value) {
    if (value == 0) return '';
    return formatNumber(value);
  }
}
