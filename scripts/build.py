"""Build one reproducible Mudlet release; no profile data is read."""
from pathlib import Path
import argparse
import xml.etree.ElementTree as ET
import zipfile

ROOT=Path(__file__).resolve().parents[1]
PACKAGE='lotj-cargoscanner'
TITLE='LotJ Cargo Scanner'
VERSION='0.4.0'
ARTIFACT='lotj-cargoscanner.mpackage'

def package_files():
    code=''
    for name,label in [('cargo_core.lua','Core'),('cargo_display.lua','Display'),('cargo_ui.lua','UI')]:
        code+='local '+label+' = (function()\n'+(ROOT/'src'/name).read_text()+'\nend)()\n'
    code+=(ROOT/'src/mudlet_adapter.lua').read_text()
    root=ET.Element('MudletPackage',version='1.001')
    node=ET.SubElement(ET.SubElement(root,'ScriptPackage'),'Script',isActive='yes',isFolder='no')
    ET.SubElement(node,'name').text=TITLE; ET.SubElement(node,'packageName').text=PACKAGE
    ET.SubElement(node,'script').text=code; ET.SubElement(node,'eventHandlerList')
    doc=ET.ElementTree(root)
    xml=b'<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE MudletPackage>\n'+ET.tostring(doc.getroot(),encoding='utf-8')+b'\n'
    config=f'mpackage = [[{PACKAGE}]]\ntitle = [[{TITLE}]]\nversion = [[{VERSION}]]\nauthor = [[Quiggly-Wiggly]]\n'
    return {PACKAGE+'.xml':xml,'config.lua':config.encode(),'README.md':(ROOT/'README.md').read_bytes()}

def build(output=None):
    output=Path(output or ROOT/ARTIFACT)
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,'w') as z:
        for name,data in package_files().items():
            entry=zipfile.ZipInfo(name,(2020,1,1,0,0,0)); entry.create_system=3
            entry.external_attr=0o100644<<16; entry.compress_type=zipfile.ZIP_DEFLATED
            z.writestr(entry,data)
    return output
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('--output')
    print(build(parser.parse_args().output))
