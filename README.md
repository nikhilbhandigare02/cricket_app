# APL League (Flutter + Firebase)

Roles
- **Admin**: adds owners (creates their login), teams, players; schedules matches (single or auto round-robin "each team vs each team"); enters scores / reschedules / deletes matches.
- **Owner**: read-only. Sees own team + players, upcoming matches, and completed results (Win / Loss / Draw).

Matches are split into **Upcoming** and **Completed** lists; saving a score moves a match to Completed.

## Firebase setup (one time)
1. Create a Firebase project; add an **Android app** with package `com.village.village_league`.
2. Download `google-services.json` into `android/app/`.
3. Enable **Authentication → Email/Password** and create **Cloud Firestore**.
4. Paste `firestore.rules` into Firestore → Rules and publish.
5. Create the first admin:
   - Authentication → Add user (email + password); copy its **UID**.
   - Firestore → collection `users` → document id = that UID → fields: `role` (string) = `admin`, `name` (string) = `Admin`.
6. Run:
   ```
   flutter pub get
   flutter run          # or: flutter build apk --release
   ```
   APK output: `build/app/outputs/flutter-apk/app-release.apk`.

## Data model
- `users/{uid}`: role (`admin`|`owner`), ownerId, name
- `owners/{id}`: name, email, phone, uid
- `teams/{id}`: name, ownerId, ownerName → `players/{id}`: name, role, jersey, phone
- `matches/{id}`: teamA/teamB id+name, dateTime, venue, completed, scoreA, scoreB, winnerId
