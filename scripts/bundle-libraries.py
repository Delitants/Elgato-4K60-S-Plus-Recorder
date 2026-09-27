#!/usr/bin/env python3
"""Copy non-system Mach-O dependencies into an app and rewrite local load paths."""
import pathlib,subprocess,sys,shutil,re,json
app=pathlib.Path(sys.argv[1]).resolve();prefix=pathlib.Path(sys.argv[2]).resolve();arch=sys.argv[3]
frameworks=app/'Contents/Frameworks';frameworks.mkdir(exist_ok=True)
queue=list((app/'Contents/MacOS').iterdir());seen=set();manifest=[];copied=set()
while queue:
 binary=queue.pop(0)
 if binary in seen:continue
 seen.add(binary)
 text=subprocess.check_output(['otool','-L',str(binary)],text=True)
 deps=list(dict.fromkeys(re.findall(r'^\t(.+?) \(',text,re.M)))
 for dep in deps:
  if dep.startswith('/System/') or dep.startswith('/usr/lib/'):continue
  name=pathlib.Path(dep).name;dest=frameworks/name
  if binary==dest:continue
  source=pathlib.Path(dep) if dep.startswith('/') else prefix/'lib'/name
  if not dest.exists() or (dep.startswith('/') and name not in copied and source.resolve()!=dest.resolve()):
   if not source.exists():raise SystemExit(f'Missing dependency {dep} for {binary}')
   copied.add(name)
   shutil.copy2(source.resolve(),dest);dest.chmod(0o755)
   arches=subprocess.check_output(['lipo','-archs',str(dest)],text=True).split()
   if arch not in arches:raise SystemExit(f'{name} has no {arch} slice')
   if len(arches)>1:
    temp=dest.with_suffix('.thin');subprocess.run(['lipo',str(dest),'-thin',arch,'-output',str(temp)],check=True);temp.replace(dest)
   subprocess.run(['install_name_tool','-id','@rpath/'+name,str(dest)],check=True)
   manifest.append({'file':name,'source':source.name,'architecture':arch})
  new='@rpath/'+name
  if dep!=new:subprocess.run(['install_name_tool','-change',dep,new,str(binary)],check=True)
  queue.append(dest)
for binary in (app/'Contents/MacOS').iterdir():
 text=subprocess.check_output(['otool','-l',str(binary)],text=True)
 deps=subprocess.check_output(['otool','-L',str(binary)],text=True)
 if '@rpath/' in deps and '@executable_path/../Frameworks' not in text:subprocess.run(['install_name_tool','-add_rpath','@executable_path/../Frameworks',str(binary)],check=True)
manifest=[{'file':p.name,'architectures':subprocess.check_output(['lipo','-archs',str(p)],text=True).split()} for p in sorted(frameworks.glob('*.dylib'))]
(app/'Contents/Resources/DEPENDENCY-MANIFEST.json').write_text(json.dumps(manifest,indent=2))
