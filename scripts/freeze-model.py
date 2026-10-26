#!/usr/bin/env python3
"""Freeze immutable model/tokenizer downloads and content hashes; weights stay in work/."""
import hashlib, json, pathlib, urllib.request
ROOT = pathlib.Path(__file__).resolve().parents[1]
MODEL_REV = '0f63a7800b00dd0226abd051b906c246e1907482'
TOKEN_REV = '06f233fe06e710322aca913c1bc4249a0d71fce1'
FOLDER = 'openai_whisper-large-v3-v20240930_626MB'
def get_json(url):
    with urllib.request.urlopen(url) as response: return json.load(response)
files = get_json(f'https://huggingface.co/api/models/argmaxinc/whisperkit-coreml/tree/{MODEL_REV}/{FOLDER}?recursive=true')
entries = [('argmaxinc/whisperkit-coreml', MODEL_REV, f['path'], 'model/' + f['path'].split('/', 1)[1]) for f in files if f['type'] == 'file']
entries += [('openai/whisper-large-v3', TOKEN_REV, name, 'tokenizer/' + name) for name in ['tokenizer.json', 'tokenizer_config.json', 'config.json', 'special_tokens_map.json', 'added_tokens.json']]
artifacts = []
for repo, revision, remote, relative in entries:
    url = f'https://huggingface.co/{repo}/resolve/{revision}/{remote}'
    target = ROOT / 'work/model-freeze' / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        partial = target.with_suffix(target.suffix + '.partial')
        print('Downloading', relative, flush=True)
        urllib.request.urlretrieve(url, partial)
        partial.replace(target)
    digest = hashlib.sha256()
    with target.open('rb') as stream:
        while chunk := stream.read(1024 * 1024): digest.update(chunk)
    artifacts.append(dict(relativePath=relative, immutableURL=url, byteCount=target.stat().st_size, sha256=digest.hexdigest()))
manifest = dict(modelIdentity=FOLDER, sdkVersion='1.1.1', modelRevision=MODEL_REV, tokenizerRevision=TOKEN_REV, artifacts=artifacts)
(ROOT / 'Sources/LectureCore/Resources/model-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Frozen {len(artifacts)} files, {sum(a["byteCount"] for a in artifacts):,} bytes')
