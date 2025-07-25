# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import os
import unittest
import unittest.mock

from bitstreams_workspace import BitstreamCache

MOCK_MANIFEST = """{
   "schema_version": 3,
   "designs": {
       "chip_earlgrey_cw310": {
           "build_id": "abcd",
           "bitstream": {
               "file": "lowrisc_systems_chip_earlgrey_cw310_0.1.bit",
               "build_target": "//hw/bitstream/vivado:fpga_cw310"
           },
           "memory_map_info": {
               "file": "memories.mmi",
               "build_target": "//hw/bitstream/vivado:fpga_cw310",
               "memories": ["otp", "rom"]
           }
       }
   }
}"""


class TestBitstreamCache(unittest.TestCase):

    def test_make_with_default(self):
        # Changes to command-line argument defaults could break this method, so
        # it's important to at least have code coverage.
        BitstreamCache.MakeWithDefaults()

    def test_get_from_cache(self):
        MOCK_BITSTREAM = 'lowrisc_systems_chip_earlgrey_cw310_0.1.bit'

        MOCKED_OS_WALK_RETURN = [
            # os.walk() yields tuples of the form (root, dir, files).
            ('cache/abcd', [],
             [MOCK_BITSTREAM, 'manifest.json', 'memories.mmi']),
        ]
        os.walk = unittest.mock.MagicMock(name='os.walk',
                                          return_value=MOCKED_OS_WALK_RETURN)

        cache = BitstreamCache('/',
                               '/tmp/cache/opentitan-bitstreams',
                               'latest.txt',
                               offline=True)
        cache.InitRepository = unittest.mock.MagicMock(name='method')

        m = unittest.mock.mock_open(read_data=MOCK_MANIFEST)
        with unittest.mock.patch('bitstreams_workspace.open', m):
            (manifest, manifest_path) = cache.GetFromCache('abcd')
        m.assert_called_once_with('cache/abcd/manifest.json', 'r')

        # This is more of an implementation detail, but it verifies that we hit
        # the mocked `os.walk` function as expected.
        os.walk.assert_called_once_with('cache/abcd')

        self.maxDiff = None
        self.assertEqual(
            manifest, {
                "schema_version": 3,
                "designs": {
                    "chip_earlgrey_cw310": {
                        "build_id": "abcd",
                        "bitstream": {
                            "file": MOCK_BITSTREAM,
                            "build_target": "//hw/bitstream/vivado:fpga_cw310",
                        },
                        "memory_map_info": {
                            "file": "memories.mmi",
                            "build_target": "//hw/bitstream/vivado:fpga_cw310",
                            "memories": ["otp", "rom"],
                        },
                    },
                },
            })

        os.walk.assert_called_once_with('cache/abcd')

    def test_write_build_file(self):
        BITSTREAM_ORIG = 'lowrisc_systems_chip_earlgrey_cw310_0.1.bit.orig'
        BITSTREAM_SPLICE = 'lowrisc_systems_chip_earlgrey_cw310_0.1.bit.splice'

        MOCKED_OS_WALK_RETURN = [
            # os.walk() yields tuples of the form (root, dir, files).
            ('cache/abcd', [],
             [BITSTREAM_ORIG, BITSTREAM_SPLICE, 'manifest.json', 'memories.mmi']),
        ]
        os.walk = unittest.mock.MagicMock(name='os.walk',
                                          return_value=MOCKED_OS_WALK_RETURN)

        BitstreamCache._GetDateTimeStr = unittest.mock.MagicMock(
            name='BitstreamCache._GetDateTimeStr',
            return_value='2022-07-14T15:02:54.463801')

        cache = BitstreamCache('/',
                               '/tmp/cache/opentitan-bitstreams',
                               'latest.txt',
                               offline=True)
        manifest = {
            "schema_version": 3,
            "designs": {
                "chip_earlgrey_cw310": {
                    "build_id": "abcd",
                    "bitstream": {
                        "file": "lowrisc_systems_chip_earlgrey_cw310_0.1.bit.orig",
                        "build_target": "//hw/bitstream/vivado:fpga_cw310",
                    },
                    "memory_map_info": {
                        "file": "memories.mmi",
                        "build_target": "//hw/bitstream/vivado:fpga_cw310",
                        "memories": ["otp", "rom"],
                    },
                },
            },
        }
        manifest_path = "cache/abcd/substitute_manifest.json"
        bazel_string = cache._ConstructBazelString('BUILD.mock', 'abcd', manifest, manifest_path)
        self.maxDiff = None
        self.assertEqual(
            bazel_string, '''# This file was autogenerated. Do not edit!
# Built at 2022-07-14T15:02:54.463801.
# Configured for bitstream: abcd

package(default_visibility = ["//visibility:public"])

exports_files(glob(["cache/**"]))

filegroup(
    name = "chip_earlgrey_cw310_bitstream",
    srcs = ["cache/abcd/lowrisc_systems_chip_earlgrey_cw310_0.1.bit.orig"],
)

filegroup(
    name = "chip_earlgrey_cw310_mmi",
    srcs = ["cache/abcd/memories.mmi"],
)

filegroup(
    name = "manifest",
    srcs = ["cache/abcd/substitute_manifest.json"],
)

alias(
    name = "chip_earlgrey_cw310_hyperdebug_bitstream",
    actual = "@//hw/bitstream/vivado:fpga_cw310_test_rom_hyp",
)

alias(
    name = "chip_earlgrey_cw310_hyperdebug_mmi",
    actual = "@//hw/bitstream/vivado:cw310_hyperdebug_mmi",
)

alias(
    name = "chip_earlgrey_cw340_bitstream",
    actual = "@//hw/bitstream/vivado:fpga_cw340_test_rom",
)

alias(
    name = "chip_earlgrey_cw340_mmi",
    actual = "@//hw/bitstream/vivado:cw340_mmi",
)
''')


class TestFetchAvailableBitstreams(unittest.TestCase):
    """
    The BitstreamCache.GetBitstreamsAvailable method calls the XML API on
    the root level of the GCP bucket to get the list of files in the
    bitstream cache. If this list is sufficiently long, the response will
    be paginated, as indicated by the <IsTruncated> tag. For p pages,
    GetBitstreamsAvailable is expected to make p+1 calls to the API (using
    BitstreamCache.Get). The last call is to get latest.txt which indicates
    the latest bitstream.

    The XML response elements are documented here:
    https://cloud.google.com/storage/docs/xml-api/get-bucket-list#response_body_elements
    """

    def setUp(self):
        self.cache = BitstreamCache('/', '/tmp/cache/opentitan-bitstreams',
                                    'latest.txt')
        self.cache.InitRepository = unittest.mock.MagicMock(name='method')

    def test_fetch_available_bitstreams_single_page(self):
        """Test fetching the available bitstreams without pagination."""

        MOCKED_GET_RETURN = [
            b"""<ListBucketResult xmlns="http://doc.s3.amazonaws.com/2006-03-01">
<Name>opentitan-bitstreams</Name>
<Prefix/>
<Marker/>
<IsTruncated>false</IsTruncated>
<Contents>
<Key>master/bitstream-0.tar.gz</Key>
<Generation>1669083850593267</Generation>
<MetaGeneration>1</MetaGeneration>
<LastModified>2022-11-22T02:24:10.633Z</LastModified>
<ETag>"e82b93a0f88161e594ef79f41277de92"</ETag>
<Size>18845320</Size>
</Contents>
</ListBucketResult>""", b"""2022-12-01T14:54:13
0"""
        ]

        # Mock out the Get method to simulate a network access
        self.cache.Get = unittest.mock.MagicMock(
            name='cache.Get',
            side_effect=MOCKED_GET_RETURN,
        )
        self.cache.GetBitstreamsAvailable(branch="earlgrey_1.0.0", refresh=True)
        self.assertEqual(self.cache.Get.call_count, 2)
        self.assertEqual(self.cache.available, {
            "0": "master/bitstream-0.tar.gz",
            "latest": "0",
        })

    def test_fetch_available_bitstreams_with_pagination(self):
        """Test fetching the XML file with the list of available bitstreams."""
        MOCKED_GET_RETURN = [
            b"""<ListBucketResult xmlns="http://doc.s3.amazonaws.com/2006-03-01">
<Name>opentitan-bitstreams</Name>
<Prefix/>
<Marker/>
<NextMarker>master/bitstream-1.tar.gz</NextMarker>
<IsTruncated>true</IsTruncated>
<Contents>
<Key>master/bitstream-0.tar.gz</Key>
<Generation>1656382040594268</Generation>
<MetaGeneration>1</MetaGeneration>
<LastModified>2022-06-28T02:07:20.635Z</LastModified>
<ETag>"5b6f3f9ef43f67b988cac31c73949e85"</ETag>
<Size>12254300</Size>
</Contents>
</ListBucketResult>""",
            b"""<ListBucketResult xmlns="http://doc.s3.amazonaws.com/2006-03-01">
<Name>opentitan-bitstreams</Name>
<Prefix/>
<Marker>master/bitstream-1.tar.gz</Marker>
<IsTruncated>false</IsTruncated>
<Contents>
<Key>master/bitstream-1.tar.gz</Key>
<Generation>1656382040594268</Generation>
<MetaGeneration>1</MetaGeneration>
<LastModified>2022-06-28T02:07:20.635Z</LastModified>
<ETag>"5b6f3f9ef43f67b988cac31c73949e85"</ETag>
<Size>12254300</Size>
</Contents>
<Contents>
<Key>master/latest.txt</Key>
<Generation>1669836798495359</Generation>
<MetaGeneration>1</MetaGeneration>
<LastModified>2022-11-30T19:33:18.615Z</LastModified>
<ETag>"58498757ff6f02bcbfbae67eb92dfa4b"</ETag>
<Size>60</Size>
</Contents>
</ListBucketResult>
""", b"""2022-12-01T14:54:13
1"""
        ]

        # Mock out the Get method to simulate a network access
        self.cache.Get = unittest.mock.MagicMock(
            name='cache.Get',
            side_effect=MOCKED_GET_RETURN,
        )
        self.cache.GetBitstreamsAvailable(branch="earlgrey_1.0.0", refresh=True)
        self.assertEqual(self.cache.Get.call_count, 3)
        self.assertEqual(
            self.cache.available, {
                "0": "master/bitstream-0.tar.gz",
                "1": "master/bitstream-1.tar.gz",
                "latest": "1",
            })


if __name__ == '__main__':
    unittest.main()
