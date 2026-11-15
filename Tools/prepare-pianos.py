#!/usr/bin/env python3
"""Fetch pinned piano libraries without modifying their original sample data.

EXS conversion of Osiris is deliberately not used: it loses the SFZ controller
conditions which select its pedal/noise sample sets. Preparation preserves SFZ.
"""
from __future__ import annotations

import argparse
import hashlib
from html.parser import HTMLParser
import json
import math
import re
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import urllib.parse
import zipfile
import zlib

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "build/library-cache"
ASSETS = {
    "Osiris": {
        "url": "https://github.com/sfzinstruments/Osiris_Piano/releases/download/v0.925/Osiris_Piano_0925.zip",
        "filename": "Osiris_Piano_0925.zip",
        "sha256": "54ef210b671ea38c4e77291714b5376af28f35803f7c1338737d0f402de02768",
        "revision": "18c6afccb60cff458edbf7c394571783e074e1e9",
        "entry": "Programs/01-natural.sfz",
        "license": "CC0-1.0",
    },
    "Headroom": {
        "url": "https://codeload.github.com/sfzinstruments/BengtNilsson.HeadroomPiano/zip/2a7df3f7252227a3484202c1d61bc1bfe352a971",
        "filename": "Headroom.zip",
        "sha256": "13ca4be08891e630ef5df8a19969287070451a361260f4ce921af5fa37de8f22",
        "revision": "2a7df3f7252227a3484202c1d61bc1bfe352a971",
        "entry": "Headroom Piano (NoFX).sfz",
        "license": "CC-BY-4.0",
    },
    "Fuchs": {
        "url": "https://drive.google.com/uc?export=download&id=1NCaVdQQyK4YbbA9ztrkBQYN8jpvbcQDG",
        "filename": "FuchsUndMoehrV10.sf2",
        "sha256": "cf6fdb8ff22a61732364659b341539ad4806d96616fb718917238bcd37bebc7f",
        "revision": "V1.0",
        "entry": "Instrument.sf2",
        "license": "Public Domain",
    },
}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def curl(url: str, target: Path) -> None:
    subprocess.run(["curl", "--fail", "--location", "--retry", "2", "--connect-timeout", "20",
                    "--max-time", "1800", "--silent", "--show-error", "--output", str(target), url], check=True)


class DriveForm(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.action = ""
        self.values: dict[str, str] = {}

    def handle_starttag(self, tag: str, attributes: list[tuple[str, str | None]]) -> None:
        values = dict(attributes)
        if tag == "form":
            self.action = values.get("action") or ""
        if tag == "input" and values.get("name"):
            self.values[values["name"]] = values.get("value") or ""


def fetch(name: str) -> Path:
    data = ASSETS[name]
    path = CACHE / data["filename"]
    if path.is_file() and digest(path) == data["sha256"]:
        print(f"{name}: архив проверен")
        return path
    temporary = path.with_name(path.name + ".part")
    try:
        curl(data["url"], temporary)
        if name == "Fuchs" and temporary.stat().st_size < 1024 * 1024:
            form = DriveForm()
            form.feed(temporary.read_text(encoding="utf-8"))
            parsed = urllib.parse.urlparse(form.action)
            if parsed.scheme != "https" or parsed.hostname != "drive.usercontent.google.com":
                raise RuntimeError("Не получена ожидаемая страница загрузки Google Drive")
            confirmation = form.action + "?" + urllib.parse.urlencode(form.values)
            curl(confirmation, temporary)
        if digest(temporary) != data["sha256"]:
            raise RuntimeError(f"{name}: контрольная сумма не совпала; файл не установлен")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
    return path


def extract(name: str, archive: Path) -> Path:
    destination = CACHE / (name.lower() + "-source")
    marker = destination / ".pianoroom-source.json"
    expected = {"sha256": ASSETS[name]["sha256"], "revision": ASSETS[name]["revision"]}
    if marker.is_file() and json.loads(marker.read_text()) == expected:
        # Do not reuse altered mappings or samples from a previous local experiment.
        with zipfile.ZipFile(archive) as original:
            for item in original.infolist():
                if item.is_dir():
                    continue
                cached = (destination / item.filename).resolve()
                if not cached.is_relative_to(destination.resolve()) or not cached.is_file() or cached.stat().st_size != item.file_size:
                    raise RuntimeError(f"{name}: изменены распакованные исходники; удалите {destination} для восстановления")
                crc = 0
                with cached.open('rb') as stream:
                    for block in iter(lambda: stream.read(8 * 1024 * 1024), b''):
                        crc = zlib.crc32(block, crc)
                if crc != item.CRC:
                    raise RuntimeError(f"{name}: изменён исходный файл {cached}")
        return next(path for path in destination.iterdir() if path.is_dir() and path.name != "__MACOSX")
    with tempfile.TemporaryDirectory(prefix=name.lower() + "-", dir=CACHE) as directory:
        stage = Path(directory)
        with zipfile.ZipFile(archive) as source:
            entries = source.infolist()
            if len(entries) > 30000 or sum(item.file_size for item in entries) > 8 * 1024**3:
                raise RuntimeError(f"{name}: неожиданный размер архива")
            for item in entries:
                target = (stage / item.filename).resolve()
                if not target.is_relative_to(stage.resolve()) or stat.S_ISLNK(item.external_attr >> 16):
                    raise RuntimeError(f"{name}: небезопасный путь в архиве")
            source.extractall(stage)
        directories = [path for path in stage.iterdir() if path.is_dir() and path.name != "__MACOSX"]
        if len(directories) != 1 or not (directories[0] / ASSETS[name]["entry"]).is_file():
            raise RuntimeError(f"{name}: неожиданная структура библиотеки")
        # Only replace this task's extraction directory after fully validating the archive.
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(stage, destination)
    marker.write_text(json.dumps(expected, indent=2) + "\n")
    return next(path for path in destination.iterdir() if path.is_dir() and path.name != "__MACOSX")


def install_fuchs(source: Path) -> None:
    destination = ROOT / "Resources/Instruments/Fuchs"
    destination.mkdir(parents=True, exist_ok=True)
    target = destination / "Instrument.sf2"
    if not target.is_file() or digest(target) != ASSETS["Fuchs"]["sha256"]:
        temporary = destination / "Instrument.sf2.part"
        shutil.copyfile(source, temporary)
        temporary.replace(target)
    (destination / "LICENSE.txt").write_text(
        "Fuchs & Möhr Felt Piano — Tom Guder\n\n"
        "The author released the soundfont and stereo WAV samples as Public Domain:\n"
        "https://www.polyphone.io/en/forum/your-creations/850-acoustic-felt-piano-upright-fuchs-mohr\n\n"
        "Original: FuchsUndMoehrV10.sf2, unchanged.\n"
        f"SHA-256: {ASSETS['Fuchs']['sha256']}\n", encoding="utf-8")
    (destination / "manifest.json").write_text(
        json.dumps({**ASSETS["Fuchs"], "size_bytes": source.stat().st_size,
                    "bank": 0, "program": 0}, ensure_ascii=False, indent=2) + "\n")



DIRECTIVE = re.compile(r'#define\s+(\$\w+)\s+("[^"]*"|\S+)|#include\s+"([^"]+)"')
MACRO = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*')


def expand_sfz(path: Path, entry: Path, root: Path, macros: dict[str, str], depth: int = 0) -> str:
    if depth > 20 or not path.resolve().is_relative_to(root.resolve()):
        raise RuntimeError("Небезопасный или зацикленный SFZ include")
    text = re.sub(r'/\*.*?\*/', '', path.read_text(encoding='utf-8-sig'), flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    def substitute(part: str) -> str:
        def replace(match: re.Match) -> str:
            if match[0] not in macros:
                raise RuntimeError("Неопределённый SFZ macro: " + match[0])
            return macros[match[0]]
        return MACRO.sub(replace, part)
    output = []
    position = 0
    for match in DIRECTIVE.finditer(text):
        output.append(substitute(text[position:match.start()]))
        if match[1]:
            macros[match[1]] = substitute(match[2].strip('"'))
        else:
            relative = Path(substitute(match[3]))
            target = entry.parent / relative
            if not target.is_file():
                target = path.parent / relative
            output.append(expand_sfz(target, entry, root, macros, depth + 1))
        position = match.end()
    output.append(substitute(text[position:]))
    return ''.join(output)


def sfz_sections(text: str):
    headers = list(re.finditer(r'<([a-zA-Z_]+)>', text))
    for index, header in enumerate(headers):
        part = text[header.end():headers[index + 1].start() if index + 1 < len(headers) else len(text)]
        found = list(re.finditer(r'(?:^|\s)([a-zA-Z_][A-Za-z0-9_]*)\s*=', part))
        values = {match[1]: part[match.end():found[j + 1].start() if j + 1 < len(found) else len(part)].strip()
                  for j, match in enumerate(found)}
        yield header[1], values


def install_sfz(name: str, source: Path) -> None:
    entry = source / ASSETS[name]['entry']
    text = expand_sfz(entry, entry, source, {})
    scopes = {'global': {}, 'master': {}, 'group': {}}
    regions = []
    curves = []
    controls = {}
    default_path = ''
    for header, values in sfz_sections(text):
        if header == 'control':
            controls.update(values)
            default_path = values.get('default_path', default_path)
        elif header == 'curve':
            curves.append(values)
        elif header in scopes:
            scopes[header] = values
            if header == 'global':
                scopes['master'] = {}
            if header in ('global', 'master'):
                scopes['group'] = {}
        elif header == 'region':
            regions.append({**scopes['global'], **scopes['master'], **scopes['group'], **values})
        else:
            raise RuntimeError('Неподдержанный SFZ header: ' + header)
    samples = set()
    normalized = []
    allowed = {'sample', 'lokey', 'hikey', 'pitch_keycenter', 'lovel', 'hivel', 'group',
               'note_polyphony', 'ampeg_attack', 'ampeg_release', 'ampeg_dynamic',
               'ampeg_release_shape', 'sustain_cc', 'ampeg_releasecc64', 'ampeg_release_curvecc64',
               'amp_velcurve_63', 'loop_mode', 'off_time', 'amp_veltrack', 'volume', 'pan',
               'ampeg_release_oncc67', 'ampeg_release_curvecc67',
               'locc64', 'hicc64', 'locc67', 'hicc67', 'locc70', 'hicc70'}
    for region in regions:
        if name == 'Osiris':
            # Horus chorus is disabled by the author's factory CC93=0.
            if 'locc93' in region:
                continue
            for key in list(region):
                if key in {'offset_cc73', 'offset_curvecc73', 'tune_cc94'} or re.fullmatch(r'(?:amplitude_cc|locc)10[012]', key):
                    del region[key]
        else:
            mic = 1.0 if region['group'] == '1' else .5
            master = (100 / 127) ** 2  # SFZ predefined curve 4.
            region['volume'] = format(float(region.pop('group_volume')) + 20 * math.log10(mic * master), '.9g')
            region['pan'] = '0'
            region['amp_veltrack'] = '100'
            region['ampeg_release'] = '.8'
            for key in list(region):
                if key in {'group_label', 'region_label', 'amp_veltrack_oncc73', 'ampeg_release_oncc72',
                           'amplitude_oncc7', 'amplitude_curvecc7'} or re.fullmatch(r'(?:amplitude_oncc|locc)(?:74|77)', key) or key.startswith('pan_'):
                    del region[key]
        unknown = set(region) - allowed
        if unknown:
            raise RuntimeError(f'{name}: неподдержанные аудиоопкоды {sorted(unknown)}')
        original = (entry.parent / default_path / region['sample'].replace('\\', '/')).resolve()
        if not original.is_relative_to(source.resolve()) or not original.is_file():
            raise RuntimeError(f'{name}: небезопасный или отсутствующий sample {original}')
        relative = original.relative_to(source.resolve())
        region['sample'] = relative.as_posix()
        samples.add(relative)
        normalized.append(region)
    if len(normalized) != (1896 if name == 'Osiris' else 300):
        raise RuntimeError(f'{name}: неожиданное число зон {len(normalized)}')
    destination = ROOT / 'Resources/Instruments' / name
    destination.mkdir(parents=True, exist_ok=True)
    for relative in sorted(samples):
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        original = source / relative
        if not target.is_file() or target.stat().st_size != original.stat().st_size or digest(target) != digest(original):
            temporary = target.with_name(target.name + '.part')
            shutil.copyfile(original, temporary)
            temporary.replace(target)
    lines = ['// Prepared by Tools/prepare-pianos.py; sample bytes are unchanged.', '<control> set_cc64=0 set_cc67=0 set_cc70=0']
    for curve in curves:
        if name == 'Osiris' and curve['curve_index'] != '11':
            continue
        lines.append('<curve> ' + ' '.join(f'{key}={value}' for key, value in curve.items()))
    for region in normalized:
        # Put sample last: unquoted SFZ sample names may contain spaces.
        lines.append('<region> ' + ' '.join(f'{key}={value}' for key, value in region.items() if key != 'sample') + ' sample=' + region['sample'])
    prepared = '\n'.join(lines) + '\n'
    temporary = destination / 'Instrument.sfz.part'
    temporary.write_text(prepared, encoding='utf-8')
    temporary.replace(destination / 'Instrument.sfz')
    license_path = source / ('license' if name == 'Osiris' else 'LICENSE')
    shutil.copyfile(license_path, destination / 'LICENSE.txt')
    if name == 'Headroom':
        shutil.copyfile(source / 'README.md', destination / 'SOURCE-README.md')
    notes = ('Original sample bytes retained. Includes and macros expanded; region inheritance flattened.\n'
             'No reverb is added here; Piano Room supplies its own reverb.\n')
    if name == 'Osiris':
        notes += ('Osiris Piano. Source: sfzinstruments/Osiris_Piano. CC0-1.0.\n'
                  'Factory mic CC100/101/102=127 retained as unity gain for all three mics.\n'
                  'Factory CC73=127 resolves inverse curve2 sample offset to zero. CC94=0 resolves tuning to zero.\n'
                  'Factory CC93=0 disables Horus extra chorus voices; those zones are omitted.\n'
                  'CC64 pedal recordings, CC67 soft recordings, CC70 noisy recordings remain selectable.\n'
                  'Release=zoneRelease+15*curve11(CC64); dynamic release and shape -6 retained.\n'
                  'Curve11: 0:0,32:0,42:.1,64:.3,72:.4,73:1,127:1; linear interpolation.\n'
                  'sustain_cc=90 is intentional: pedal CC64 shapes the envelope rather than holding notes indefinitely.\n')
    else:
        notes += ('Headroom Piano by Bengt Nilsson. CC-BY-4.0; attribution and original license retained.\n'
                  'Factory Close gain=1, Decca gain=.5, master gain=(100/127)^2 baked into volume dB.\n'
                  'Factory pans centered; velocity tracking=100%; base release=.4*2=.8 seconds.\n'
                  'High-key release=.8+10*curve7(CC67); curve7: 0:1,1:0,127:0.\n'
                  'Fixed factory GUI controls removed; five velocity layers and both microphones retained.\n'
                  'SFZ curve definitions verified against sfztools/sfizz src/sfizz/Curve.cpp.\n')
    (destination / 'TRANSFORMATIONS.txt').write_text(notes, encoding='utf-8')
    manifest = {**ASSETS[name], 'regions': len(normalized), 'samples': len(samples),
                'sample_bytes': sum((destination / path).stat().st_size for path in samples),
                'prepared_sha256': digest(destination / 'Instrument.sfz'),
                'opcodes': sorted(set().union(*(set(region) for region in normalized)))}
    (destination / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(f'{name}: подготовлено {len(normalized)} зон, {len(samples)} сэмплов')


def main() -> None:
    parser = argparse.ArgumentParser(description="Проверить и подготовить исходники трёх пианино")
    parser.add_argument("--sources-only", action="store_true", help="Только загрузить проверенные исходники")
    arguments = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    for name in ASSETS:
        archive = fetch(name)
        if name == "Fuchs":
            if not arguments.sources_only:
                install_fuchs(archive)
        else:
            source = extract(name, archive)
            if not arguments.sources_only:
                install_sfz(name, source)
    (CACHE / "sources-manifest.json").write_text(json.dumps(ASSETS, ensure_ascii=False, indent=2) + "\n")
    if not arguments.sources_only:
        print("Три библиотеки подготовлены; исходные архивы проверены по SHA-256.")


if __name__ == "__main__":
    main()
