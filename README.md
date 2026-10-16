# MCH Continuity System (MCHC)

## About the project

MCHC is a Dart console program for maternal and child health. It solves a real health problem: when a mother moves between visits, clinics or health workers, her records are often lost or incomplete. MCHC keeps one continuous record for each mother and her baby, so care can continue from where it stopped. It belongs to the Health domain, as a Maternal and Child Health Continuity System.

A mother registers as either **Antenatal** (pregnant, baby not yet born) or **Postnatal** (baby has been born) and receives an automatically generated Patient ID (for example `MCH001`). Health workers then record visit notes and immunizations against that ID. When the mother logs in again, her saved details, history and immunization status are shown to her automatically.

## Features

- Register a new patient with mother's name, child's name (postnatal only), phone number and address
- Patient ID (`MCH001`...) and staff IDs (`HW001` for health workers, `RC001` for receptionists) generated automatically
- Three roles: Health Worker, Receptionist and Patient, each with its own menu
- Antenatal and postnatal care types, with immunization starting only after the baby is born
- Visit notes with date and the name of the health worker who wrote them
- Immunization tracking (BCG, Polio 1 and Polio 2 added by default), with completion dates and the option to add new vaccines
- "Last visit" shows "No visit yet" for new patients and is filled in automatically at the first recorded visit
- Search patients by ID or name
- Staff sign-up protected by a hidden institution PIN
- Account lock after 3 failed login attempts
- Forgotten ID recovery using name, address and phone number
- Input checks and clear messages, such as "Please enter a valid phone number (8 to 15 digits)."
- Duplicate patients blocked: the same mother name and phone number cannot be registered twice
- All records saved automatically to a file and loaded again when the program starts

## How it meets Digital Public Goods (DPG) standards

**Open-source:** the full source code is public on GitHub, and anyone can read, run and improve it.

**Inclusive and accessible:** it uses simple text menus and plain-language prompts. It needs no internet, no installation beyond the Dart SDK, and no special hardware. Every menu has a back or log out option, and every wrong input gets a helpful message.

**Privacy-respecting:** data is stored only in a local file (`mchc_data.json`) and is never sent anywhere. Access depends on role: receptionists see basic details only, health workers see full records, and patients see only their own record after logging in with their name and ID. The institution PIN is hidden while typing, and the data file is excluded from GitHub through `.gitignore`.

**Modular and reusable:** the models (`Patient`, `Staff`, `Vaccination`) are separate classes that can be reused in another project, and the helper functions for input, validation and login are independent of each other.

## Programming concepts used

| Concept | Place being used |
|---|---|
| Classes, attributes and objects | `Patient`, `Staff` and `Vaccination` |
| Enums | `Role`, `CareType` and `LoginStatus` |
| Data structure: list | `patients`, `staffMembers`, `history` and `vaccinations` |
| Data structure: map and set | `failedAttempts` (map) and `lockedKeys` (set) for login protection |
| Getters | `isAntenatal`, `lastVisitLabel` and `Vaccination.status` |
| Factory constructors | `fromJson` in each model, to rebuild objects from the saved file |
| Serialization | `toJson` and `fromJson`, saving and loading with `dart:convert` |
| File handling | `saveData` and `loadData` using `dart:io` |
| Input validation | Regular expressions for names, phone numbers and dates |
| Separation of concerns | Separate functions for lookups, display, sign-up, login and menus |

## Project structure

```
ASSIGN/
├── mchc.dart          # The whole program (models, login, menus, storage)
├── mchc_data.json     # Saved records (created automatically, kept off GitHub)
├── .gitignore         # Keeps patient data off GitHub
└── README.md          # This file
```

## How to run

1. Install the [Dart SDK](https://dart.dev/get-dart) (version 2.19 or newer). No extra packages are needed.
2. Download `mchc.dart` into a folder.
3. Open a terminal in that folder and run: `dart run mchc.dart`

The default institution PIN is `MCHC2026`. Change it at the top of `mchc.dart` before real use.

## Example usage

Add your screenshots here, each under a short caption:

- Welcome screen and main menu
- Registering a new patient (success message and Patient ID)
- Logging in and seeing saved details
- Health worker adding a visit note
- Updating immunization
- Wrong input and locked account messages

