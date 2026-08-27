/// Bank account details for Fruity Farms — CIB Egypt
class BankDetails {
  final String bankName;
  final String bankAddress;
  final String accountName;
  final String accountNumber;
  final String iban;
  final String swiftCode;
  final String currency;

  const BankDetails({
    required this.bankName,
    required this.bankAddress,
    required this.accountName,
    required this.accountNumber,
    required this.iban,
    required this.swiftCode,
    required this.currency,
  });

  static const _bn = 'CIB (Commercial International Bank)';
  static const _sw = 'CIBEEGCX127';
  static const _ad = '16 Khaled Ibn Al Walid, Sheraton Al Matar, Cairo, Egypt';
  static const _an = 'Fruity Farms for Export & Import';

  static const List<BankDetails> all = [
    BankDetails(
      bankName: _bn,
      bankAddress: _ad,
      accountName: _an,
      accountNumber: '100040067412',
      iban: 'EG740010012700000100040067412',
      swiftCode: _sw,
      currency: 'EUR',
    ),
    BankDetails(
      bankName: _bn,
      bankAddress: _ad,
      accountName: _an,
      accountNumber: '100040061848',
      iban: 'EG490010012700000100040061848',
      swiftCode: _sw,
      currency: 'GBP',
    ),
    BankDetails(
      bankName: _bn,
      bankAddress: _ad,
      accountName: _an,
      accountNumber: '100039996027',
      iban: 'EG790010012700000100039996027',
      swiftCode: _sw,
      currency: 'USD',
    ),
    BankDetails(
      bankName: _bn,
      bankAddress: _ad,
      accountName: _an,
      accountNumber: '100039996019',
      iban: 'EG740010012700000100039996019',
      swiftCode: _sw,
      currency: 'EGP',
    ),
  ];

  static BankDetails? forCurrency(String currency) {
    for (final b in all) {
      if (b.currency == currency) return b;
    }
    return null;
  }
}

/// Client-specific default values for auto-fill when a customer is selected.
class ClientDefaults {
  final String country;
  final String contact;
  final String destinationAddress;
  final String incoterm;
  final String seaPort;
  final String airPort;

  const ClientDefaults({
    required this.country,
    required this.contact,
    required this.destinationAddress,
    required this.incoterm,
    required this.seaPort,
    required this.airPort,
  });

  static const Map<String, ClientDefaults> all = {
    'DKI FRUIT MARKETING (PTY) LTD': ClientDefaults(
      country: 'South Africa',
      contact: 'Karoline Strydom',
      destinationAddress: '15 Beaulie Crescent, Bakkershoogte, Somerset West, 7130',
      incoterm: 'CFR',
      seaPort: 'Sengal',
      airPort: 'OR Tambo Airport',
    ),
    'DKI FRUIT MARKETING': ClientDefaults(
      country: 'South Africa',
      contact: 'Karoline Strydom',
      destinationAddress: '15 Beaulie Crescent, Bakkershoogte, Somerset West, 7130',
      incoterm: 'CFR',
      seaPort: 'Sengal',
      airPort: 'OR Tambo Airport',
    ),
    'BRUNO S.R.L.': ClientDefaults(
      country: 'Italy',
      contact: 'Tiffany Gerardo',
      destinationAddress: 'Via Lino Lovo, 62-37050 Vallese di Oppeano (VR)',
      incoterm: 'CFR',
      seaPort: 'Genoa Port',
      airPort: 'Frankfurt Airport / Germany',
    ),
  };

  static ClientDefaults? forName(String customerName) {
    if (customerName.isEmpty) return null;
    final upper = customerName.toUpperCase().trim();
    for (final entry in all.entries) {
      if (upper.contains(entry.key.toUpperCase())) return entry.value;
    }
    return null;
  }
}
