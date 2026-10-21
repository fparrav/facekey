## Install

Facekey {{VERSION}} is signed with a Developer ID certificate but **not notarized**, so macOS Gatekeeper asks for confirmation the first time you open it.

1. Open `Facekey.dmg` and drag **Facekey** to **Applications**.
2. Open it in one of two ways:
   - **Terminal:** run `xattr -dr com.apple.quarantine /Applications/Facekey.app`, then open Facekey.
   - **System Settings:** open Facekey and dismiss the warning, then go to **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway** and confirm with your password or Touch ID (macOS 15).

Requires macOS 15 or later.

**SHA-256** of `Facekey.dmg`: `{{SHA256}}`
