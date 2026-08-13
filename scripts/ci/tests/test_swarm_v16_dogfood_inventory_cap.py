#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
import sys
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts'))
import swarm_control as sc
import swarm_v16_dogfood as dogfood


class FakeResponse:
    def __init__(self,payload): self.payload=payload
    def __enter__(self): return self
    def __exit__(self,*args): return False
    def read(self): return json.dumps(self.payload).encode()


class DogfoodInventoryCapTests(unittest.TestCase):
    def four_full_pages(self):
        batches=[]
        for page in range(4):
            start=page*100+1
            batches.append([{'number':number} for number in range(start,start+100)])
        return batches

    @mock.patch.object(dogfood.urllib.request,'urlopen')
    def test_exactly_four_hundred_is_complete_after_empty_probe(self,urlopen):
        batches=self.four_full_pages()+[[]]
        urlopen.side_effect=[FakeResponse(batch) for batch in batches]

        prs=dogfood.fetch_open_prs('owner/repo','token')

        self.assertEqual(len(prs),400)
        self.assertEqual(prs[-1]['number'],400)
        self.assertEqual(urlopen.call_count,5)
        probe_url=urlopen.call_args_list[-1].args[0].full_url
        self.assertIn('per_page=100',probe_url)
        self.assertIn('page=5',probe_url)

    @mock.patch.object(dogfood.urllib.request,'urlopen')
    def test_four_hundred_one_fails_closed_instead_of_truncating(self,urlopen):
        batches=self.four_full_pages()+[[{'number':401}]]
        urlopen.side_effect=[FakeResponse(batch) for batch in batches]

        with self.assertRaisesRegex(sc.ValidationError,'refusing partial classification'):
            dogfood.fetch_open_prs('owner/repo','token')
        self.assertEqual(urlopen.call_count,5)

    @mock.patch.object(dogfood.urllib.request,'urlopen')
    def test_short_inventory_does_not_probe(self,urlopen):
        urlopen.side_effect=[FakeResponse([{'number':1},{'number':2}])]

        prs=dogfood.fetch_open_prs('owner/repo','token')

        self.assertEqual([pr['number'] for pr in prs],[1,2])
        self.assertEqual(urlopen.call_count,1)


if __name__=='__main__': unittest.main()
