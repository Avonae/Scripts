# TinyPNG compression script

Compresses PNG, JPEG, and WebP images in place with the [TinyPNG API](https://tinypng.com/developers).

## What it does

- Uploads each file to TinyPNG and downloads the compressed result.
- Overwrites the original only if the result is smaller.
- Caches results by content hash in `~/.cache/tinify`, so re-runs on the same files cost no API calls.
- Prints `before -> after path` in bytes for each file, and `FAIL path` to stderr on errors.
- Exits with code 1 if any file failed.

## How to use

Get an API key at https://tinypng.com/developers and export it:

```bash
export TINIFY_API_KEY="your-key"
```

Compress files:

```bash
~/Scripts/tinypng/tinify.sh image1.png image2.jpg
```

Compress all images in a directory tree:

```bash
find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
  -exec ~/Scripts/tinypng/tinify.sh {} +
```

Use a custom cache directory:

```bash
~/Scripts/tinypng/tinify.sh -c /path/to/cache image.png
```

The free plan allows 500 compressions per month.
