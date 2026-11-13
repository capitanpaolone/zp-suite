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


ZP Studio Suite 2.6.7 is in preparation and is not published. The 2.6.7 candidate adds ZP Consolidate, which copies referenced take sources and project-registered SRT/VTT files into Media without converting media. The candidate checkout uses updates from the local REAPER installation; see `docs/PRE_RELEASE_2.6.7.md` and `docs/PROVENIENZA_2.6.7.md`.

## Not included in this version

ZP Montaggio Parlato (prototype) and ZP BrownSlope Dynamic Guard are still in development and are not part of this ReaPack release.

ZP Speech (the transcription engine behind Transcribe, 29) is not in the ReaPack package: install it from Welcome (33), which downloads it from GitHub. On macOS it uses MacWhisper or OpenAI Whisper; on Windows and Linux it uses local OpenAI Whisper and is still **experimental**.

## Guides and source

- [English Suite guide](ZP%20Studio%20Suite/help/en/index.html)
- [Guida italiana della Suite](ZP%20Studio%20Suite/help/index.html)
- [Website: Lato Cardioide — Tools](https://latocardioide.it/strumenti/)
- [ReaPack repository index](https://github.com/capitanpaolone/zp-suite/raw/master/index.xml)

The ReaPack package description and release notes are provided in both English and Italian. The GitHub README is English-first; Italian readers can choose the Italian README and set the Suite language in **33 Welcome**.

## License

GPL-3.0-or-later for most components; some REAPER-derived meters are LGPL-2.1-or-later. See [LICENSE](LICENSE), [LICENSE-LGPL-2.1.txt](LICENSE-LGPL-2.1.txt) and [NOTICE.md](NOTICE.md).
