# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0-prototype] - 2026-03-13

### Added
- **Core Communication Engine**: Implemented a robust voice and video chat framework based on WebRTC with Unified Plan semantics.
- **Custom System Audio Capture (Windows)**: Developed a low-latency WASAPI Loopback capturer in C++ to enable high-fidelity system audio sharing during screen shares.
- **Neural Noise Suppression**: Integrated **RNNoise** (Recurrent Neural Network for noise suppression) for real-time background noise removal and voice isolation.
- **P2P Mesh Networking**: Implemented a secure, low-latency peer-to-peer networking layer using **WireGuard** tunnels, enabling direct encrypted communication between peers.
- **Screen Sharing**: Added support for high-frame-rate screen sharing with optional system audio loopback.
- **Signaling Layer**: Designed a Go-based WebSocket signaling server for peer discovery and SDP/ICE exchange.
- **Audio Processing Profiles**: Added support for multiple audio profiles including "Voice Isolation" (RNNoise), "Studio" (Flat), and "Custom" (Noise Gate).
- **Quality of Service (QoS)**: Implemented dynamic bitrate constraints and bandwidth management for both audio and video streams.
