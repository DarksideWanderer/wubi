#!/usr/bin/env python3
"""Convert the pinned MIT pinyin-data character dictionary into offline TSV.

Download pinyin.txt and LICENSE from SOURCE, then run:
  python3 tools/build_pinyin.py /path/to/pinyin.txt /path/to/LICENSE
"""
import hashlib
import json
from pathlib import Path
import re
import sys
import unicodedata

COMMIT = '9d05c9e29cb6a7e5c79f2f5279f5c1014246a19a'
SOURCE = f'https://github.com/mozillazg/pinyin-data/tree/{COMMIT}'
ROOT = Path(__file__).resolve().parents[1]


def normalize(reading):
    reading = unicodedata.normalize('NFD', reading.lower()).replace('u\u0308', 'v')
    return ''.join(c for c in reading if not unicodedata.combining(c))


def main():
    source, license_file = map(Path, sys.argv[1:])
    raw = source.read_bytes()
    records = {}
    for line in raw.decode('utf-8').splitlines():
        match = re.match(r'U\+([0-9A-F]+):\s*([^#]+)', line)
        if not match:
            continue
        char = chr(int(match[1], 16))
        readings = sorted({normalize(s.strip()) for s in match[2].split(',')})
        assert all(re.fullmatch('[a-z]+', s) for s in readings), (char, readings)
        records[char] = readings
    output = 'character\tpinyin\n' + ''.join(
        char + '\t' + ','.join(readings) + '\n' for char, readings in sorted(records.items()))
    (ROOT / 'data/pinyin.tsv').write_text(output, encoding='utf-8')
    (ROOT / 'data/PINYIN-LICENSE.txt').write_bytes(license_file.read_bytes())
    metadata = dict(source=SOURCE, commit=COMMIT, source_file='pinyin.txt',
                    source_sha256=hashlib.sha256(raw).hexdigest(),
                    characters=len(records), syllables=len({s for ss in records.values() for s in ss}),
                    normalization='Tone-insensitive, u-diaeresis mapped to v; all character readings retained.')
    (ROOT / 'data/PINYIN-SOURCE.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(metadata, ensure_ascii=False))


if __name__ == '__main__':
    main()
