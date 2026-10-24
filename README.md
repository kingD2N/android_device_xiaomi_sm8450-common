
# Common device configuration for Xiaomi Taro family

## Currently supported SoCs

- SM8450 (taro)
- SM8475 (cape)
- SM7475 (ukee)

## Currently supported devices:

- Xiaomi 12 (cupid)
- Redmi K50 Ultra / Xiaomi 12T Pro (diting)
- POCO F4 GT / Redmi K50 Gaming (ingres)
- POCO F5 / Redmi Note 12 Turbo (marble)

## Copyright

```
Copyright (C) 2023-24 Paranoid Android

SPDX-License-Identifier: Apache-2.0
```

## Building the ingres kernel from source

By default the kernel comes prebuilt from `device/xiaomi/ingres-kernel`
(`KERNEL_PREBUILT_DIR`). To compile the kernel `Image` from source instead
([kingD2N/Tree_ingres](https://github.com/kingD2N/Tree_ingres), branch
`melt-ingres` — Melt-MIX 5.10.272 + ingres drivers):

```bash
cp device/xiaomi/sm8450-common/kernel/local_manifest.xml .repo/local_manifests/ingres-kernel-source.xml
repo sync -c kernel/xiaomi/sm8450
device/xiaomi/sm8450-common/kernel/build-kernel.sh ingres   # Image + System.map -> device/xiaomi/ingres-kernel
./rom-build.sh ingres
```

The script uses the same config fragments as the Melt-MIX CI
(`gki_defconfig vendor/waipio_GKI.config vendor/xiaomi_GKI.config vendor/ingres_GKI.config vendor/debugfs.config`)
and the newest `prebuilts/clang` of the ROM tree. DTB/DTBO and the vendor
modules stay the prebuilt LineageOS 23.2 ones; the new `Image` is installed
only if its symbol CRCs match all of those modules (`tools/crccheck.py`),
otherwise it stops with exit code 3. The previous Image is kept as
`Image.prebuilt` for rollback.
