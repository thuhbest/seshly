# Developer Setup Guide

This guide helps you set up the Seshly project with all necessary secrets and configurations.

## Prerequisites

- Flutter 3.x+
- Node.js 18+
- Firebase CLI
- FlutterFire CLI
- Android SDK (for Android development)
- Xcode (for iOS development)

## Quick Setup

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/seshly.git
cd seshly
```

### 2. Install Dependencies

**Flutter:**
```bash
flutter pub get
```

**Backend (sesh-ai-gateway):**
```bash
cd sesh-ai-gateway
npm install
cd ..
```

**Cloud Functions:**
```bash
cd functions
npm install
cd ..
```

### 3. Configure Firebase

Generate Firebase configuration for your platform:

```bash
# Ensure FlutterFire CLI is installed
dart pub global activate flutterfire_cli

# Configure Firebase (interactive)
flutterfire configure
```

When prompted:
- Select your Firebase project
- Select all platforms (web, android, ios, macos, windows, linux)

This generates `lib/firebase_options.dart` (automatically gitignored).

### 4. Configure Backend (sesh-ai-gateway)

```bash
cd sesh-ai-gateway

# Create local config from template
cp gcloud.env.example gcloud.env

# Edit gcloud.env and add your actual values:
# - OPENAI_API_KEY: Get from https://platform.openai.com/api-keys
# - DOC_AI_PROCESSOR_ID: Get from Google Cloud Console
nano gcloud.env  # or use your preferred editor

cd ..
```

### 5. Configure Cloud Functions

```bash
cd functions

# Create local config from template (if using local development)
cp .env.example .env.local

# Update with actual LiveKit and Peach credentials
# Note: These are typically managed via Google Cloud Secret Manager in production
nano .env.local

cd ..
```

### 6. Configure Android Signing

```bash
cd android

# Copy the template
cp key.properties.example key.properties

# Generate a keystore (if you don't have one):
keytool -genkey -v -keystore seshly-release-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias seshly

# Edit key.properties with your actual paths and passwords
nano key.properties

cd ..
```

Example `key.properties`:
```properties
storeFile=../path/to/seshly-release-key.jks
storePassword=your_actual_keystore_password
keyAlias=seshly
keyPassword=your_actual_key_password
```

### 7. Verify Setup

```bash
# Check Flutter setup
flutter doctor

# Check backend can load config
cd sesh-ai-gateway
npm run build
cd ..

# Verify no secrets are exposed
git ls-files | xargs grep -l "REMOVEDpro\|AIzaSy" || echo "✓ No exposed secrets found"
```

## Development

### Flutter App

```bash
# Run development app
flutter run

# Run on specific device
flutter run -d chrome
flutter run -d emulator-5554

# Build for Android
flutter build apk --split-per-abi

# Build for iOS
flutter build ios
```

### Backend (sesh-ai-gateway)

```bash
cd sesh-ai-gateway

# Development
npm run dev

# Production build
npm run build
npm start

# Run tests
npm test
```

### Cloud Functions

```bash
cd functions

# Run locally
npm run serve

# Deploy to Firebase
firebase deploy --only functions
```

## Troubleshooting

### Firebase Configuration Issues

**Problem:** `firebase_options.dart` not found
```bash
# Regenerate it
flutterfire configure
```

**Problem:** Firebase project ID mismatch
```bash
# Check your .firebaserc file
cat .firebaserc

# Reconfigure if needed
firebase logout
firebase login
flutterfire configure
```

### Backend API Key Issues

**Problem:** `OPENAI_API_KEY not found`
```bash
# Verify gcloud.env exists and has the key
cat sesh-ai-gateway/gcloud.env | grep OPENAI_API_KEY

# If not present, add it
echo "OPENAI_API_KEY=your_key_here" >> sesh-ai-gateway/gcloud.env
```

### Android Signing Issues

**Problem:** `key.properties` not found
```bash
cd android
cp key.properties.example key.properties
# Edit with actual values
```

## Security Reminders

⚠️ **IMPORTANT:**
- Never commit `.env`, `gcloud.env`, `firebase_options.dart`, or `key.properties`
- These files are gitignored for your protection
- Don't share your API keys or signing credentials
- If you accidentally expose secrets, see [SECURITY.md](SECURITY.md)

## Getting Help

- Check [SECURITY.md](SECURITY.md) for security setup
- Read [README.md](README.md) for project overview
- Check platform-specific guides:
  - [Flutter Docs](https://flutter.dev/docs)
  - [Firebase Docs](https://firebase.google.com/docs)
  - [Node.js/Express Docs](https://expressjs.com/)

---

**Last Updated:** 2026-04-30
