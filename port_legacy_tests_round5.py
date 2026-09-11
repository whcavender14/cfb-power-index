from pathlib import Path
import shutil, subprocess, csv
root=Path.cwd();dest=root/'outputs/round5/legacy_test_workspace';dest.mkdir(exist_ok=True)
for p in root.glob('*.R'):
    target=dest/p.name
    if not target.exists(): target.symlink_to(p)
for name in ['cfb_data_v2','cfb_data_v3','tests']:
    target=dest/name
    if not target.exists(): target.symlink_to(root/name,target_is_directory=True)
for rnd in ['round3','round4']:
    target=dest/'outputs'/rnd;target.mkdir(parents=True,exist_ok=True)
    for p in (root/'outputs'/rnd).iterdir():
        if p.is_file(): shutil.copy2(p,target/p.name)
        elif p.name=='cache' and not (target/p.name).exists(): (target/p.name).symlink_to(p,target_is_directory=True)
rows=[]
for name in ['test_v4.R','test_v4_integration.R','test_v5.R','test_v5_integration.R']:
    print('Running',name,flush=True)
    with (root/'outputs/round5'/('ported_'+name+'.log')).open('w') as log:
        r=subprocess.run(['Rscript',str(root/'tests'/name)],cwd=dest,stdout=log,stderr=subprocess.STDOUT)
    rows.append({'suite':name,'pass':r.returncode==0,'exit_code':r.returncode})
with (root/'outputs/round5/ported_legacy_suites.csv').open('w') as f:
    w=csv.DictWriter(f,fieldnames=['suite','pass','exit_code']);w.writeheader();w.writerows(rows)
if not all(r['pass'] for r in rows): raise SystemExit(1)
