#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
from pathlib import Path
import sys
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc


def encoded(value):
    raw=base64.b64encode((json.dumps(value)+'\n').encode()).decode()
    return '\n'.join(raw[i:i+60] for i in range(0,len(raw),60))+'\n'


class FakeContentsStore(sc.GitHubContentsStore):
    def __init__(self,responses):
        super().__init__('owner/repo','token','swarm-state')
        self.responses=responses
        self.calls=[]
    def _request(self,method,path,payload=None):
        self.calls.append((method,path,payload))
        for matcher,response in self.responses:
            if matcher in path:
                if callable(response): return response(method,path,payload)
                return json.loads(json.dumps(response))
        raise AssertionError(f'unexpected request: {method} {path}')


class LargeStateReadTests(unittest.TestCase):
    def test_inline_line_wrapped_base64_contents_reads(self):
        value={'schemaVersion':16,'kind':'test-state','x':1}
        store=FakeContentsStore([('/contents/.swarm/runtime/v16/mission-graph.json',{'type':'file','sha':'abc','encoding':'base64','content':encoded(value)})])
        stored=store.get('.swarm/runtime/v16/mission-graph.json')
        self.assertEqual(stored.value,value); self.assertEqual(stored.version,'abc')
        self.assertFalse(any('/git/blobs/' in path for _,path,_ in store.calls))

    def test_missing_inline_content_falls_back_to_exact_blob_sha(self):
        value={'schemaVersion':16,'kind':'mission-graph','large':True}
        store=FakeContentsStore([
            ('/contents/.swarm/runtime/v16/mission-graph.json',{'type':'file','sha':'blob123','encoding':'none','size':1500000}),
            ('/git/blobs/blob123',{'sha':'blob123','encoding':'base64','content':encoded(value)}),
        ])
        stored=store.get('.swarm/runtime/v16/mission-graph.json')
        self.assertEqual(stored.value,value); self.assertEqual(stored.version,'blob123')
        self.assertTrue(any(path.endswith('/git/blobs/blob123') for _,path,_ in store.calls))

    def test_empty_inline_content_also_uses_blob(self):
        value={'schemaVersion':16,'kind':'mission-graph'}
        store=FakeContentsStore([
            ('/contents/state.json',{'type':'file','sha':'empty-inline','encoding':'none','content':''}),
            ('/git/blobs/empty-inline',{'sha':'empty-inline','encoding':'base64','content':encoded(value)}),
        ])
        self.assertEqual(store.get('state.json').value,value)

    def test_blob_sha_mismatch_fails_closed(self):
        store=FakeContentsStore([
            ('/contents/state.json',{'type':'file','sha':'wanted','encoding':'none'}),
            ('/git/blobs/wanted',{'sha':'different','encoding':'base64','content':encoded({'x':1})}),
        ])
        with self.assertRaises(sc.ValidationError): store.get('state.json')

    def test_invalid_non_whitespace_base64_still_fails_closed(self):
        store=FakeContentsStore([('/contents/state.json',{'type':'file','sha':'bad','encoding':'base64','content':'eyJ4IjogMX0=***'})])
        with self.assertRaises(sc.ValidationError): store.get('state.json')

    def test_blob_without_supported_content_fails_closed(self):
        store=FakeContentsStore([
            ('/contents/state.json',{'type':'file','sha':'wanted','encoding':'none'}),
            ('/git/blobs/wanted',{'sha':'wanted','encoding':'none','content':None}),
        ])
        with self.assertRaises(sc.ValidationError): store.get('state.json')

    def test_list_file_metadata_uses_same_blob_fallback(self):
        value={'schemaVersion':16,'kind':'mission-graph'}
        directory=[{'type':'file','path':'.swarm/runtime/v16/mission-graph.json'}]
        store=FakeContentsStore([
            ('/contents/.swarm/runtime/v16/mission-graph.json',{'type':'file','sha':'listed','encoding':'none','size':1500000}),
            ('/contents/.swarm/runtime/v16',directory),
            ('/git/blobs/listed',{'sha':'listed','encoding':'base64','content':encoded(value)}),
        ])
        rows=store.list('.swarm/runtime/v16')
        self.assertEqual(len(rows),1); self.assertEqual(rows[0][1].value,value); self.assertEqual(rows[0][1].version,'listed')


if __name__=='__main__': unittest.main()
