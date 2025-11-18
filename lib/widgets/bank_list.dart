class BankInfo {
  final String name;
  final String shortName; // Dùng cho URL
  final String bin;

  BankInfo({required this.name, required this.shortName, required this.bin});
}

final List<BankInfo> vietnameseBanks = [
  BankInfo(name: 'Ngân hàng TMCP Ngoại thương Việt Nam', shortName: 'Vietcombank', bin: '970436'),
  BankInfo(name: 'Ngân hàng TMCP Kỹ thương Việt Nam', shortName: 'Techcombank', bin: '970407'),
  BankInfo(name: 'Ngân hàng TMCP Quân đội', shortName: 'MBbank', bin: '970422'),
  BankInfo(name: 'Ngân hàng TMCP Á Châu', shortName: 'ACB', bin: '970416'),
  BankInfo(name: 'Ngân hàng TMCP Công thương Việt Nam', shortName: 'Vietinbank', bin: '970415'),
  BankInfo(name: 'Ngân hàng TMCP Đầu tư và Phát triển Việt Nam', shortName: 'BIDV', bin: '970418'),
  BankInfo(name: 'Ngân hàng TMCP Việt Nam Thịnh Vượng', shortName: 'VPbank', bin: '970432'),
  BankInfo(name: 'Ngân hàng Nông nghiệp và Phát triển Nông thôn Việt Nam', shortName: 'Agribank', bin: '970405'),
  BankInfo(name: 'Ngân hàng TMCP Sài Gòn Thương Tín', shortName: 'Sacombank', bin: '970403'),
  BankInfo(name: 'Ngân hàng TMCP Tiên Phong', shortName: 'TPbank', bin: '970423'),
  BankInfo(name: 'Ngân hàng TMCP Hàng hải Việt Nam', shortName: 'MSB', bin: '970426'),
  BankInfo(name: 'Ngân hàng TMCP Quốc tế Việt Nam', shortName: 'VIB', bin: '970441'),
  BankInfo(name: 'Ngân hàng TMCP Sài Gòn - Hà Nội', shortName: 'SHB', bin: '970443'),
  BankInfo(name: 'Ngân hàng TMCP Phát triển Thành phố Hồ Chí Minh', shortName: 'HDbank', bin: '970437'),
  BankInfo(name: 'Ngân hàng TMCP Sài Gòn', shortName: 'SCB', bin: '970429'),
  BankInfo(name: 'Ngân hàng TMCP Đông Á', shortName: 'DONGAbank', bin: '970406'),
  BankInfo(name: 'Ngân hàng TMCP Xuất Nhập khẩu Việt Nam', shortName: 'Eximbank', bin: '970431'),
  BankInfo(name: 'Ngân hàng TMCP Bưu điện Liên Việt', shortName: 'LienVietPostbank', bin: '970449'),
  BankInfo(name: 'Ngân hàng TMCP Phương Đông', shortName: 'OCB', bin: '970448'),
];
