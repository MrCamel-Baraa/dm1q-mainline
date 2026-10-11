#!/usr/bin/env python3
"""Rebuild the upstream fix for pcie-qcom.c on the pristine 7.3-rc3 file and prove it is byte-identical
to the upstream post-image (git blob 42cbeef083ca, from the index line of the posted patch).

Usage: mkpatch.py <pristine pcie-qcom.c> <patched copy to write>
Then: diff -u (see build-patch.sh) gives the patch carried in the pmaports package.
"""
import subprocess, sys

SRC = sys.argv[1]       # pristine drivers/pci/controller/dwc/pcie-qcom.c
OUT = sys.argv[2]       # patched copy to write
s = open(SRC).read()


def sub(old, new):
    global s
    assert s.count(old) == 1, "pattern not unique/found:\n" + old
    s = s.replace(old, new)


sub("""	/* iommu map structure */
	struct {
		u32 bdf;
		u32 phandle;
		u32 smmu_sid;
		u32 smmu_sid_len;
	} *map;
	void __iomem *bdf_to_sid_base = pcie->parf + PARF_BDF_TO_SID_TABLE_N;
	struct device *dev = pcie->pci->dev;
	u8 qcom_pcie_crc8_table[CRC8_TABLE_SIZE];
	int i, nr_map, size = 0;
	u32 smmu_sid_base;
	u32 val;

	of_get_property(dev->of_node, "iommu-map", &size);
	if (!size)
		return 0;

""", """	void __iomem *bdf_to_sid_base = pcie->parf + PARF_BDF_TO_SID_TABLE_N;
	struct device *dev = pcie->pci->dev;
	struct device_node *iommu_np;
	u8 qcom_pcie_crc8_table[CRC8_TABLE_SIZE];
	const __be32 *map;
	u32 iommu_cells, entry_cells, phandle, smmu_sid_base;
	int i, nr_cells, nr_map, size = 0;
	u32 val;

	map = of_get_property(dev->of_node, "iommu-map", &size);
	if (!map || !size)
		return 0;

	if (size % sizeof(*map)) {
		dev_err(dev, "Malformed iommu-map property\\n");
		return -EINVAL;
	}
	nr_cells = size / sizeof(*map);

	/*
	 * Each iommu-map entry is: rid-base (1 cell), phandle (1 cell),
	 * IOMMU specifier (#iommu-cells cells), length (1 cell). Read
	 * #iommu-cells from the IOMMU provider referenced by the first
	 * entry to compute the per-entry stride.
	 */
	phandle = be32_to_cpu(map[1]);
	iommu_np = of_find_node_by_phandle(phandle);
	if (!iommu_np) {
		dev_err(dev, "Failed to find IOMMU node in iommu-map\\n");
		return -ENODEV;
	}

	if (of_property_read_u32(iommu_np, "#iommu-cells", &iommu_cells))
		iommu_cells = 1;
	of_node_put(iommu_np);

	entry_cells = 3 + iommu_cells;

	/*
	 * Retain backward compatibility with DTs that describe iommu-map
	 * with 4-cell entries against an IOMMU declaring #iommu-cells = 2,
	 * matching the fallback in drivers/of/base.c::of_check_bad_map().
	 */
	if (iommu_cells == 2 && !(nr_cells % 4)) {
		bool legacy = true;

		for (i = 0; i < nr_cells; i += 4) {
			if (be32_to_cpu(map[i + 1]) != phandle ||
			    be32_to_cpu(map[i + 3]) != 1) {
				legacy = false;
				break;
			}
		}

		if (legacy) {
			dev_warn_once(dev, "iommu-map has 1-cell entries targeting 2-cell #iommu-cells, treating as 1-cell output\\n");
			entry_cells = 4;
		}
	}

	if (nr_cells % entry_cells) {
		dev_err(dev, "Malformed iommu-map property\\n");
		return -EINVAL;
	}
	nr_map = nr_cells / entry_cells;

""")

sub("""	map = kzalloc(size, GFP_KERNEL);
	if (!map)
		return -ENOMEM;

	of_property_read_u32_array(dev->of_node, "iommu-map", (u32 *)map,
				   size / sizeof(u32));

	nr_map = size / (sizeof(*map));

""", "")

sub("	smmu_sid_base = map[0].smmu_sid;\n", "	smmu_sid_base = be32_to_cpu(map[2]);\n")

sub("""		__be16 bdf_be = cpu_to_be16(map[i].bdf);
		u32 val;
		u8 hash;
""", """		u32 bdf = be32_to_cpu(map[i * entry_cells]);
		u32 sid = be32_to_cpu(map[i * entry_cells + 2]);
		__be16 bdf_be = cpu_to_be16(bdf);
		u8 hash;
""")

sub("		val = map[i].bdf << 16 | (map[i].smmu_sid - smmu_sid_base) << 8 | 0;\n",
    "		val = bdf << 16 | (sid - smmu_sid_base) << 8 | 0;\n")

sub("""	kfree(map);

	return 0;
}

static int qcom_pcie_get_resources_2_9_0""", """	return 0;
}

static int qcom_pcie_get_resources_2_9_0""")

open(OUT, "w").write(s)
h = subprocess.run(["git", "hash-object", OUT], capture_output=True, text=True).stdout.strip()
ok = h.startswith("42cbeef083ca")
print("post-image blob:", h, "-> upstream index line says 42cbeef083ca:", "MATCH" if ok else "DIFFERENT")
sys.exit(0 if ok else 1)
