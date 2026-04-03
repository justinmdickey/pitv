# PiTV

Play a TV show on loop on a **Casio TV-880B** portable television using a **Raspberry Pi Zero**.

The Pi outputs NTSC composite video directly to the Casio's RCA input. Videos autoplay on boot, loop forever, and recover from crashes automatically.

## Hardware

### What You Need

- Raspberry Pi Zero (or Zero 2 W)
- Casio TV-880B (or any TV with composite/RCA video input)
- Micro SD card (8GB+ recommended)
- Soldering iron (to attach composite video pads)
- RCA cable or wire
- 5V micro-USB power supply for the Pi

### Wiring

```
Pi Zero                          Casio TV-880B
────────                         ─────────────
PP24 (composite video) ──────── Video In (yellow RCA)
PP6  (ground)          ──────── Ground (RCA shield)
GPIO 18 (PWM audio)  ─┐
                       ├─ RC ── Audio In (or earphone jack)
GND                   ─┘
```

**Video**: Solder a wire to test pad **PP24** on the Pi Zero's underside. This is the composite video output. Connect it to the center pin of a yellow RCA plug. Solder ground from **PP6** to the RCA shield.

**Audio** (optional): The Pi Zero has no 3.5mm jack. For audio, connect **GPIO 18** through a simple RC low-pass filter (270-ohm resistor + 33nF capacitor to ground) to the Casio's audio input or earphone jack.

> **Tip**: Search "add RCA output to Pi Zero" for detailed soldering guides with photos.

## Software Setup

### Prerequisites

- Raspberry Pi OS Lite (Bookworm or Bullseye) flashed to SD card
- SSH access or keyboard/monitor connected to the Pi
- `ffmpeg` installed on your desktop/laptop (for transcoding)

### Install

```bash
# On the Pi:
git clone <your-repo-url> ~/pitv
cd ~/pitv
sudo ./scripts/setup.sh
```

This installs VLC, configures composite output, and enables the autostart service.

#### With SD card protection (recommended)

```bash
sudo ./scripts/setup.sh --readonly
```

Enables OverlayFS so the SD card is never written to during normal operation. Prevents corruption from power cycling.

### Prepare Videos

On your **desktop** (not the Pi — it's too slow to transcode):

```bash
# Single file
./scripts/transcode.sh simpsons_s01e01.mkv videos/s01e01.mp4

# Entire directory
./scripts/transcode.sh ~/simpsons_rips/ ./videos/
```

This converts videos to 320x240 H.264 Baseline at 500kbps — optimized for the Casio's tiny screen and the Pi's hardware decoder.

### Deploy Videos

Copy the transcoded `.mp4` files to the Pi:

```bash
scp videos/*.mp4 pi@raspberrypi.local:~/pitv/videos/
```

Then reboot:

```bash
ssh pi@raspberrypi.local "sudo reboot"
```

The show starts playing automatically.

## Configuration

Edit `config/pitv.conf` to customize:

| Setting | Default | Description |
|---------|---------|-------------|
| `VIDEO_DIR` | `/home/pi/pitv/videos` | Where to find video files |
| `SHUFFLE` | `false` | Randomize playback order |
| `RESTART_DELAY` | `3` | Seconds before restarting after crash |
| `VIDEO_EXTENSIONS` | `mp4 mkv avi m4v` | File types to play |

## Managing the Service

```bash
# Check status
sudo systemctl status pitv

# View logs
journalctl -u pitv -f

# Stop playback
sudo systemctl stop pitv

# Restart playback
sudo systemctl restart pitv
```

## Adding Videos with OverlayFS Enabled

If you used `--readonly` during setup, the filesystem is protected. To add new videos:

```bash
# Disable overlay
sudo raspi-config nonint disable_overlayfs
sudo raspi-config nonint disable_bootro
sudo reboot

# After reboot, copy new files
scp new_episode.mp4 pi@raspberrypi.local:~/pitv/videos/

# Re-enable overlay
ssh pi@raspberrypi.local
sudo raspi-config nonint enable_overlayfs
sudo raspi-config nonint enable_bootro
sudo reboot
```

## Troubleshooting

**No picture on the Casio**
- Check solder joints on PP24 and PP6
- Verify `enable_tvout=1` and `sdtv_mode=0` are in `/boot/firmware/config.txt`
- Make sure the Casio is set to AV input mode (not antenna)

**No audio**
- Verify audio routing: `amixer cset numid=3 1` (forces analog output)
- Check the RC filter wiring from GPIO 18
- Try connecting directly to the Casio's earphone jack

**Video stutters or freezes**
- Ensure videos are transcoded with `transcode.sh` (320x240 Baseline H.264)
- Raw HD files will overwhelm the Pi Zero's decoder
- Check `journalctl -u pitv` for VLC errors

**Service won't start**
- Check logs: `journalctl -u pitv -e`
- Verify videos exist: `ls ~/pitv/videos/*.mp4`
- Test manually: `~/pitv/scripts/pitv-player.sh`

## Project Structure

```
pitv/
├── README.md              # This file
├── config/
│   ├── config.txt         # Pi boot config additions
│   └── pitv.conf          # Player settings
├── scripts/
│   ├── pitv-player.sh     # Main playback loop
│   ├── transcode.sh       # FFmpeg transcoder (desktop)
│   └── setup.sh           # Pi install script
├── systemd/
│   └── pitv.service       # Autostart service
└── videos/                # Drop transcoded .mp4s here
```

## License

MIT
