"""Launch vendor CLI synchronously, using a private project with absolute paths."""
from pathlib import Path
import os,re,subprocess,sys,json,hashlib,datetime,shutil
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/td';OUT.mkdir(parents=True,exist_ok=True)
if len(sys.argv)<2 or sys.argv[1] not in ('syn','full'):
    raise SystemExit('Usage: build_td.py syn|full')
if sys.argv[1]=='full':
    evidence=json.loads((ROOT/'config/voice_pin_verification.json').read_text(encoding='utf-8'))
    adc=(ROOT/'lab_ex3_osd/user_source/constraints_source/pin.adc').read_text(encoding='utf-8-sig')
    assignments=re.findall(r'set_pin_assignment\s*\{\s*([^}]+?)\s*\}\s*\{([^}]+)\}',adc)
    voice=[body for port,body in assignments if port.strip()=='I_voice_next']
    uses=[port.strip() for port,body in assignments if re.search(r'\bLOCATION\s*=\s*V2\s*;',body)]
    if not (evidence.get('schematic_mapping_verified') is True and evidence.get('fpga_pin')=='V2'
            and len(voice)==1 and uses==['I_voice_next'] and 'LVCMOS33' in voice[0]
            and 'PULLDOWN' in voice[0]):
        raise SystemExit('Voice input pin does not match verified schematic/ADC; refusing full build.')
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
archive=OUT/'attempts'/stamp
prior=[p for p in OUT.iterdir() if p.is_file() and (p.suffix in ('.log','.area','.timing','.ts','.bit','.json') or p.name=='build_failure.txt')]
if prior:
    archive.mkdir(parents=True,exist_ok=True)
    for p in prior:shutil.copy2(p,archive/p.name)
def hashes():
    files=[p for p in (ROOT/'lab_ex3_osd/user_source').rglob('*') if p.is_file() and p.suffix.lower() in ('.v','.sv','.adc','.sdc','.xml','.ipc','.tcl','.hex','.vh','.vhd','.mif','.dat','.txt')]
    files += [ROOT/'lab_ex3_osd/td_project/camera_to_dsi_display.al',ROOT/'lab_ex3_osd/td_project/camera_to_dsi_display.sdc']
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
before=hashes()
bit=OUT/'video_tracking.bit'
if bit.exists():bit.unlink() # single verified workspace file, previous copy archived
source=ROOT/'lab_ex3_osd/td_project/camera_to_dsi_display.al'
project=source.read_text(encoding='utf-8-sig')
project=re.sub(r'(<File\s+Path=")([^"]+)(")',lambda m:m[1]+(source.parent/m[2]).resolve().as_posix()+m[3],project)
project=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*(")',lambda m:m[1]+OUT.as_posix()+m[2],project,count=1)
(OUT/'camera_to_dsi_display.prj').write_text(project,encoding='utf-8')
(ROOT/'build/temp').mkdir(parents=True,exist_ok=True)
shutil.copy2(ROOT/'lab_ex3_osd/user_source/hdl_source/logo_index.hex',OUT/'logo_index.hex')
td_run=os.environ.get('TD_RUN_EXE') or shutil.which('run.exe') or 'D:/arch/bin/run.exe'
if not Path(td_run).is_file():raise SystemExit('TD run.exe not found; set -TdRoot or TD_RUN_EXE')
env=dict(os.environ,TEMP=str(ROOT/'build/temp'),TMP=str(ROOT/'build/temp'),HX_VERIFY_STAGE=sys.argv[1] if len(sys.argv)>1 else 'full')
with (OUT/'console.log').open('w',encoding='utf-8') as log:
    result=subprocess.run([td_run,(ROOT/'scripts/build_td.tcl').as_posix()],cwd=OUT,env=env,stdout=log,stderr=subprocess.STDOUT)
text=(OUT/'console.log').read_text(encoding='utf-8',errors='replace')
print('\n'.join(text.splitlines()[-24:]))
marker='HX_SYNTHESIS_PASS' if env['HX_VERIFY_STAGE']=='syn' else 'HX_BUILD_PASS'
completed=result.returncode==0 and marker in text
if completed:(OUT/'build_failure.txt').unlink(missing_ok=True)
timing_file=OUT/'video_tracking_pr.timing'
timing={}
if completed and timing_file.exists() and env['HX_VERIFY_STAGE']=='full':
    timing_text=timing_file.read_text(encoding='utf-8',errors='replace')
    for name in ('SWNS','HWNS'):
        m=re.search(r'\b'+name+r':\s*(-?[\d.]+)ns',timing_text)
        timing[name]=float(m[1]) if m else None
timing_pass=bool(timing) and all(v is not None and v>=0 for v in timing.values())
unchanged=before==hashes()
manifest={'started_utc':stamp,'stage':env['HX_VERIFY_STAGE'],'process_exit_code':result.returncode,
 'build_completed':completed,'timing_ns':timing,'timing_passed':timing_pass,'sources_unchanged_during_build':unchanged,
 'download_ready':completed and timing_pass and unchanged and bit.exists(),'source_sha256':before}
if completed and bit.exists():manifest['bit_sha256']=hashlib.sha256(bit.read_bytes()).hexdigest();manifest['bit_size']=bit.stat().st_size
(OUT/'build_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
if not completed:sys.exit(result.returncode or 1)
if not unchanged:print('FAIL sources changed during TD build; rebuild required');sys.exit(2)
if env['HX_VERIFY_STAGE']=='full' and not timing_pass:print('FAIL final setup/hold timing:',timing);sys.exit(3)

