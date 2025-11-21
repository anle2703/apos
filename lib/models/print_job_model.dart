// File: lib/models/print_job_model.dart

enum PrintJobType {
  kitchen,
  provisional,
  cancel,
  receipt,
  detailedProvisional,
  cashFlow,
  endOfDayReport,
  tableManagement,
  label,
}

PrintJobType _printJobTypeFromString(String? s) {
  switch (s) {
    case 'kitchen':
      return PrintJobType.kitchen;
    case 'provisional':
      return PrintJobType.provisional;
    case 'cancel':
      return PrintJobType.cancel;
    case 'receipt':
      return PrintJobType.receipt;
    case 'detailedProvisional':
      return PrintJobType.detailedProvisional;
    case 'cashFlow':
      return PrintJobType.cashFlow;
    case 'endOfDayReport':
      return PrintJobType.endOfDayReport;
    case 'tableManagement':
      return PrintJobType.tableManagement;
    default:
      return PrintJobType.provisional;
  }
}

class PrintJob {
  final String id;
  final PrintJobType type;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  final String? firestoreId;

  PrintJob({
    required this.id,
    required this.type,
    required this.data,
    required this.createdAt,
    this.firestoreId,
  });

  factory PrintJob.fromJson(Map<String, dynamic> json) {
    DateTime created;
    final rawCreated = json['createdAt'];

    if (rawCreated is DateTime) {
      created = rawCreated;
    } else if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else if (rawCreated is int) {
      created = DateTime.fromMillisecondsSinceEpoch(rawCreated);
    } else {
      try {
        created = (rawCreated as dynamic).toDate();
      } catch (_) {
        created = DateTime.now();
      }
    }

    final String? typeStr = json['type']?.toString();
    final PrintJobType parsedType = _printJobTypeFromString(typeStr);

    return PrintJob(
      id: json['id']?.toString() ?? '',
      type: parsedType,
      data: Map<String, dynamic>.from(json['data'] ?? {}),
      createdAt: created,
      firestoreId: json['firestoreId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'data': data,
      'createdAt': createdAt.toIso8601String(),
      'firestoreId': firestoreId,
    };
  }

  PrintJob copyWith({String? firestoreId}) {
    return PrintJob(
      id: id,
      type: type,
      data: data,
      createdAt: createdAt,
      firestoreId: firestoreId ?? this.firestoreId,
    );
  }
}