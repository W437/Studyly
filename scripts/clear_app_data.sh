#!/bin/bash

# Script to completely clear all app data
# This removes old seed data from the Isar database

echo "🧹 Clearing Studyly app data..."
echo ""

# For iOS Simulator
echo "📱 Clearing iOS Simulator data..."
xcrun simctl --set testing erase all 2>/dev/null || echo "No simulators to clear"

# For Android Emulator
echo "🤖 Clearing Android data..."
adb uninstall com.example.studyly 2>/dev/null || echo "App not installed on Android"

echo ""
echo "✅ App data cleared!"
echo ""
echo "Next steps:"
echo "1. Run 'flutter clean'"
echo "2. Run 'flutter pub get'"
echo "3. Run the app fresh - all seed data will be gone!"
