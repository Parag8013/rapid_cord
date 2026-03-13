# rapid_cord
# RapidCord

A high-performance, low-latency voice, video, and screen sharing application built for efficiency and security. RapidCord leverages a decentralized P2P architecture and professional-grade audio processing to deliver a premium communication experience.

## 🚀 Key Features

- **High-Fidelity Communication**: Real-time voice and video chat with adaptive bitrate control.
- **Advanced Screen Sharing**: Low-latency display capture with support for high frame rates.
- **System Audio Loopback**: Share your high-quality system audio alongside your screen (Windows).
- **Neural Noise Suppression**: Real-time background noise removal using RNNoise.
- **Secure P2P Mesh**: Encrypted decentralized networking powered by WireGuard.
- **Professional Audio Profiles**: Switch between Voice Isolation, Studio, and Custom profiles.

## 🛠 Technical Architecture

### Peer-to-Peer Networking (WireGuard)
Unlike traditional client-server models, RapidCord establishes a secure mesh network using **WireGuard**. Each user is assigned a deterministic virtual IP (10.0.x.x), and traffic is routed directly between peers using Curve25519 encryption, ensuring low latency and high privacy.

### Custom Audio Engine (WASAPI & RNNoise)
The application features a custom C++ audio pipeline integrated into the WebRTC stack:
- **WASAPI Loopback**: Utilizes the Windows Audio Session API to capture process-specific or system-wide audio directly from the output buffer.
- **RNNoise Integration**: Employs a Recurrent Neural Network (RNN) to differentiate between human speech and background noise, providing superior voice isolation.

### WebRTC Implementation
We use a customized WebRTC implementation with **Unified Plan** semantics:
- **Hot-swapping**: Seamlessly switch camera or microphone sources without dropping calls.
- **Speaking Detection**: Real-time amplitude analysis for active speaker identification.
- **Bandwidth Management**: Granular control over encoding parameters for both local and remote streams.

## 📁 Project Structure

- `rapid_cord_flutter/`: The cross-platform frontend built with Flutter.
- `flutter-webrtc/`: Customized WebRTC plugin with native C++ audio extensions.
- `server/`: High-performance Go-based signaling hub for peer discovery.
- `rnnoise/`: The neural noise suppression engine.
- `models/`: Pre-trained weights for noise reduction and other ML features.

## 🛠 Getting Started

1. **Signaling Server**: Navigate to `/server` and run `go run main.go`.
2. **Client**: Open `/rapid_cord_flutter` and run `flutter run`.

Make sure to point and change the server ip for the client to connect to the signaling server.

---
*RapidCord is a prototype voice and video chat application.*

