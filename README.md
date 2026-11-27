# ZP Suite

A free, open-source toolkit for voiceover, dubbing, podcasts, e-learning and broadcast workflows in REAPER. It brings script reading, subtitle handling, project preparation, accessible controls and ZP audio tools into one REAPER setup.

**Prefer Italian?** See [README in Italian](README.it.md). The Suite itself is available in Italian and English.

## Choose your language

After installing or updating, open **33 Welcome** from REAPER's Action List. Under **Suite language**, choose **English** or **Italiano**. This preference is saved and is independent of REAPER's own language. The `?` help buttons open the guide in the selected Suite language.

## Install with ReaPack

1. In REAPER, choose **Extensions → ReaPack → Import repositories**.
2. Add this repository URL:

   `https://github.com/capitanpaolone/zp-suite/raw/master/index.xml`

3. Choose **Extensions → ReaPack → Browse packages**, search for **ZP**, and install **ZP Studio Suite** and any ZP effects you need.
4. Synchronize packages to receive updates.

The Suite works in a clean REAPER install. SWS, js_ReaScriptAPI and OSARA are optional; they add features where available.

## What is included

- **ZP Studio Suite** — teleprompters, SRT import/export and references, project tools, mixdown preparation, voice-minute reports, Voice Cleaner and accessible workflows.
- **ZP Voce** — voice chains, dialogue tools and voice/music processing.
- **ZP Master** — mastering and reference-tone tools.
- **ZP Misura** — loudness meters, oscilloscope, passive signal probes and ZP BrownSlope Prism, a passive brown-slope analyzer.

Version 2.6.6 adds automatic copying and Sync now in Render & Copy on Windows (requires js_ReaScriptAPI) and Linux (requires find and stat). Version 2.6.5 updates the Solo Recorder guide to explain how ZP Remote packages relate to Dubbertools. Version 2.6.4 added Render & Copy, a Dubbertools link in SOLO Web, and the ZP Remote REAPER tool for creating packages and importing deliveries. ZP Remote export requires Python 3 and ffmpeg.


Version 2.6.9 introduces **ZP Shared Bus v3.1**, the new **`39 ZP Telemetry Engine`**, the new **`ZP Spoken Finish Pro 1.0.0`** (shipped alongside classic `ZP Spoken Finish 3.10.2` with the `MAGIC` `VELVET · AIR SILK · 3D FOCUS` signature module), **`30 ZP SRT 2.0`** (unified 4-tab subtitle workstation with `Coalesce short cues`), two calibrated **Project Templates** (`-18 LUFS` VoiceOver and `-8 LUFS` Mix-Spot), **`ZP Master Pro 2.52`** (`TRANSP` transparent profile + `ENHANCE` + `2× PRECLIP` + `SPT -8 LUFS` preset and **CATENA** tab), **`ZP BUS Chain 1.3.7`** (Teletronix LA-2A Gray-calibrated `LA2 GRAY` + `PAD -6` + `2×` oversampling), **`ZP Magic Voice LAB 1.2.7`** (`20 kHz` linear transparency via residual-only 2× oversampling and 5 UAD-calibrated hardware cartridges), **`ZP Click & Attack Softener 1.4`** (STFT spectral `MICRO-CLICK` with `~940 Hz` local pocket coherence, continuous `Freq Skew` `Low ↔ Air`, and automatable `Micro %`), **`ZP Loudness Meter Multichannel 45.3`**, **`ZP BrownSlope Prism 1.2`** (cepstral comb-filter detection), **`ZP Audition Noise Monitor 1.1`** (Monitor FX), and unified product branding (`latocardioide.it · dubbertools.com`) across all Lua windows, JSFX plugins, and IT/EN guides.

ZP Studio Suite 2.6.7 distributes **ZP Magic Voice LAB 1.2.0-lab3**, the correct version, as a separate **ZP Voce** effect. **ZP Magic Voice 1.2.0** without LAB is an archived prototype and is excluded from the package. Install ZP Magic Voice LAB alongside ZP Studio Suite in ReaPack. [Operating guide](ZP%20Studio%20Suite/help/en/magic_voice_lab.html).

Version 2.6.8 includes: **Embed into Items** will copy only timeline markers you have selected; operational markers such as Harmonic Space Carver's `#HSC` cues will stay on the timeline. It also includes **ZP Magic Voice LAB 1.2.3** (backward-compatible DRC `FREQ` center + `OCT` octave width knobs, real continuous response curves in `DRC`, `DYN EQ` `±5 / ±12 dB` and `DYN BAL` `±6 / ±12 dB` monitors, flashing global DELTA with 30 s auto-off, extended spring-loaded per-stage `S·DELTA`, 4 s active-speech block suggestions, color-only `LIGHT / DARK` theme keeping all DRC controls visible), **ZP BrownSlope Prism 1.1** (`±1.5 / ±3 dB` tolerance corridor, warm/cool differential fill, optional `Live` trace, bipolar zone bars, slope spirit level, and Dark/Light theme toggle), **ZP Loudness Meter Multichannel 45.0** (vertical-first anti-drift UI with free `TARGET` + one-click `LOCK NOW`, green `±LU` band, 60s drift ribbon freezing on pause, floating peak-hold, 4 responsive views including `LUFS-I`/`TP` embedded TCP/MCP, and Dark/Light themes) and the **scrollable `STATO` log** in **ZP Render & Copy**.

ZP Studio Suite 2.6.7 adds ZP Consolidate, which copies referenced take sources and project-registered SRT/VTT files into Media without converting media. See the [changelog](CHANGELOG.md) for the complete list of changes.

## Separate packages

Starting with 2.6.9, these packages have graduated from BETA (2026-11-26); the requirements and limits stay as listed.

- **ZP Clean & Paint**: ReaPack installs the REAPER actions. The ZP Voice Model Lab engine, Python environment, presets and voice models remain external and must be installed and configured separately.
- **ZP Montaggio Parlato**: requires ZP Studio Suite and ZP Speech from 33 Welcome; the current version is tested on macOS. PDF import needs `pdftotext` (Poppler). Clipboard paste needs SWS.
- **ZP BrownSlope Dynamic Guard** and **ZP Click & Attack Softener**: separate effects to try on sessions and working copies. Cue Navigator is only needed for the `?` help button.

ZP Speech (the transcription engine behind Transcribe, 29) is not in the ReaPack package: install it from Welcome (33), which downloads it from GitHub. On macOS it uses MacWhisper or OpenAI Whisper; on Windows and Linux it uses local OpenAI Whisper and is still **experimental**.

## Guides and source

- [English Suite guide](ZP%20Studio%20Suite/help/en/index.html)
- [Separate packages guide](ZP%20Studio%20Suite/help/en/lab.html)
- [Guida italiana della Suite](ZP%20Studio%20Suite/help/index.html)
- [Website: Lato Cardioide — Tools](https://latocardioide.it/strumenti/)
- [ReaPack repository index](https://github.com/capitanpaolone/zp-suite/raw/master/index.xml)

The ReaPack package description and release notes are provided in both English and Italian. The GitHub README is English-first; Italian readers can choose the Italian README and set the Suite language in **33 Welcome**.

## License and Disclaimer of Warranty

Most components are licensed under **GPL-3.0-or-later**; some REAPER-derived meters are **LGPL-2.1-or-later**. See [LICENSE](LICENSE), [LICENSE-LGPL-2.1.txt](LICENSE-LGPL-2.1.txt) and [NOTICE.md](NOTICE.md).

**No Warranty ("AS IS"):** ZP Suite is free, open-source software provided **"as is" without warranty of any kind**, either expressed or implied, including implied warranties of merchantability or fitness for a particular purpose (pursuant to Sections 15–16 of the GNU GPLv3). You assume all risk regarding quality, performance, and suitability in production: always keep backups of important sessions and verify rendered deliverables. In no event shall the author be liable for any direct, indirect, incidental, or consequential damages, downtime, or data loss arising from the use or inability to use this software.
