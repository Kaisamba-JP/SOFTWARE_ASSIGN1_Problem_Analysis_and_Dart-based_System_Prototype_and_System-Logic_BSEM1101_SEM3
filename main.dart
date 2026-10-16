import 'dart:convert';
import 'dart:io';

// ============================================================
//  MCH CONTINUITY SYSTEM (MCHC) - Dart console prototype
//  Roles: Health Worker, Patient, Receptionist
// ============================================================

// ---------- Settings ----------
// Change this to your institution's real access code.
const String institutionPin = 'MCHC2026';
const String dataFile = 'mchc_data.json';
const int maxAttempts = 3;

// ---------- Models ----------
enum Role { healthWorker, patient, receptionist }

// Antenatal = pregnant mother (no child yet). Postnatal = mother with a baby.
enum CareType { antenatal, postnatal }

String careLabel(CareType type) =>
    type == CareType.antenatal ? 'Antenatal' : 'Postnatal';

String roleLabel(Role role) {
  if (role == Role.healthWorker) return 'Health Worker';
  if (role == Role.receptionist) return 'Receptionist';
  return 'Patient';
}

class Vaccination {
  String name;
  bool completed;
  String? dateCompleted;

  Vaccination({
    required this.name,
    this.completed = false,
    this.dateCompleted,
  });

  String get status {
    if (!completed) return 'Due';
    return dateCompleted == null
        ? 'Completed'
        : 'Completed ($dateCompleted)';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'completed': completed,
        'dateCompleted': dateCompleted,
      };

  factory Vaccination.fromJson(Map<String, dynamic> json) => Vaccination(
        name: json['name'] as String,
        completed: json['completed'] as bool? ?? false,
        dateCompleted: json['dateCompleted'] as String?,
      );
}

class Patient {
  String id;
  CareType careType;
  String motherName;
  String childName;
  String phone;
  String address;
  // Empty until the first visit is recorded by a health worker.
  String lastVisit;
  List<String> history;
  List<Vaccination> vaccinations;

  Patient({
    required this.id,
    required this.careType,
    required this.motherName,
    required this.childName,
    required this.phone,
    required this.address,
    this.lastVisit = '',
    required this.history,
    required this.vaccinations,
  });

  bool get isAntenatal => careType == CareType.antenatal;

  // What to show on screen for the last visit.
  String get lastVisitLabel => lastVisit.isEmpty ? 'No visit yet' : lastVisit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'careType': careType.name,
        'motherName': motherName,
        'childName': childName,
        'phone': phone,
        'address': address,
        'lastVisit': lastVisit,
        'history': history,
        'vaccinations': vaccinations.map((v) => v.toJson()).toList(),
      };

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'] as String,
        // Older saved files have no careType: decide from the child's name.
        careType: json['careType'] == 'antenatal'
            ? CareType.antenatal
            : json['careType'] == 'postnatal'
                ? CareType.postnatal
                : ((json['childName'] as String? ?? '').trim().isEmpty
                    ? CareType.antenatal
                    : CareType.postnatal),
        motherName: json['motherName'] as String,
        childName: json['childName'] as String? ?? '',
        phone: json['phone'] as String,
        address: json['address'] as String? ?? '',
        lastVisit: json['lastVisit'] as String? ?? '',
        history: (json['history'] as List? ?? [])
            .map((e) => e.toString())
            .toList(),
        vaccinations: (json['vaccinations'] as List? ?? [])
            .map((e) => Vaccination.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Staff {
  String id;
  String name;
  Role role;

  Staff({required this.id, required this.name, required this.role});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'role': role.name,
      };

  factory Staff.fromJson(Map<String, dynamic> json) => Staff(
        id: json['id'] as String,
        name: json['name'] as String,
        role: json['role'] == 'receptionist'
            ? Role.receptionist
            : Role.healthWorker,
      );
}

// ---------- Data (kept in memory, saved to a file) ----------
List<Patient> patients = [];
List<Staff> staffMembers = [];
int patientCounter = 1;
int staffCounter = 1;

// Login protection (lasts until the program is closed)
final Map<String, int> failedAttempts = {};
final Set<String> lockedKeys = {};
bool staffSignUpLocked = false;

// ---------- Saving and loading ----------
void saveData() {
  final data = {
    'patientCounter': patientCounter,
    'staffCounter': staffCounter,
    'patients': patients.map((p) => p.toJson()).toList(),
    'staff': staffMembers.map((s) => s.toJson()).toList(),
  };

  try {
    File(dataFile).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  } catch (e) {
    print('\nWarning: could not save data ($e).');
  }
}

void loadData() {
  final file = File(dataFile);
  if (!file.existsSync()) return;

  try {
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    patientCounter = data['patientCounter'] as int? ?? 1;
    staffCounter = data['staffCounter'] as int? ?? 1;

    patients = (data['patients'] as List? ?? [])
        .map((e) => Patient.fromJson(e as Map<String, dynamic>))
        .toList();

    staffMembers = (data['staff'] as List? ?? [])
        .map((e) => Staff.fromJson(e as Map<String, dynamic>))
        .toList();
  } catch (e) {
    print('\nWarning: saved data could not be read. A backup copy was kept '
        'and the system will start empty.');
    try {
      file.copySync('$dataFile.bak');
    } catch (_) {}
    patients = [];
    staffMembers = [];
    patientCounter = 1;
    staffCounter = 1;
  }
}

// ---------- Input helpers ----------
void endProgram() {
  print('\nInput closed. Goodbye.');
  saveData();
  exit(0);
}

String ask(String label) {
  stdout.write(label);
  final line = stdin.readLineSync();
  if (line == null) endProgram();
  return line!.trim();
}

// Reads input without showing it on screen (used for the institution PIN).
String askHidden(String label) {
  stdout.write(label);
  var hidden = false;

  try {
    if (stdin.hasTerminal) {
      stdin.echoMode = false;
      hidden = true;
    }
  } catch (_) {}

  final line = stdin.readLineSync();

  if (hidden) {
    try {
      stdin.echoMode = true;
    } catch (_) {}
    stdout.writeln();
  }

  if (line == null) endProgram();
  return line!.trim();
}

String askRequired(String label) {
  while (true) {
    final value = ask(label);
    if (value.isNotEmpty) return value;
    print('This field cannot be empty.');
  }
}

String askName(String label) {
  final pattern = RegExp(r"^\p{L}[\p{L}\s.'\-]{1,59}$", unicode: true);
  while (true) {
    final value = ask(label);
    if (pattern.hasMatch(value)) return value;
    print('Please enter a valid name (letters only, at least 2 characters).');
  }
}

// Asks whether the patient is antenatal or postnatal.
// Returns null when allowBack is true and the person chooses to go back.
CareType? askCareType({bool allowBack = false}) {
  while (true) {
    print('\nIs the patient Antenatal or Postnatal?');
    print('1. Antenatal (pregnant, baby not yet born)');
    print('2. Postnatal (baby has been born)');
    if (allowBack) print('3. Go back');

    final choice = ask('\nChoose an option: ');
    if (choice == '1') return CareType.antenatal;
    if (choice == '2') return CareType.postnatal;
    if (allowBack && choice == '3') return null;
    print('\nInvalid option!');
  }
}

String askAddress(String label) {
  while (true) {
    final value = ask(label);
    if (value.length >= 3) return value;
    print('Please enter a valid address (at least 3 characters).');
  }
}

String normalizePhone(String input) => input.replaceAll(RegExp(r'[\s\-]'), '');

String askPhone(String label) {
  while (true) {
    final value = normalizePhone(ask(label));
    if (RegExp(r'^\+?\d{8,15}$').hasMatch(value)) return value;
    print('Please enter a valid phone number (8 to 15 digits).');
  }
}

bool isValidDate(String text) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(text);
  if (match == null) return false;

  final day = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final date = DateTime(year, month, day);

  return date.year == year &&
      date.month == month &&
      date.day == day &&
      year >= 1900 &&
      !date.isAfter(DateTime.now());
}

String today() {
  final now = DateTime.now();
  final day = now.day.toString().padLeft(2, '0');
  final month = now.month.toString().padLeft(2, '0');
  return '$day/$month/${now.year}';
}

String askDateOrToday(String label) {
  while (true) {
    final value = ask(label);
    if (value.isEmpty) return today();
    if (isValidDate(value)) return value;
    print('Please enter a valid date as DD/MM/YYYY, or press Enter for today.');
  }
}

void pause() {
  ask('\nPress Enter to continue...');
}

String normalizeText(String input) =>
    input.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

bool sameText(String a, String b) => normalizeText(a) == normalizeText(b);

// ---------- Login protection ----------
// Returns true when the account has just become locked.
bool registerFailure(String key) {
  final count = (failedAttempts[key] ?? 0) + 1;
  failedAttempts[key] = count;

  if (count >= maxAttempts) {
    lockedKeys.add(key);
    print('\nToo many failed attempts. This account is locked until the '
        'system is restarted.');
    return true;
  }

  print('Attempts left: ${maxAttempts - count}');
  return false;
}

void clearFailures(String key) => failedAttempts.remove(key);

// ---------- Lookups ----------
Patient? findPatientById(String id) {
  for (final patient in patients) {
    if (patient.id.toLowerCase() == id.toLowerCase()) return patient;
  }
  return null;
}

Staff? findStaffById(String id, Role role) {
  for (final staff in staffMembers) {
    if (staff.id.toLowerCase() == id.toLowerCase() && staff.role == role) {
      return staff;
    }
  }
  return null;
}

Patient? findDuplicatePatient(String motherName, String phone) {
  for (final patient in patients) {
    if (sameText(patient.motherName, motherName) && patient.phone == phone) {
      return patient;
    }
  }
  return null;
}

// ---------- Display helpers ----------
String fit(String text, int width) {
  if (text.length > width - 1) {
    return '${text.substring(0, width - 3)}..'.padRight(width);
  }
  return text.padRight(width);
}

void printPatientBasic(Patient patient) {
  print('\n===== PATIENT INFORMATION =====');
  print('Patient ID   : ${patient.id}');
  print('Care Type    : ${careLabel(patient.careType)}');
  print('Mother Name  : ${patient.motherName}');
  if (!patient.isAntenatal) {
    print('Child Name   : ${patient.childName}');
  }
  print('Phone Number : ${patient.phone}');
  print('Address      : ${patient.address}');
  print('Last Visit   : ${patient.lastVisitLabel}');
}

void printHistory(Patient patient) {
  print('\n===== PATIENT HISTORY =====');
  if (patient.history.isEmpty) {
    print('No history recorded yet.');
    return;
  }
  for (final item in patient.history) {
    print('- $item');
  }
}

void printVaccinations(Patient patient) {
  print('\n===== IMMUNIZATION STATUS =====');
  if (patient.isAntenatal) {
    print('Not applicable yet. Immunization starts after the baby is born '
        '(postnatal).');
    return;
  }
  if (patient.vaccinations.isEmpty) {
    print('No vaccinations recorded yet.');
    return;
  }
  for (final vaccine in patient.vaccinations) {
    print('- ${vaccine.name}: ${vaccine.status}');
  }
}

void printFullRecord(Patient patient) {
  printPatientBasic(patient);
  printHistory(patient);
  printVaccinations(patient);
}

void printPatientTable(List<Patient> list) {
  if (list.isEmpty) {
    print('\nNo patients registered yet.');
    return;
  }

  print('\n${fit('ID', 8)}${fit('Type', 12)}${fit('Mother', 22)}'
      '${fit('Child', 22)}${fit('Phone', 16)}Last Visit');
  print('-' * 92);

  for (final p in list) {
    print('${fit(p.id, 8)}${fit(careLabel(p.careType), 12)}'
        '${fit(p.motherName, 22)}'
        '${fit(p.isAntenatal ? '-' : p.childName, 22)}'
        '${fit(p.phone, 16)}${p.lastVisitLabel}');
  }
  print('\nTotal patients: ${list.length}');
}

void printIdCard(String title, String id) {
  print('\n+------------------------------------+');
  print('  $title');
  print('  $id');
  print('+------------------------------------+');
}

// ---------- Patient records ----------
List<Vaccination> defaultVaccinations() => [
      Vaccination(name: 'BCG'),
      Vaccination(name: 'Polio 1'),
      Vaccination(name: 'Polio 2'),
    ];

// A new patient has no last visit yet. It is filled in the first time a
// health worker adds a visit note.
Patient createPatient({
  required CareType careType,
  required String motherName,
  required String childName,
  required String phone,
  required String address,
}) {
  final id = 'MCH${patientCounter.toString().padLeft(3, '0')}';
  patientCounter++;

  final patient = Patient(
    id: id,
    careType: careType,
    motherName: motherName,
    childName: childName,
    phone: phone,
    address: address,
    history: [],
    // Vaccines are for the baby, so antenatal patients start with none.
    vaccinations: careType == CareType.postnatal ? defaultVaccinations() : [],
  );

  patients.add(patient);
  saveData();
  return patient;
}

// Used by receptionists, health workers (byStaff = true) and by patients
// registering themselves (byStaff = false).
// careType is already known for patients who chose it at the start;
// staff are asked here.
Patient? registerPatientFlow({required bool byStaff, CareType? careType}) {
  print('\n--- Register New Patient ---');

  final type = careType ?? askCareType(allowBack: true);
  if (type == null) return null;

  print('\nRegistering an ${careLabel(type)} patient.');

  final motherName = askName("Enter Mother's Name: ");
  // Only postnatal patients have a child to name.
  final childName =
      type == CareType.postnatal ? askName("Enter Child's Name: ") : '';
  final phone = askPhone('Enter Phone Number: ');
  final address = askAddress('Enter Address: ');

  final duplicate = findDuplicatePatient(motherName, phone);
  if (duplicate != null) {
    print('\nPatient Already Registered!');
    if (byStaff) {
      print('Patient ID: ${duplicate.id}');
      print('Mother Name: ${duplicate.motherName}');
      if (!duplicate.isAntenatal) {
        print('Child Name: ${duplicate.childName}');
      }
    } else {
      // Do not reveal the ID to someone who is not logged in.
      print('Please go back and choose Log in. If you forgot your ID, '
          'type FORGOT when asked for it.');
    }
    return null;
  }

  // Details are saved to the file right here, so they are available
  // the next time this patient logs in.
  final patient = createPatient(
    careType: type,
    motherName: motherName,
    childName: childName,
    phone: phone,
    address: address,
  );

  print('\nCongratulations! You have successfully registered.');
  printIdCard('PATIENT ID', patient.id);
  if (byStaff) {
    print('Give this ID to the patient and tell her not to forget it. '
        'She will use it to log in next time.');
  } else {
    print('Please do not forget this ID. You will use it to log in next '
        'time, and your saved details will be shown to you.');
  }
  return patient;
}

Patient? selectPatient() {
  final id = askRequired('\nEnter Patient ID: ');
  final patient = findPatientById(id);
  if (patient == null) {
    print('\nNo Such Patient Registered!');
  }
  return patient;
}

// full = true shows history and vaccinations too (health workers only).
void searchPatient({required bool full}) {
  final query = askRequired('\nEnter Patient ID or name to search: ');
  final lower = query.toLowerCase();

  final matches = patients
      .where((p) =>
          p.id.toLowerCase() == lower ||
          p.motherName.toLowerCase().contains(lower) ||
          p.childName.toLowerCase().contains(lower))
      .toList();

  if (matches.isEmpty) {
    print('\nNo Such Patient Registered!');
    return;
  }

  if (matches.length == 1) {
    full ? printFullRecord(matches.first) : printPatientBasic(matches.first);
    return;
  }

  print('\n${matches.length} patients found:');
  printPatientTable(matches);
  print('Search again with an exact Patient ID to see one record.');
}

// ---------- Sign up ----------
Staff? staffSignUp(Role role) {
  print('\n--- ${roleLabel(role)} Sign Up ---');

  if (staffSignUpLocked) {
    print('Staff sign-up is locked until the system is restarted.');
    return null;
  }

  var verified = false;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    final pin = askHidden('Enter the institution PIN: ');
    if (pin == institutionPin) {
      verified = true;
      break;
    }
    print('Wrong institution PIN. '
        'Attempts left: ${maxAttempts - attempt}');
  }

  if (!verified) {
    staffSignUpLocked = true;
    print('\nToo many wrong PINs. Staff sign-up is locked until the '
        'system is restarted.');
    return null;
  }

  final name = askName('Enter your full name: ');
  final prefix = role == Role.healthWorker ? 'HW' : 'RC';
  final id = '$prefix${staffCounter.toString().padLeft(3, '0')}';
  staffCounter++;

  final staff = Staff(id: id, name: name, role: role);
  staffMembers.add(staff);
  saveData();

  print('\nSign up successful!');
  printIdCard('YOUR STAFF ID', id);
  print('Please write this ID down. You need it to log in.');
  pause();
  return staff;
}

Patient? patientSignUp(CareType careType) {
  print('\n--- ${careLabel(careType)} Patient Sign Up ---');
  final patient = registerPatientFlow(byStaff: false, careType: careType);
  if (patient != null) pause();
  return patient;
}

// ---------- Log in ----------
// Result of checking a name + ID against the saved data.
enum LoginStatus { ok, notRegistered, wrongId, wrongName }

class Account {
  final String id;
  final String name;
  Account(this.id, this.name);
}

// All saved accounts for a role (read from the data loaded from the JSON file).
List<Account> accountsFor(Role role) {
  if (role == Role.patient) {
    return patients.map((p) => Account(p.id, p.motherName)).toList();
  }
  return staffMembers
      .where((s) => s.role == role)
      .map((s) => Account(s.id, s.name))
      .toList();
}

// Compares the typed name and ID with the saved accounts:
//  - ID exists and its name matches        -> ok
//  - ID exists but belongs to another name -> wrongName
//  - name exists but the ID does not       -> wrongId
//  - neither exists                        -> notRegistered
LoginStatus checkLogin(Role role, String name, String id) {
  final accounts = accountsFor(role);

  Account? idMatch;
  for (final a in accounts) {
    if (a.id.toLowerCase() == id.toLowerCase()) {
      idMatch = a;
      break;
    }
  }

  if (idMatch != null) {
    return sameText(idMatch.name, name)
        ? LoginStatus.ok
        : LoginStatus.wrongName;
  }

  final nameExists = accounts.any((a) => sameText(a.name, name));
  return nameExists ? LoginStatus.wrongId : LoginStatus.notRegistered;
}

bool nameIsRegistered(Role role, String name) =>
    accountsFor(role).any((a) => sameText(a.name, name));

void printLoginProblem(LoginStatus status, String name) {
  if (status == LoginStatus.notRegistered) {
    print('\n$name is not part of our system. Please register first.');
  } else if (status == LoginStatus.wrongId) {
    print('\n$name is in the system, but the ID is wrong. '
        'Please try again with the correct ID.');
  } else if (status == LoginStatus.wrongName) {
    print('\nThe name linked to this ID is wrong. '
        'Please try again with the correct name.');
  }
}

Staff? staffLogin(Role role) {
  print('\n--- ${roleLabel(role)} Log In ---');

  while (true) {
    final name = askRequired('Enter your name: ');
    final id = askRequired('Enter your Staff ID: ');

    final nameKey = '${role.name}:name:${normalizeText(name)}';
    final idKey = '${role.name}:id:${id.toLowerCase()}';

    if (lockedKeys.contains(nameKey) || lockedKeys.contains(idKey)) {
      print('\nThis account is locked until the system is restarted.');
      return null;
    }

    final status = checkLogin(role, name, id);

    if (status == LoginStatus.ok) {
      final staff = findStaffById(id, role)!;
      clearFailures(nameKey);
      clearFailures(idKey);
      print('\nWelcome, ${staff.name}!');
      return staff;
    }

    printLoginProblem(status, name);

    // Not registered: send the person back to the menu to sign up.
    if (status == LoginStatus.notRegistered) return null;

    final key = status == LoginStatus.wrongName ? idKey : nameKey;
    if (registerFailure(key)) return null;
  }
}

// A mother who forgot her ID can prove who she is with name, address, phone.
Patient? recoverPatient(String name) {
  print('\nNo problem. Please confirm your details.');
  final address = askRequired('Enter your Address: ');
  final phone = normalizePhone(askRequired('Enter your Phone Number: '));

  for (final patient in patients) {
    if (sameText(patient.motherName, name) &&
        sameText(patient.address, address) &&
        patient.phone == phone) {
      return patient;
    }
  }

  print('\nThose details do not match any patient.');
  return null;
}

// Tells the person which type their ID belongs to when they picked the other.
bool careTypeMatches(Patient patient, CareType chosen) {
  if (patient.careType == chosen) return true;
  print('\nThis ID is registered as a ${careLabel(patient.careType)} patient. '
      'Please go back and choose ${careLabel(patient.careType)}.');
  return false;
}

Patient? patientLogin(CareType careType) {
  print('\n--- ${careLabel(careType)} Patient Log In ---');

  while (true) {
    final name = askRequired("Enter your name (mother's name): ");
    final id =
        askRequired('Enter your Patient ID (or type FORGOT if you forgot it): ');

    final nameKey = 'patient:name:${normalizeText(name)}';
    final idKey = 'patient:id:${id.toLowerCase()}';

    if (lockedKeys.contains(nameKey) || lockedKeys.contains(idKey)) {
      print('\nThis account is locked until the system is restarted.');
      return null;
    }

    if (id.toUpperCase() == 'FORGOT') {
      if (!nameIsRegistered(Role.patient, name)) {
        printLoginProblem(LoginStatus.notRegistered, name);
        return null;
      }
      final patient = recoverPatient(name);
      if (patient != null) {
        if (!careTypeMatches(patient, careType)) return null;
        clearFailures(nameKey);
        print('\nWelcome, ${patient.motherName}!');
        print('Your Patient ID is ${patient.id}. Please keep it safe.');
        return patient;
      }
      if (registerFailure(nameKey)) return null;
      continue;
    }

    final status = checkLogin(Role.patient, name, id);

    if (status == LoginStatus.ok) {
      final patient = findPatientById(id)!;
      if (!careTypeMatches(patient, careType)) return null;
      clearFailures(nameKey);
      clearFailures(idKey);
      print('\nWelcome back, ${patient.motherName}!');
      return patient;
    }

    printLoginProblem(status, name);

    if (status == LoginStatus.notRegistered) return null;

    final key = status == LoginStatus.wrongName ? idKey : nameKey;
    if (registerFailure(key)) return null;
  }
}

// ---------- Menus ----------
void patientMenu(Patient patient) {
  // Show the saved details as soon as the patient is in, so she sees her
  // information right after logging in (or registering).
  printFullRecord(patient);

  while (true) {
    print('\n===== PATIENT MENU =====');
    print('Logged in as: ${patient.motherName} (${patient.id})');
    print('1. View my information');
    print('2. View my history');
    print('3. View my immunization status');
    print('4. Log out');

    final choice = ask('\nChoose an option: ');

    if (choice == '1') {
      printPatientBasic(patient);
    } else if (choice == '2') {
      printHistory(patient);
    } else if (choice == '3') {
      printVaccinations(patient);
    } else if (choice == '4') {
      print('\nYou have been logged out.');
      return;
    } else {
      print('\nInvalid option!');
    }
  }
}

void receptionistMenu(Staff staff) {
  while (true) {
    print('\n===== RECEPTIONIST MENU =====');
    print('Logged in as: ${staff.name} (${staff.id})');
    print('1. Register new patient');
    print('2. View all patients');
    print('3. Search patient');
    print('4. Log out');

    final choice = ask('\nChoose an option: ');

    if (choice == '1') {
      registerPatientFlow(byStaff: true);
    } else if (choice == '2') {
      printPatientTable(patients);
    } else if (choice == '3') {
      searchPatient(full: false);
    } else if (choice == '4') {
      print('\nYou have been logged out.');
      return;
    } else {
      print('\nInvalid option!');
    }
  }
}

void healthWorkerMenu(Staff staff) {
  while (true) {
    print('\n===== HEALTH WORKER MENU =====');
    print('Logged in as: ${staff.name} (${staff.id})');
    print('1. Register new patient');
    print('2. View all patients');
    print('3. Search patient');
    print('4. View patient history');
    print('5. View immunization status');
    print('6. Add visit note');
    print('7. Update immunization');
    print('8. Log out');

    final choice = ask('\nChoose an option: ');

    if (choice == '1') {
      registerPatientFlow(byStaff: true);
    } else if (choice == '2') {
      printPatientTable(patients);
    } else if (choice == '3') {
      searchPatient(full: true);
    } else if (choice == '4') {
      final patient = selectPatient();
      if (patient != null) printHistory(patient);
    } else if (choice == '5') {
      final patient = selectPatient();
      if (patient != null) printVaccinations(patient);
    } else if (choice == '6') {
      addVisitNote(staff);
    } else if (choice == '7') {
      updateImmunization();
    } else if (choice == '8') {
      print('\nYou have been logged out.');
      return;
    } else {
      print('\nInvalid option!');
    }
  }
}

// ---------- Health worker actions ----------
void addVisitNote(Staff staff) {
  final patient = selectPatient();
  if (patient == null) return;

  final note = askRequired('Enter visit note: ');
  final date = today();

  patient.history.add('$date - $note (by ${staff.name})');
  // This is where the last visit date gets recorded.
  patient.lastVisit = date;
  saveData();

  print('\nVisit note added for ${patient.motherName} (${patient.id}).');
}

void updateImmunization() {
  final patient = selectPatient();
  if (patient == null) return;

  if (patient.isAntenatal) {
    print('\n${patient.motherName} is an Antenatal patient. '
        'Immunization can only be updated after the baby is born.');
    return;
  }

  while (true) {
    printVaccinations(patient);
    print('\n1. Mark a vaccine as completed');
    print('2. Add a new vaccine');
    print('3. Back');

    final choice = ask('\nChoose an option: ');

    if (choice == '1') {
      markVaccineCompleted(patient);
    } else if (choice == '2') {
      addVaccine(patient);
    } else if (choice == '3') {
      return;
    } else {
      print('\nInvalid option!');
    }
  }
}

void markVaccineCompleted(Patient patient) {
  if (patient.vaccinations.isEmpty) {
    print('\nNo vaccines to update.');
    return;
  }

  print('');
  for (var i = 0; i < patient.vaccinations.length; i++) {
    final vaccine = patient.vaccinations[i];
    print('${i + 1}. ${vaccine.name} - ${vaccine.status}');
  }

  final input = ask('\nEnter the number of the vaccine: ');
  final number = int.tryParse(input);

  if (number == null || number < 1 || number > patient.vaccinations.length) {
    print('\nInvalid vaccine number!');
    return;
  }

  final vaccine = patient.vaccinations[number - 1];
  if (vaccine.completed) {
    print('\n${vaccine.name} is already marked as completed.');
    return;
  }

  vaccine.dateCompleted =
      askDateOrToday('Date given (DD/MM/YYYY, or press Enter for today): ');
  vaccine.completed = true;
  saveData();

  print('\n${vaccine.name} marked as completed.');
}

void addVaccine(Patient patient) {
  final name = askRequired('Enter the new vaccine name: ');

  for (final vaccine in patient.vaccinations) {
    if (sameText(vaccine.name, name)) {
      print('\nThat vaccine is already on the list.');
      return;
    }
  }

  patient.vaccinations.add(Vaccination(name: name));
  saveData();
  print('\n$name added as Due.');
}

// ---------- Welcome flow ----------
void roleEntry(Role role) {
  // As soon as Patient is selected, ask Antenatal or Postnatal.
  CareType? careType;
  if (role == Role.patient) {
    careType = askCareType(allowBack: true);
    if (careType == null) return;
  }

  while (true) {
    print(role == Role.patient
        ? '\n--- Patient (${careLabel(careType!)}) ---'
        : '\n--- ${roleLabel(role)} ---');
    print('Please enter:');
    print('1. To log in');
    print('2. To sign up');
    print('3. To go back');

    final choice = ask('\nChoose an option: ');

    if (choice == '1' || choice == '2') {
      final loggingIn = choice == '1';

      if (role == Role.patient) {
        final patient =
            loggingIn ? patientLogin(careType!) : patientSignUp(careType!);
        if (patient != null) {
          patientMenu(patient);
          return;
        }
      } else {
        final staff = loggingIn ? staffLogin(role) : staffSignUp(role);
        if (staff != null) {
          if (role == Role.healthWorker) {
            healthWorkerMenu(staff);
          } else {
            receptionistMenu(staff);
          }
          return;
        }
      }
    } else if (choice == '3') {
      return;
    } else {
      print('\nInvalid option!');
    }
  }
}

void exitSystem() {
  saveData();
  print('\nYou have exited the system. Enter 0 to turn it on again.');

  while (true) {
    final restart = ask('Enter 0: ');
    if (restart == '0') {
      print('\nSystem turned on again.');
      return;
    }
    print('Invalid input! Enter 0 to turn the system on again.');
  }
}

void main() {
  loadData();

  while (true) {
    print('\n=====================================');
    print('     Hello, welcome to the MCHC');
    print('=====================================');
    print('Please enter:');
    print('1. To use as a Health Worker');
    print('2. To use as a Patient');
    print('3. To use as a Receptionist');
    print('4. To exit');

    final choice = ask('\nChoose an option: ');

    if (choice == '1') {
      roleEntry(Role.healthWorker);
    } else if (choice == '2') {
      roleEntry(Role.patient);
    } else if (choice == '3') {
      roleEntry(Role.receptionist);
    } else if (choice == '4') {
      exitSystem();
    } else {
      print('\nInvalid option!');
    }
  }
}