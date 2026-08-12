from __future__ import annotations
import base64, json, random, threading, time, urllib.error, urllib.parse, urllib.request
from dataclasses import dataclass
from typing import Any, Mapping
from .model import *
from .model import _branch, _dict

@dataclass(frozen=True)
class StoredValue: value:dict[str,Any]; version:str
class Store:
    def get(self,path): raise NotImplementedError
    def create(self,path,value,message='swarm: create'): raise NotImplementedError
    def update(self,path,value,expected_version,message='swarm: update'): raise NotImplementedError
    def list(self,prefix): raise NotImplementedError
class MemoryStore(Store):
    def __init__(self): self._d={}; self._n=0; self._lock=threading.RLock()
    def _v(self): self._n+=1; return str(self._n)
    def get(self,path):
        with self._lock:
            if path not in self._d: raise NotFoundError(path)
            x=self._d[path]; return StoredValue(json.loads(json.dumps(x.value)),x.version)
    def create(self,path,value,message='swarm: create'):
        with self._lock:
            if path in self._d: raise ConflictError(path)
            self._d[path]=StoredValue(json.loads(json.dumps(dict(value))),self._v())
            x=self._d[path]; return StoredValue(json.loads(json.dumps(x.value)),x.version)
    def update(self,path,value,expected_version,message='swarm: update'):
        with self._lock:
            if path not in self._d: raise NotFoundError(path)
            if self._d[path].version!=expected_version: raise ConflictError(path)
            self._d[path]=StoredValue(json.loads(json.dumps(dict(value))),self._v())
            x=self._d[path]; return StoredValue(json.loads(json.dumps(x.value)),x.version)
    def list(self,prefix):
        with self._lock:
            return [(p,StoredValue(json.loads(json.dumps(self._d[p].value)),self._d[p].version)) for p in sorted(self._d) if p.startswith(prefix)]
class FaultInjectingStore(MemoryStore):
    def __init__(self): super().__init__(); self.fail_next_create=False; self.fail_next_update=False
    def create(self,*a,**k):
        if self.fail_next_create: self.fail_next_create=False; raise SwarmError('transient write failure')
        return super().create(*a,**k)
    def update(self,*a,**k):
        if self.fail_next_update: self.fail_next_update=False; raise SwarmError('transient write failure')
        return super().update(*a,**k)
class GitHubContentsStore(Store):
    RETRYABLE={429,500,502,503,504}
    def __init__(self,repository,token,branch=DEFAULT_STATE_BRANCH,max_retries=3):
        if repository.count('/')!=1 or not token: raise ValidationError('repository owner/name and token required')
        self.repository,self.owner,self.repo,self.token,self.branch,self.max_retries=repository,*repository.split('/',1),token,_branch(branch,'stateBranch',False),max_retries
    def _request(self,method,path,payload=None):
        body=None if payload is None else json.dumps(payload).encode()
        for attempt in range(self.max_retries+1):
            req=urllib.request.Request('https://api.github.com'+path,method=method,data=body,headers={'Authorization':f'Bearer {self.token}','Accept':'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28','User-Agent':'nembra-swarm-control-plane','Content-Type':'application/json'})
            try:
                with urllib.request.urlopen(req,timeout=30) as r:
                    raw=r.read(); return None if not raw else json.loads(raw.decode())
            except urllib.error.HTTPError as e:
                raw=e.read().decode(errors='replace'); retry=e.headers.get('Retry-After') if e.headers else None; secondary=e.code==403 and ('secondary rate limit' in raw.lower() or retry)
                if attempt<self.max_retries and (e.code in self.RETRYABLE or secondary):
                    base=float(retry) if retry and retry.isdigit() else .4*(2**attempt); time.sleep(base+random.uniform(0,.2)); continue
                raise GitHubAPIError(method,path,e.code,raw) from e
            except urllib.error.URLError as e:
                if attempt<self.max_retries: time.sleep(.4*(2**attempt)+random.uniform(0,.2)); continue
                raise SwarmError(f'GitHub transport failure: {e}') from e
    def _path(self,path): return f"/repos/{self.owner}/{self.repo}/contents/{urllib.parse.quote(safe_relpath(path),safe='/')}"
    def _decode(self,p):
        if p.get('type')!='file' or not isinstance(p.get('content'),str): raise ValidationError('state subject not file')
        try: return _dict(json.loads(base64.b64decode(p['content']).decode()),'state')
        except Exception as e: raise ValidationError('state file invalid JSON') from e
    def get(self,path):
        try: p=self._request('GET',self._path(path)+'?'+urllib.parse.urlencode({'ref':self.branch}))
        except GitHubAPIError as e:
            if e.status==404: raise NotFoundError(path) from e
            raise
        if not isinstance(p,dict) or not isinstance(p.get('sha'),str): raise ValidationError('bad contents response')
        return StoredValue(self._decode(p),p['sha'])
    def create(self,path,value,message='swarm: create'):
        validate_data_only(value); payload={'message':message,'content':base64.b64encode(pretty_json(value).encode()).decode(),'branch':self.branch}
        try: p=self._request('PUT',self._path(path),payload)
        except GitHubAPIError as e:
            if e.status in {409,422}: raise ConflictError(path) from e
            raise
        sha=((p or {}).get('content') or {}).get('sha')
        if not isinstance(sha,str): raise ValidationError('create omitted SHA')
        return StoredValue(dict(value),sha)
    def update(self,path,value,expected_version,message='swarm: update'):
        validate_data_only(value); payload={'message':message,'content':base64.b64encode(pretty_json(value).encode()).decode(),'branch':self.branch,'sha':expected_version}
        try: p=self._request('PUT',self._path(path),payload)
        except GitHubAPIError as e:
            if e.status in {409,422}: raise ConflictError(path) from e
            if e.status==404: raise NotFoundError(path) from e
            raise
        sha=((p or {}).get('content') or {}).get('sha')
        if not isinstance(sha,str): raise ValidationError('update omitted SHA')
        return StoredValue(dict(value),sha)
    def list(self,prefix):
        out=[]
        def walk(path):
            try: p=self._request('GET',self._path(path)+'?'+urllib.parse.urlencode({'ref':self.branch,'per_page':100}))
            except GitHubAPIError as e:
                if e.status==404:return
                raise
            if isinstance(p,dict):
                if p.get('type')!='file' or not isinstance(p.get('sha'),str): raise ValidationError('bad list subject')
                out.append((path,StoredValue(self._decode(p),p['sha']))); return
            if not isinstance(p,list): raise ValidationError('bad directory response')
            for e in p:
                child=e.get('path'); kind=e.get('type')
                if not isinstance(child,str): raise ValidationError('directory entry missing path')
                if kind=='dir' or (kind=='file' and child.endswith('.json')): walk(child)
        walk(safe_relpath(prefix.rstrip('/'))); return sorted(out)
