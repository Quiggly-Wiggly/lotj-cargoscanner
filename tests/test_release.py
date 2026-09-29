"""Verify release contents, reproducibility, Lua syntax, and behavior."""
from pathlib import Path
import importlib.util, os, shutil, subprocess, tempfile, unittest, xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('builder',ROOT/'scripts/build.py')
builder=importlib.util.module_from_spec(spec); spec.loader.exec_module(builder)
def lua():
    if os.environ.get('LUA'):
        p=os.environ['LUA']; return [p]+(['--luaonly'] if 'tex' in Path(p).name else [])
    for name in ('luajit','lua5.1','lua'):
        if shutil.which(name): return [shutil.which(name)]
    for p in sorted(Path('/usr/local/texlive').glob('*/bin/*/luajittex'),reverse=True): return [str(p),'--luaonly']
    raise RuntimeError('Install LuaJIT / Lua 5.1 or set LUA')
def run(script,*args,cwd=ROOT):
    result=subprocess.run(lua()+[str(script)]+list(map(str,args)),cwd=cwd,text=True,capture_output=True)
    if result.returncode: raise AssertionError(result.stdout+result.stderr)
    return result.stdout
class ReleaseTests(unittest.TestCase):
    def test_package(self):
        with tempfile.TemporaryDirectory() as t:
            a=builder.build(Path(t)/'a.mpackage'); b=builder.build(Path(t)/'b.mpackage')
            self.assertEqual(a.read_bytes(),b.read_bytes())
            self.assertEqual(a.read_bytes(),(ROOT/builder.ARTIFACT).read_bytes())
            files=builder.package_files()
            self.assertEqual(set(files),{builder.PACKAGE+'.xml','config.lua','README.md'})
            for name,data in files.items():
                for forbidden in (b'/Users/',b'/home/'):
                    self.assertNotIn(forbidden,data,name)
            xml=ET.fromstring(files[builder.PACKAGE+'.xml'])
            self.assertFalse(xml.findall('.//Variable'))
            paths=[]
            for i,s in enumerate(xml.iter('script')):
                if s.text:
                    p=Path(t)/f'script{i}.lua';p.write_text(s.text);paths.append(p)
            check=Path(t)/'compile.lua';check.write_text('for _,p in ipairs(arg) do assert(loadfile(p)) end\n')
            run(check,*paths)
    def test_behavior(self):
        for name in ('core','display','ui'):
            print(run(ROOT/'tests'/('test_'+name+'.lua')))
        for windows in (False,True):
            with tempfile.TemporaryDirectory() as folder:
                bootstrap=Path(folder)/'package.lua'
                doc=ET.fromstring(builder.package_files()[builder.PACKAGE+'.xml'])
                bootstrap.write_text(doc.findtext('./ScriptPackage/Script/script'))
                wrapper=Path(folder)/'runner.lua'
                wrapper.write_text('TEST_DIR=arg[1]; local f=assert(io.open(arg[2])); PACKAGE_CODE=f:read("*a"); f:close(); TEST_WINDOWS_RENAME=arg[3]=="true"; dofile("tests/test_adapter.lua")')
                print(run(wrapper,folder,bootstrap,'true' if windows else 'false'))
