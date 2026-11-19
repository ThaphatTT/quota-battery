# Promo video

A 60 s, 1080x1920, 30 fps video made with HyperFrames (`npx hyperframes@0.9.17`).

- `video/`: the HyperFrames project. `index.html` mounts one scene per file in `video/compositions/`.
- `audio/`: `synth.py` writes the music and sound effects from scratch (no samples); `build.sh` mixes them to
  `video/assets/audio/mix.wav` at about -14 LUFS (needs `ffmpeg`).
- App pictures in `video/assets/` are renders of the real views from the Mac snapshot tests (sample data only).

```sh
sh promo/audio/build.sh
cd promo/video
npx hyperframes@0.9.17 check
npx hyperframes@0.9.17 render -q delivery -o ../out/quota-battery-promo.mp4
```

`promo/out/` is ignored by git.
