# PowerWarden — OEM Battery Optimization & Killer Defense Guide

Aggressive OEM power-saving daemons (Xiaomi MIUI/HyperOS, Samsung OneUI, OnePlus OxygenOS/ColorOS) often aggressively kill background foreground services and disable alarms.

Follow the instructions below per OEM to keep PowerWarden running silently without being killed:

---

### 1. Xiaomi / Poco / Redmi (MIUI & HyperOS)
1. **Battery Saver Exemption:**
   - Go to *Settings -> Apps -> Manage apps -> PowerWarden*.
   - Tap *Battery saver* -> Select **No restrictions**.
2. **Autostart Permission:**
   - In the same app info menu, toggle ON **Autostart**.
3. **App Lock (Recents):**
   - Open Recent Apps overview.
   - Long-press or swipe down on the PowerWarden card and tap the **Lock** icon.

---

### 2. Samsung (One UI)
1. **Battery Optimization:**
   - Go to *Settings -> Apps -> PowerWarden -> Battery*.
   - Select **Unrestricted** (prevents background app sleeping).
2. **Never Sleeping Apps:**
   - Go to *Settings -> Device care -> Battery -> Background usage limits*.
   - Tap *Never auto-sleeping apps* -> Add **PowerWarden**.

---

### 3. OnePlus / Oppo / Realme (OxygenOS & ColorOS)
1. **Background Activity:**
   - Go to *Settings -> Battery -> More settings -> App battery management*.
   - Select *PowerWarden* -> Enable **Allow background activity** & **Allow auto-launch**.
2. **Quick Freeze:**
   - Disable *Auto freeze* for PowerWarden.

---

### 4. Stock Android / Google Pixel
1. Go to *Settings -> Apps -> PowerWarden -> App battery usage*.
2. Select **Unrestricted**.
