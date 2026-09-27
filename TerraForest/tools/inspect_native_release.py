from concurrent.futures import ThreadPoolExecutor
import json
import urllib.request

urls = [
    'https://api.github.com/repos/BoQsc/godot-cpp-prebuilt/releases/tags/api-4.7-d7b6162-zig',
    'https://raw.githubusercontent.com/BoQsc/godot-cpp-prebuilt/main/README.md',
    'https://ziglang.org/download/index.json',
]

def inspect(url):
    try:
        req=urllib.request.Request(url,headers={'User-Agent':'TerraForest-build'})
        raw=urllib.request.urlopen(req,timeout=30).read().decode()
        if 'api.github.com' in url:
            data=json.loads(raw)
            raw=json.dumps({'body':data['body'],'assets':[{k:a.get(k) for k in ['name','size','browser_download_url','digest']} for a in data['assets']]},indent=2)
        elif 'ziglang.org' in url:
            data=json.loads(raw).get('0.16.0',{})
            raw=json.dumps({k:v for k,v in data.items() if k in ['version','date','x86_64-windows']},indent=2)
        return url+'\n'+raw
    except Exception as error:
        return url+'\n'+str(error)

for result in ThreadPoolExecutor(3).map(inspect,urls):
    print(result)
