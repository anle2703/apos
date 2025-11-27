import 'dart:convert';

class VietQrGenerator {
  static String generate({
    required String bankBin,
    required String bankAccount,
    required String amount,
    required String description,
  }) {
    final sb = StringBuffer();

    // 00: Payload Format Indicator
    sb.write(_f("00", "01"));
    // 01: Point of Initiation Method (11 = Static, 12 = Dynamic)
    sb.write(_f("01", amount.isNotEmpty ? "12" : "11"));

    // --- 38: Merchant Account Information ---
    final merchantInfo = StringBuffer();
    merchantInfo.write(_f("00", "A000000727")); // GUID VietQR

    // Beneficiary Organization
    final beneficiaryInfo = StringBuffer();
    beneficiaryInfo.write(_f("00", bankBin));
    beneficiaryInfo.write(_f("01", bankAccount));

    merchantInfo.write(_f("01", beneficiaryInfo.toString()));
    merchantInfo.write(_f("02", "QRIBFTTA")); // Service Code

    sb.write(_f("38", merchantInfo.toString()));
    // ----------------------------------------

    // 53: Transaction Currency
    sb.write(_f("53", "704")); // VND

    // 54: Transaction Amount
    if (amount.isNotEmpty && amount != "0") {
      sb.write(_f("54", amount));
    }

    // 58: Country Code
    sb.write(_f("58", "VN"));

    // 62: Additional Data Field (Nội dung chuyển khoản)
    if (description.isNotEmpty) {
      // --- SỬA Ở ĐÂY: Xóa dấu tiếng Việt trước khi đưa vào QR ---
      final cleanDescription = _removeAccents(description);

      final additionalInfo = StringBuffer();
      // Tag 08: Purpose of Transaction
      additionalInfo.write(_f("08", cleanDescription));
      sb.write(_f("62", additionalInfo.toString()));
    }

    // 63: CRC
    final dataSoFar = "${sb.toString()}6304";
    final crc = _calcCrc(dataSoFar);
    return "$dataSoFar$crc";
  }

  // Helper format TLV
  static String _f(String id, String value) {
    return "$id${value.length.toString().padLeft(2, '0')}$value";
  }

  // Hàm tính CRC16
  static String _calcCrc(String data) {
    int crc = 0xFFFF;
    final bytes = utf8.encode(data);

    for (final byte in bytes) {
      crc ^= (byte << 8);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = (crc << 1) ^ 0x1021;
        } else {
          crc <<= 1;
        }
      }
    }
    return (crc & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  // --- HÀM MỚI: CHUYỂN TIẾNG VIỆT CÓ DẤU THÀNH KHÔNG DẤU ---
  static String _removeAccents(String str) {
    const vietnamese = 'aAeEoOuUiIdDyY';
    final pattern = <String>[
      'áàảãạăắằẳẵặâấầẩẫậ',
      'ÁÀẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬ',
      'éèẻẽẹêếềểễệ',
      'ÉÈẺẼẸÊẾỀỂỄỆ',
      'óòỏõọôốồổỗộơớờởỡợ',
      'ÓÒỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢ',
      'úùủũụưứừửữự',
      'ÚÙỦŨỤƯỨỪỬỮỰ',
      'íìỉĩị',
      'ÍÌỈĨỊ',
      'đ',
      'Đ',
      'ýỳỷỹỵ',
      'ÝỲỶỸỴ'
    ];

    var result = str;
    for (int i = 0; i < pattern.length; i++) {
      for (int j = 0; j < pattern[i].length; j++) {
        result = result.replaceAll(pattern[i][j], vietnamese[i]);
      }
    }
    return result;
  }
}