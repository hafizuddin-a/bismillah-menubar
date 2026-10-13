# homebrew-tap

[Homebrew](https://brew.sh) tap for my Mac apps.

```bash
brew install --cask hafizuddin-a/tap/bismillah
```

| Cask | What it is |
|------|------------|
| [bismillah](https://github.com/hafizuddin-a/bismillah-menubar) | Writes out the bismillah on your screen like handwriting every time your Mac wakes. |

The apps are not notarized by Apple. Each cask clears macOS's quarantine flag after installing so they open
without the "can't verify the developer" warning; the cask file shows exactly what it runs. The apps update
themselves, so `brew upgrade` skips them unless you pass `--greedy`.

Remove with `brew uninstall --cask bismillah` (and `brew untap hafizuddin-a/tap` to forget the tap).
