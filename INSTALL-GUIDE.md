# DevWatch - Installation Guide

## Quick Install

### Option 1: Using the DMG File (Easiest)

1. Download `DevWatch-1.0.dmg` from the releases
2. Double-click to mount the DMG
3. Drag **DevWatch.app** to the **Applications** folder
4. Eject the DMG
5. Open **Applications** and double-click **DevWatch** to run

### Option 2: Build from Source

#### Requirements

- macOS 11.0 or later
- Xcode 13.0 or later
- Apple Silicon or Intel Mac

#### Build Steps

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/dev-watch.git
   cd dev-watch
   ```

2. **Build the application:**
   ```bash
   chmod +x build-app.sh
   ./build-app.sh
   ```
   
   The compiled app will be at: `build/Build/Products/Release/DevWatch.app`

3. **Create a DMG (optional):**
   ```bash
   chmod +x create-dmg.sh
   ./create-dmg.sh
   ```
   
   This creates `DevWatch-1.0.dmg` for distribution.

4. **Install manually:**
   ```bash
   cp -r build/Build/Products/Release/DevWatch.app /Applications/
   ```

## Running DevWatch

### First Run

1. Open **Applications** and double-click **DevWatch**
2. macOS may show a security warning - click **Open**
3. Approve permissions if prompted
4. DevWatch will start and appear in your menu bar

### Menu Bar

- **Click icon** - Show/hide the port list popover
- **Command + Click** - Open settings
- **Right-click** - Quit menu

### Permissions

DevWatch requires permission to run `lsof` commands. On first run:

1. macOS may prompt for permission
2. Click **Allow** when prompted
3. Enter your password if required

## Features Once Running

- **View ports** - See all local listening services
- **Open in browser** - Click a service to open localhost
- **Show details** - See process name, PID, and protocol
- **Terminate** - Kill a process (safe kill or force quit)
- **Auto-refresh** - Updates every 3 seconds
- **Notifications** - Get alerts when services start/stop

## Troubleshooting

### "DevWatch cannot be opened" Error

This usually means macOS is blocking the app. To fix:

1. Open **System Preferences** → **Security & Privacy**
2. Click **General** tab
3. Find the message about DevWatch
4. Click **Open Anyway**
5. Try running DevWatch again

### Missing Terminal Permissions

DevWatch uses `lsof` which requires permissions:

```bash
# Grant permissions (may need admin password)
chmod +s /usr/sbin/lsof
```

### App Won't Start

Try building from source:

```bash
./build-app.sh
```

If issues persist, check:
- Xcode is installed: `xcode-select --install`
- Deployment target compatibility

## Building for Distribution

To create a signed and notarized DMG for release:

1. Ensure you have a valid Developer ID
2. Code sign the app:
   ```bash
   codesign -s "Developer ID Application" \
     --options runtime \
     -v build/Build/Products/Release/DevWatch.app
   ```

3. Create the DMG:
   ```bash
   ./create-dmg.sh
   ```

4. Notarize (requires Apple Developer account):
   ```bash
   xcrun altool --notarize-app -f DevWatch-1.0.dmg \
     -t osx \
     -u your-email@example.com \
     -p your-app-password
   ```

## System Requirements

- **OS:** macOS 11.0 or later
- **Architecture:** Apple Silicon (M1+) or Intel
- **RAM:** 50 MB minimum
- **Disk Space:** ~100 MB

## Uninstall

Simply delete the app:

```bash
rm -rf /Applications/DevWatch.app
```

Or drag it to Trash from Applications folder.

## Support

For issues or questions:
- Check the [GitHub Issues](https://github.com/yourusername/dev-watch/issues)
- Review the [README](README.md)
- Check the [FAQ](#faq-section)

## Advanced Configuration

### Launch on Startup

To make DevWatch launch automatically when you log in:

1. Open **System Preferences** → **General** → **Login Items**
2. Click the **+** button
3. Select **DevWatch** from Applications
4. Close preferences

### Command Line Usage

You can also run DevWatch from the terminal:

```bash
/Applications/DevWatch.app/Contents/MacOS/DevWatch
```

## Development

See [Development Guide](INSTALL-GUIDE.md) for instructions on:
- Setting up the development environment
- Building and testing locally
- Creating releases

---

**Version:** 1.0  
**Last Updated:** April 2026  
**macOS Compatibility:** 11.0+
