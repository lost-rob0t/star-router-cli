"""Real CLI generation and Couch HTTP submission boundaries."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

root = Path(__file__).resolve().parents[1]
schema = json.loads((root / "schemas/starintel-0.10.1/generated/schema.json").read_text())
manifest = json.loads((root / "schemas/starintel-0.10.1/generated/portable-manifest.json").read_text())
research_fixtures = json.loads((root / "schemas/starintel-0.10.1/research-fixtures.json").read_text())
raw_key_cases = json.loads((root / "fixtures/raw-json-unique-keys.json").read_text())["cases"]
minimal_operation = next(case["document"] for case in research_fixtures if case["name"] == "minimal-operation" and case["valid"])

def sample(node):
    if "$ref" in node:
        return sample(schema["$defs"][node["$ref"].split("/")[-1]])
    if "enum" in node:
        return node["enum"][0]
    if "anyOf" in node:
        return sample(node["anyOf"][0])
    kind = node.get("type")
    if kind == "object":
        return {key: sample(node["properties"][key]) for key in node.get("required", [])}
    if kind == "array": return []
    if kind in ("integer", "number"): return node.get("minimum", 0)
    if kind == "boolean": return False
    if node.get("format") == "date-time": return "2026-10-04T12:00:00Z"
    if node.get("format") == "date": return "2026-10-04"
    if node.get("format") == "uri": return "https://example.test/"
    if "pattern" in node:
        if "@" in node["pattern"]: return "fixture@example.test"
        if "0-9()." in node["pattern"]: return "+123456789"
        return "0"
    return "fixture"

binary=sys.argv[1]
requests=[]
reject=False
class Couch(BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def do_POST(self):
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        requests.append((self.path,body))
        if self.path=='/_session':
            response={'ok':True}
        else:
            assert self.path=='/test/_bulk_docs'
            assert isinstance(body['docs'],list)
            response=[{'id':d['_id'],'ok':True} for d in body['docs']]
            if reject: response[0]={'id':body['docs'][0]['_id'],'error':'conflict'}
        payload=json.dumps(response).encode()
        self.send_response(200)
        self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(payload)))
        self.send_header('Set-Cookie','AuthSession=test; Path=/')
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',0),Couch)
thread=threading.Thread(target=server.serve_forever,daemon=True)
thread.start()
def run(*args):return subprocess.run([binary,*args],capture_output=True,text=True,timeout=30)
try:
    options={'opaque':{'flag':False,'nil':None,'items':[]}}
    first=run('target','--dataset=test','--target=example.com','--actor=certsh','--options='+json.dumps(options))
    assert first.returncode==0, first.stderr
    document=json.loads(first.stdout)
    assert document['schemaVersion']=='0.10.1' and document['dtype']=='target' and 'id' in document
    assert '_id' not in document and 'data' not in document
    assert document['options']==options and document['recurring'] is False
    assert run('target','--dataset=test','--target=example.com','--actor=certsh','--options=[]').returncode!=0
    with tempfile.TemporaryDirectory() as directory:
        root=Path(directory)
        values=['one.example','two.example','three.example','four.example','five.example']
        targets=root/'targets.txt';targets.write_text('\n'.join(values)+'\n')
        result=run('target','--dataset=test','--target='+str(targets),'--actor=certsh','--bulk')
        assert result.returncode==0,result.stderr
        documents=[json.loads(line) for line in result.stdout.splitlines()]
        assert [d['target'] for d in documents]==values
        assert len({d['id'] for d in documents})==5
        documents[0]['extensions']={'opaque':{'flag':False,'nil':None,'items':[]}}
        documents[0]['rev']='1-test'
        path=root/'documents.ndjson';path.write_text(''.join(json.dumps(d)+'\n' for d in documents))
        config=root/'config.ini';config.write_text(f'[DB]\ndatabase=test\ntargetdb=targets\nuser=test\npassword=test\nhost="http://127.0.0.1"\nport={server.server_port}\n[MAIN]\nverbose=false\ndefault-dataset=test\n[ROUTER]\napi-address=tcp://127.0.0.1:6001\npub-address=tcp://127.0.0.1:6000\n')
        args=('insert_data','--configPath='+str(config),'--file='+str(path),'--bulkSize=2')
        result=run(*args)
        assert result.returncode==0,result.stderr
        batches=[body['docs'] for name,body in requests if name=='/test/_bulk_docs']
        assert list(map(len,batches))==[2,2,1]
        uploaded=[d for batch in batches for d in batch]
        for original,physical in zip(documents,uploaded):
            expected=dict(original);expected['_id']=expected.pop('id')
            if 'rev' in expected:expected['_rev']=expected.pop('rev')
            assert physical==expected
        requests.clear()
        inventory=[]
        transient=[]
        for entry in manifest['types']:
            if entry['kind'] != 'document': continue
            dtype=entry['name'].split('/')[-1]
            if entry.get('persistence','persistent') != 'persistent':
                transient.append(dtype)
                continue
            name=''.join(word.capitalize() for word in dtype.split('-'))
            value=dict(minimal_operation) if dtype=='operation' else sample(schema['$defs'][name])
            value.update(id='fixture:'+dtype,dataset='test',dtype=dtype,schemaVersion='0.10.1',
                         extensions={'opaque':{'flag':False,'nil':None,'items':[]}})
            inventory.append(value)
        assert len(inventory)==90
        assert len(transient)==33 and 'operation-condition' in transient
        path.write_text(''.join(json.dumps(d)+'\n' for d in inventory))
        result=run('insert_data','--configPath='+str(config),'--file='+str(path),'--bulkSize=17')
        assert result.returncode==0,result.stderr
        batches=[body['docs'] for name,body in requests if name=='/test/_bulk_docs']
        assert list(map(len,batches))==[17,17,17,17,17,5]
        for original,physical in zip(inventory,[d for batch in batches for d in batch]):
            expected=dict(original);expected['_id']=expected.pop('id')
            assert physical==expected
        requests.clear()
        for case in raw_key_cases:
            path.write_text(case['wire']+'\n')
            result=run(*args)
            if case['valid']:
                assert result.returncode==0, (case['name'],result.stderr)
                bulk=[body['docs'] for name,body in requests if name=='/test/_bulk_docs']
                assert len(bulk)==1 and len(bulk[0])==1, (case['name'],requests)
            else:
                assert result.returncode!=0 and not requests, (case['name'],result.stderr,requests)
            requests.clear()
        path.write_text('{"id":"bad","dataset":"test","dtype":"person","schemaVersion":"0.10.1","extensions":{"n":01}}\n')
        result=run(*args)
        assert result.returncode!=0 and not requests, (result.stderr,requests)
        path.write_bytes(b'{"id":"bad","dataset":"test","dtype":"person","schemaVersion":"0.10.1","extensions":{"text":"\\xff"}}\n')
        result=run(*args)
        assert result.returncode!=0 and not requests, (result.stderr,requests)
        requests.clear()
        legacy={'_id':'starintel:person:test','dataset':'test','dtype':'person','schema_version':'0.9.0',
                'version':1,'date_added':'2026-10-04T00:00:00Z','date_updated':'2026-10-04T00:00:00Z',
                'sources':[],'evidence':[],'data':{'fname':'Ada'},'extensions':{'opaque':{'flag':False,'nil':None}}}
        path.write_text(json.dumps(legacy)+'\n')
        result=run(*args)
        assert result.returncode==0,result.stderr
        assert [body['docs'] for name,body in requests if name=='/test/_bulk_docs']==[[legacy]]
        requests.clear()
        path.write_text(json.dumps(documents[0])+'\n'+json.dumps({'schema_version':'0.10.1','dtype':'person','data':{}})+'\n')
        result=run(*args)
        assert result.returncode!=0 and not requests, (result.stderr,requests)
        path.write_text(json.dumps(documents[0])+'\n')
        reject=True
        result=run(*args)
        assert result.returncode!=0 and 'conflict' in result.stderr
    print('actual CLI: generated targets, 90 persistent dtypes, 33 transient excluded, strict raw NDJSON, explicit 0.9.0, complete batching, Couch projection, pre-network rejection, bulk errors PASS')
finally:
    server.shutdown();server.server_close();thread.join(timeout=5)
