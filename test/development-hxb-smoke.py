#!/usr/bin/env python3
"""Development-host candidate execution and HXB consumption, not conformance."""
import concurrent.futures, datetime, hashlib, json, os, pathlib, shlex, shutil, subprocess, sys, time, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'test/generated/testing/breadth'
ARCHIVE=ROOT/'test/generated/testing/compiler.eval.hxb'
HOST=shutil.which(os.environ.get('HAXE_HOST','haxe'))
if HOST is None: raise SystemExit('HAXE_HOST executable not found')
OUT.mkdir(parents=True,exist_ok=True)
STD=ROOT/'haxe/std'
env=os.environ.copy()
env.pop('HAXE_REFERENCE',None)
env['HAXE_STD_PATH']=str(STD)
env['HAXE_IN_HAXE_STD_PATH']=str(STD)
cases=[]
for line in (ROOT/'test/upstream-hxb-smoke.sh').read_text().splitlines():
    if line.startswith('run_case '):
        _,name,cp,main=shlex.split(line)
        cases.append(dict(name=name,kind='direct',class_path=cp,main=main))
    elif line.startswith('run_hxml_case '):
        _,name,project,hxml,main=shlex.split(line)
        cases.append(dict(name=name,kind='hxml',class_path=project,hxml=hxml,main=main))
if sum(c['kind']=='direct' for c in cases)<112 or sum(c['kind']=='hxml' for c in cases)<9:
    raise SystemExit('Existing smoke case inventory is incomplete')

def invoke(cmd,cwd,log):
    start=time.monotonic()
    try:
        with log.open('wb') as stream:
            result=subprocess.run(cmd,cwd=cwd,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=60)
        return dict(command=cmd,cwd=str(cwd),returncode=result.returncode,timed_out=False,seconds=round(time.monotonic()-start,3),log=str(log.relative_to(ROOT)))
    except subprocess.TimeoutExpired:
        return dict(command=cmd,cwd=str(cwd),returncode=None,timed_out=True,seconds=round(time.monotonic()-start,3),log=str(log.relative_to(ROOT)))

def run(case):
    path=OUT/case['name'];path.mkdir(exist_ok=True)
    output=path/'candidate.hxb'
    if output.exists(): output.unlink()
    cwd=ROOT if case['kind']=='direct' else ROOT/case['class_path']
    args=['-cp',str(ROOT/case['class_path']),'--main',case['main']] if case['kind']=='direct' else [case['hxml']]
    cmd=[HOST,'--hxb-lib',str(ARCHIVE),'--run','haxe.Main','--']+args+['--hxb',str(output)]
    result=dict(case)
    result['candidate']=invoke(cmd,cwd,path/'candidate.log')
    result['archive']=dict(path=str(output.relative_to(ROOT)),exists=output.is_file())
    if result['candidate']['returncode']==0 and output.is_file():
        try:
            with zipfile.ZipFile(output) as z:
                members=z.namelist()
                root_member='cross/'+case['main'].replace('.','/')+'.hxb'
                result['archive'].update(bytes=output.stat().st_size,members=len(members),hxb_members=sum(n.endswith('.hxb') for n in members),zip_error=z.testzip(),root_member=root_member,root_present=root_member in members and z.getinfo(root_member).file_size>0)
        except Exception as exc:result['archive']['zip_error']=repr(exc)
        dump=path/'dump';dump.mkdir(exist_ok=True)
        cmd=[HOST,'--hxb-lib',str(output),'-cp',str(STD),'-cp',str(ROOT/case['class_path']),'--main',case['main'],'--no-output','-D','dump=record','-D','dump-path='+str(dump)]
        result['consumption']=invoke(cmd,ROOT,path/'consumption.log')
    else: result['consumption']=None
    result['passed']=result['candidate']['returncode']==0 and result['consumption'] is not None and result['consumption']['returncode']==0 and result['archive'].get('zip_error') is None and result['archive'].get('root_present',False)
    (path/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(('PASS ' if result['passed'] else 'FAIL ')+case['name'],flush=True)
    return result

# Rebuild the compiler archive so every run exercises the current checkout.
build=invoke([HOST,'-cp','src','-main','haxe.Main','--interp','--no-output','--hxb',str(ARCHIVE)],ROOT,OUT/'build.log')
if build['returncode']!=0:
    raise SystemExit('Compiler archive build failed; see '+build['log'])
start=time.monotonic()
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results=list(pool.map(run,cases))
summary={
 'mode':'development-host candidate execution plus host consumption; no reference/conformance comparison',
 'host':HOST,
 'host_version':subprocess.check_output([HOST,'--version'],text=True).strip(),
 'candidate_archive':str(ARCHIVE.relative_to(ROOT)),
 'candidate_archive_sha256':hashlib.sha256(ARCHIVE.read_bytes()).hexdigest(),
 'pinned_std':str(STD),
 'completed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
 'elapsed_seconds':round(time.monotonic()-start,3),
 'counts':{
  'total':len(results),'direct':sum(r['kind']=='direct' for r in results),'hxml':sum(r['kind']=='hxml' for r in results),
  'candidate_succeeded':sum(r['candidate']['returncode']==0 for r in results),
  'consumption_attempted':sum(r['consumption'] is not None for r in results),
  'consumption_succeeded':sum(r['consumption'] is not None and r['consumption']['returncode']==0 for r in results),
  'passed':sum(r['passed'] for r in results),'failed':sum(not r['passed'] for r in results)},
 'results':results}
(OUT/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
text=['Development-host HXB breadth check','',summary['mode'],'',json.dumps(summary['counts'],indent=2),'']
for r in results:
 if not r['passed']:text.append(f"FAIL {r['name']}: candidate={r['candidate']['returncode']}, consumption={None if r['consumption'] is None else r['consumption']['returncode']}")
(OUT/'summary.txt').write_text('\n'.join(text)+'\n')
print(json.dumps(summary['counts']),flush=True)

sys.exit(1 if summary["counts"]["failed"] else 0)
