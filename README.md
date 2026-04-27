# PixelText - Image to Text Encoder

A powerful, cross-platform Flutter application that converts images to text using advanced OCR (Optical Character Recognition) technology. Extract text from images effortlessly and export results in multiple formats.

![Flutter](https://img.shields.io/badge/Flutter-3.6.0+-02569B?logo=flutter)
![License](https://img.shields.io/badge/License-MIT-green)
![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Linux%20%7C%20macOS%20%7C%20Windows-blue)

---

## 📋 Table of Contents

- [Features](#features)
- [Supported Platforms](#supported-platforms)
- [Requirements](#requirements)
- [Installation](#installation)
- [Project Structure](#project-structure)
- [Dependencies](#dependencies)
- [Usage](#usage)
- [Configuration](#configuration)
- [Building](#building)
- [Contributing](#contributing)
- [License](#license)
- [Support](#support)

---

## ✨ Features

- **Image to Text Conversion**: Advanced OCR engine to extract text from images
- **Multiple File Format Support**: 
  - JPEG, PNG, GIF, BMP, WebP
  - Batch processing capabilities
- **Export Formats**:
  - Plain Text (.txt)
  - PDF documents (.pdf)
  - Copy to clipboard
- **User-Friendly Interface**: Intuitive Material Design UI
- **Cross-Platform**: Works on mobile, desktop, and web
- **Real-time Processing**: Instant text extraction feedback
- **Image Preview**: View selected images before processing
- **Editable Text**: Edit extracted text directly in the app

---

## 🖥️ Supported Platforms

| Platform | Status | Min Version |
|----------|--------|------------|
| **Android** | ✅ Supported | Android 5.0 (API 21) |
| **iOS** | ✅ Supported | iOS 11.0+ |
| **Web** | ✅ Supported | Modern browsers |
| **Windows** | ✅ Supported | Windows 10+ |
| **macOS** | ✅ Supported | macOS 10.14+ |
| **Linux** | ✅ Supported | GTK 3.0+ |

---

## 📦 Requirements

### Minimum Requirements

- **Flutter SDK**: 3.6.0 or higher
- **Dart SDK**: Compatible with Flutter 3.6.0+
- **Git**: For version control

### Platform-Specific Requirements

#### Android
- Android Studio 4.1+
- Android SDK 21 (API level 21) or higher
- Gradle 7.0+

#### iOS
- Xcode 12.0+
- Swift 5.3+
- CocoaPods

#### Windows
- Visual Studio 2019 or later
- Windows 10 SDK or later

#### macOS
- Xcode 12.0+
- Swift 5.3+
- CocoaPods

#### Linux
- CMake 3.10+
- GTK development libraries

#### Web
- Modern web browser (Chrome, Firefox, Safari, Edge)
- No additional setup required

---

## 🚀 Installation

### 1. Clone the Repository

```bash
git clone https://github.com/Rafi12234/PixelText---Image-Text-Encoder.git
cd PixelText---Image-Text-Encoder
```

### 2. Install Flutter Dependencies

```bash
flutter pub get
```

### 3. Configure Platform-Specific Setup

#### For Android
```bash
cd android
./gradlew clean build
cd ..
```

#### For iOS
```bash
cd ios
pod install
cd ..
```

#### For Windows
No additional steps required after `flutter pub get`

#### For macOS
```bash
cd macos
pod install
cd ..
```

### 4. Verify Installation

```bash
flutter doctor
```

Ensure all required components are installed (marked with ✓).

---

## 📂 Project Structure

```
PixelText---Image-Text-Encoder/
├── android/                 # Android-specific implementation
│   ├── app/                 # Android app module
│   ├── gradle/              # Gradle configuration
│   └── build.gradle         # Root build configuration
├── ios/                     # iOS-specific implementation
│   ├── Runner/              # iOS app implementation
│   └── Runner.xcodeproj/    # Xcode project file
├── lib/                     # Flutter source code
│   └── main.dart            # Application entry point
├── windows/                 # Windows-specific implementation
│   ├── runner/              # Windows app runner
│   └── CMakeLists.txt       # Build configuration
├── macos/                   # macOS-specific implementation
│   ├── Runner/              # macOS app implementation
│   └── CMakeLists.txt       # Build configuration
├── linux/                   # Linux-specific implementation
│   ├── runner/              # Linux app runner
│   └── CMakeLists.txt       # Build configuration
├── web/                     # Web-specific implementation
│   ├── index.html           # Web entry point
│   └── manifest.json        # PWA manifest
├── test/                    # Test files
│   └── widget_test.dart     # Widget tests
├── pubspec.yaml             # Flutter package configuration
├── pubspec.lock             # Locked dependency versions
├── analysis_options.yaml    # Dart analysis configuration
└── README.md                # This file
```

---

## 📚 Dependencies

### Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| **flutter** | 3.6.0+ | Flutter SDK |
| **file_picker** | ^8.1.2 | File selection dialog |
| **image** | ^4.5.4 | Image processing |
| **path_provider** | ^2.1.4 | Platform-specific file paths |
| **pdf** | ^3.11.1 | PDF generation |
| **cupertino_icons** | ^1.0.8 | iOS style icons |

### Development Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| **flutter_test** | SDK | Testing framework |
| **flutter_lints** | ^5.0.0 | Lint rules |

---

## 💻 Usage

### Running the Application

#### Development Mode
```bash
# Run on Android
flutter run -d android

# Run on iOS
flutter run -d ios

# Run on Web
flutter run -d chrome

# Run on Windows
flutter run -d windows

# Run on macOS
flutter run -d macos

# Run on Linux
flutter run -d linux
```

#### Release Mode
```bash
# Build Android APK
flutter build apk --release

# Build iOS IPA
flutter build ios --release

# Build Web
flutter build web --release

# Build Windows
flutter build windows --release

# Build macOS
flutter build macos --release

# Build Linux
flutter build linux --release
```

### Basic Usage Flow

1. **Launch the Application**
   ```bash
   flutter run
   ```

2. **Select an Image**
   - Tap the "Pick Image" button
   - Choose an image file from your device

3. **Process the Image**
   - The app automatically processes the image
   - View the extracted text in real-time

4. **Edit and Export**
   - Edit the extracted text if needed
   - Export as PDF or TXT
   - Copy to clipboard

---

## ⚙️ Configuration

### Flutter Configuration

Edit `pubspec.yaml` to customize:

```yaml
# Change app name
name: image_to_text

# Change version
version: 1.0.0+1

# Modify environment constraints
environment:
  sdk: ^3.6.0
```

### Dart Analysis Configuration

Modify `analysis_options.yaml` to adjust linting rules:

```yaml
# Enabled lint rules
linter:
  rules:
    - avoid_empty_else
    - avoid_print
    - avoid_relative_lib_imports
```

### Platform-Specific Configuration

#### Android (`android/app/build.gradle`)
```gradle
android {
    compileSdk 35
    
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 35
    }
}
```

#### iOS (`ios/Podfile`)
```ruby
platform :ios, '11.0'
```

---

## 🔨 Building

### Building for Different Platforms

#### Android
```bash
# Build APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

#### iOS
```bash
# Build iOS app
flutter build ios --release

# Build IPA
flutter build ipa --release
```

#### Web
```bash
# Build web app
flutter build web --release

# Output: build/web/
```

#### Windows
```bash
# Build Windows installer
flutter build windows --release

# Output: build\windows\runner\Release\
```

#### macOS
```bash
# Build macOS app
flutter build macos --release

# Output: build/macos/Build/Products/Release/
```

#### Linux
```bash
# Build Linux app
flutter build linux --release

# Output: build/linux/x64/release/bundle/
```

---

## 🧪 Testing

### Run Unit and Widget Tests

```bash
# Run all tests
flutter test

# Run specific test file
flutter test test/widget_test.dart

# Run tests with coverage
flutter test --coverage
```

### Generate Test Coverage Report

```bash
# Generate coverage
flutter test --coverage

# View coverage (requires lcov)
# On macOS/Linux:
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html
```

---

## 🐛 Troubleshooting

### Common Issues

#### Issue: "Flutter SDK not found"
**Solution:**
```bash
# Add Flutter to PATH
export PATH="$PATH:[FLUTTER_SDK_PATH]/bin"

# Verify installation
flutter doctor
```

#### Issue: "Pod install fails" (iOS)
**Solution:**
```bash
cd ios
rm -rf Pods
rm Podfile.lock
pod install
cd ..
```

#### Issue: "Gradle build fails" (Android)
**Solution:**
```bash
cd android
./gradlew clean build
cd ..
```

#### Issue: "Web build hangs"
**Solution:**
```bash
# Clear build cache
flutter clean
flutter pub get
flutter build web --release
```

---

## 📖 Additional Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Dart Documentation](https://dart.dev/guides)
- [Material Design Guidelines](https://material.io/design/)
- [Flutter Best Practices](https://flutter.dev/docs/testing/best-practices)

---

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. **Fork the Repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/PixelText---Image-Text-Encoder.git
   ```

2. **Create a Feature Branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Commit Your Changes**
   ```bash
   git commit -m "Add your descriptive commit message"
   ```

4. **Push to Your Fork**
   ```bash
   git push origin feature/your-feature-name
   ```

5. **Submit a Pull Request**
   - Provide a clear description of changes
   - Reference any related issues

### Code Style

- Follow Dart style guide: [Effective Dart](https://dart.dev/guides/language/effective-dart)
- Use `flutter analyze` to check code quality
- Format code: `dart format lib/`

---

## 📄 License

This project is licensed under the **MIT License** - see the LICENSE file for details.

```
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
...
```

---

## 📞 Support

### Getting Help

- **Issues**: [GitHub Issues](https://github.com/Rafi12234/PixelText---Image-Text-Encoder/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Rafi12234/PixelText---Image-Text-Encoder/discussions)
- **Documentation**: [Flutter Docs](https://docs.flutter.dev/)

### Report a Bug

1. Go to [Issues](https://github.com/Rafi12234/PixelText---Image-Text-Encoder/issues)
2. Click "New Issue"
3. Describe the bug with:
   - Device/platform information
   - Reproduction steps
   - Expected vs. actual behavior
   - Screenshots or logs

### Feature Requests

Feel free to open a new issue with the title prefix `[Feature Request]`

---

## 👨‍💻 Authors

**Rafi12234**
- GitHub: [@Rafi12234](https://github.com/Rafi12234)
- Project: [PixelText](https://github.com/Rafi12234/PixelText---Image-Text-Encoder)

---

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- All contributors and supporters
- The open-source community

---

## 📊 Project Statistics

- **Language**: Dart/Flutter
- **Lines of Code**: ~2,400+
- **Platforms Supported**: 6
- **Dependencies**: 5 core + 2 dev
- **Last Updated**: 2026

---

**Made with ❤️ by the PixelText Team**
