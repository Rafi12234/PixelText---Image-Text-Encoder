# PixelText Studio

PixelText Studio is a cross-platform Flutter application for turning binary image data into portable text and back again. It does not perform OCR. Instead, it serializes a selected image into a JSON payload that contains the file name, MIME type, and base64-encoded bytes, making the image easy to copy, paste, store, and transport through text-only channels such as chats, emails, notes, documentation, or source code comments.

When the encoded payload exceeds the app's character limit, PixelText Studio automatically opens an adaptive compression workflow. That workflow reduces image dimensions and JPEG quality until the text payload fits, while trying to keep the result as readable and faithful as possible. The app can also restore a pasted payload back into an image, copy encoded text to the clipboard, save the encoded payload as a PDF, and download the restored image as a file.

![Flutter](https://img.shields.io/badge/Flutter-3.6.0+-02569B?logo=flutter)
![License](https://img.shields.io/badge/License-MIT-green)
![Platforms](https://img.shields.io/badge/Platforms-Android%20%7C%20iOS%20%7C%20Web%20%7C%20Linux%20%7C%20macOS%20%7C%20Windows-blue)

## Project Summary

This project is built around a simple but useful idea: images are often hard to move through systems that only accept text, while base64-encoded JSON is easy to transmit almost anywhere. PixelText Studio takes that idea further by giving you a polished interface for:

- Encoding an image into a text payload with metadata.
- Copying that payload into the clipboard for immediate reuse.
- Saving the payload into a PDF document for archiving or sharing.
- Decoding pasted payloads back into their original image bytes.
- Downloading a restored image to disk.
- Automatically compressing images that are too large to fit the app's limit.

The app is designed as a standalone utility, but the data format is intentionally portable. The encoded structure is a JSON object with a version field, the original file name, the detected MIME type, and the base64 data string.

## What the App Does

### Encode an image into text

The main action in the app is selecting an image file from the file picker. Once selected, the image is loaded into memory and wrapped in a JSON payload. That payload becomes the text representation of the image and appears in the editor so it can be copied or saved.

### Compress large payloads automatically

The app uses a character cap of 5,000 characters for the encoded payload. If the original image is too large, PixelText Studio launches a compression routine that:

- Converts the image to JPEG.
- Tries multiple resize scales and quality values.
- Chooses the best readable candidate under the limit.
- Falls back to progressively smaller and lower-quality images if needed.

This keeps the encoded text manageable without blocking the workflow.

### Decode text back into an image

If you paste a previously generated payload into the editor, the app can restore the image bytes from that text. It supports plain JSON payloads and data-style base64 strings, so the text can come back from the app itself or from another storage medium.

### Export and share

After encoding, you can:

- Copy the payload to the clipboard.
- Save the payload as a PDF document.
- Save the restored image back to disk.
- Clear the workspace and start over with a fresh image.

## Key Features

- Image-to-text encoding using a structured JSON payload.
- Reverse decoding from text back to image bytes.
- Adaptive compression for oversized images.
- Clipboard copy for instant sharing.
- PDF export for archival and distribution.
- Image preview and editable encoded text area.
- Character count and status feedback in the UI.
- Responsive layout that works on desktop and mobile screen sizes.
- Cross-platform support across Android, iOS, Web, Linux, macOS, and Windows.

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| Android | Supported | Mobile build with native picker and file save flows |
| iOS | Supported | Mobile build with native picker and file save flows |
| Web | Supported | Browser build with in-browser UI and clipboard actions |
| Windows | Supported | Desktop build with folder selection dialogs |
| macOS | Supported | Desktop build with native file and folder selection |
| Linux | Supported | Desktop build with GTK-backed Flutter shell |

## Technology Stack

- Flutter and Dart for the application framework and UI.
- `file_picker` for selecting images and folders.
- `image` for decoding, resizing, orientation correction, and JPEG compression.
- `pdf` for generating PDF exports of the encoded text.
- `path_provider` for locating writable directories where needed.
- Flutter clipboard services for quick text transfer.

## Encoding Format

The app stores encoded images as JSON with a stable structure similar to:

```json
{
  "version": 1,
  "name": "photo.png",
  "mime": "image/png",
  "data": "base64-encoded-image-bytes"
}
```

This format keeps the payload self-describing so it can be restored later without guessing the original name or MIME type.

## User Flow

1. Launch the app.
2. Choose an image file.
3. Review the generated JSON text.
4. Copy the payload, save it to PDF, or paste it elsewhere.
5. If the payload is too large, accept the compression flow.
6. Paste encoded text back into the editor at any time to restore the image.
7. Download the restored image if you want a file copy.

## Project Structure

- `lib/main.dart` - Main app logic and UI
- `test/widget_test.dart` - Flutter widget test
- `android/` - Android platform project
- `ios/` - iOS platform project
- `linux/` - Linux platform project
- `macos/` - macOS platform project
- `windows/` - Windows platform project
- `web/` - Web entry point and manifest
- `pubspec.yaml` - Dependencies and app metadata
- `pubspec.lock` - Locked dependency versions
- `analysis_options.yaml` - Dart analysis rules
- `README.md` - Project documentation

## Requirements

- Flutter SDK 3.6.0 or later.
- Dart 3.6-compatible tooling.
- Git for cloning and version control.
- Platform tooling for the target device, such as Android Studio, Xcode, Visual Studio, or the Linux build toolchain.

## Installation

```bash
git clone https://github.com/Rafi12234/PixelText---Image-Text-Encoder.git
cd PixelText---Image-Text-Encoder
flutter pub get
flutter doctor
```

## Running the App

```bash
flutter run
```

To target a specific platform:

```bash
flutter run -d android
flutter run -d ios
flutter run -d chrome
flutter run -d windows
flutter run -d macos
flutter run -d linux
```

## Building Releases

```bash
flutter build apk --release
flutter build ios --release
flutter build web --release
flutter build windows --release
flutter build macos --release
flutter build linux --release
```

## Testing

```bash
flutter test
```

## Contributing

Contributions are welcome. If you extend the app, keep the documentation aligned with the actual workflow so the README stays accurate:

- Describe the encoded payload format if it changes.
- Update platform instructions if file handling changes.
- Document new export or restore behaviors.
- Keep feature descriptions tied to the real UI and code paths.

## License

This project is licensed under the MIT License.

## Author

Rafi12234
