# RootFS v0.3.3 合规证据 / Compliance evidence

这里保存从固定 RootFS archive 可复现生成的工程证据，不保存 RootFS 本身。

This directory stores reproducible engineering evidence generated from the
pinned RootFS archive. It does not store the RootFS payload.

## 已生成 / Generated

- `PACKAGE-INVENTORY.tsv`：15 个已安装二进制包的完整 APK database 清单；
- `SBOM.spdx.json`：通过 SPDX 2.3 JSON schema 验证的 machine-readable SBOM；
- `SOURCE-INVENTORY.json`：10 个 source origin、精确 aports commit 和 build recipe
  locator；
- `SOURCE-ACQUISITION.json`：与 inventory 一一对应的 aports snapshot、upstream
  distfile URL 和 SHA-512，以及覆盖条目类型、路径、普通文件权限位与内容的规范化目录
  SHA-256；
- `CORRESPONDING-SOURCE-REVIEW-RESULTS.json`：绑定全部 10 个 source origin、
  130 个规范化 aports 条目和 9 个 upstream distfile 的对应源码候选材料工程
  复核；重建环境、法律、源码提供、交付与再分发批准保持关闭；
- `REBUILD-ENVIRONMENT-REVIEW.json`：区分固定 v0.3.3 发布归档与后继候选；
  历史 builder 源码已定位，但发布归档的精确 toolchain/重建仍无法验证；后继
  schema-v4 候选在两次独立调用、共四次构建中得到相同 archive，并保留各次
  host tool/environment receipt；
- `SOURCE-DELIVERY-INVENTORY.json`：把历史/后继 builder、固定 Alpine 输入、
  10 个 origin 的源码材料与 RootFS 修改披露列成 5 个交付单元；inventory
  与统一仓库外候选 materializer 已完整，但 checked-in 证据不声称实际候选已经
  材料化，源码提供、法律、交付与再分发批准仍关闭；
- `LICENSE-INVENTORY.json`：声明的许可证表达式、标识符和 archive 内
  license/notice 文件检查结果；
- `LICENSE-REVIEW.json`：覆盖 10 个 source origin 的 78 个候选许可证文本、
  attribution、声明与内联 notice 的路径、大小、SHA-256 和逐包未决审查项；
- `LICENSE-REVIEW-RESULTS.json`：对全部 78 个候选的 checksum-bound 工程复核
  结论、coverage 和未决项处置；不表示法律或再分发批准；
- `LICENSE-NOTICE-CANDIDATES.json`：为剩余 8 个 source origin 固定 13 份远端
  许可证/attribution 材料、47 份 aports 补充文件及现有 78 份复核证据的外置候选包；
  payload 不提交，工程、法律和再分发门禁保持关闭；
- `LICENSE-NOTICE-REVIEW-RESULTS.json`：绑定候选清单与 138 个 payload 文件树的
  工程复核结果；7 个 origin 的候选材料工程项关闭，只有 `alpine-keys` 因缺少
  上游 MIT grant/版权声明仍未决，法律和再分发门禁保持关闭；
- `RUNTIME-CONFIGURATION.json`：guest、`apk`、repository、world 和 DNS 默认配置；
- `NOTICE.md`：可复现 attribution inventory 与尚未完成事项；
- `EVIDENCE.json`：输入成员摘要、数量和明确的工程/发行状态；
- `SHA256SUMS`：上述生成文件的 SHA-256。

`SOURCE-ACQUISITION.json` pins the aports snapshots and upstream distfiles
needed to assemble an external corresponding-source candidate directory.
`CORRESPONDING-SOURCE-REVIEW-RESULTS.json` binds engineering review of all 10
source origins, 130 canonical aports entries, and nine upstream distfiles.
These are acquisition and candidate-review records, not a committed source
archive, source offer, delivery approval, or redistribution grant.
`LICENSE-REVIEW.json` pins 78 unreviewed candidate evidence files across all
10 source origins; it is an engineering review index, not legal approval.
`LICENSE-REVIEW-RESULTS.json` records the engineering review of all 78 pinned
candidates. Two source origins have no remaining indexed review items; eight
still have package-specific open items. `LICENSE-NOTICE-CANDIDATES.json`
indexes an external candidate bundle for those eight origins: 13 pinned remote
license/attribution payloads, 47 supplemental aports files, and the existing
78 reviewed evidence files. `LICENSE-NOTICE-REVIEW-RESULTS.json` binds the
engineering review to the exact 138-file payload tree. Seven origins have no
remaining candidate-material engineering items; only `alpine-keys` remains
open because the upstream package lacks an MIT grant and copyright notice.
Legal and redistribution approval remain open.
`REBUILD-ENVIRONMENT-REVIEW.json` identifies the historical builder while
recording that its exact release environment and published-archive rebuild
cannot be verified. It separately records a schema-v4 successor that produced
one byte-identical archive across two independent invocations and four total
builds, even though the captured host-tool bytes differed. This is same-host
successor reproducibility evidence, not proof for the pinned release archive,
cross-host reproducibility, or permission to replace or distribute it.
`SOURCE-DELIVERY-INVENTORY.json` indexes five required delivery units; none is
committed as an approved materialized source delivery. The unified external
candidate materializer is ready, but its output remains unapproved and
uncommitted.

固定 `alpine-baselayout` aports snapshot 的 16 个 canonical entries 已逐项
检查：15 个普通文件，以及 1 个指向 `alpine-baselayout.post-install` 的
`alpine-baselayout.post-upgrade` 符号链接。8,053 字节
`APKBUILD`（SHA-256
`80af34ff14881421241beca05d78b9b85fabfcf77899f078036283a961fd4870`）
保存包的 `GPL-2.0-only` 声明、贡献者和维护者；快照中其余 Alpine 配置与安装脚本
没有额外内联版权或 notice。唯一的外部内容是 Debian netbase 6.4 的
`protocols` 与 `services`，固定源码分别为 3,144 和 12,813 字节；外置候选包中的
1,234 字节 `netbase-6.4-copyright`（SHA-256
`795b66147ea5ad692991caa7008ece551fb0fa88b9c53656223bd1518dc58ab2`）
保存其 Peter Tobias、Anthony Towns 与 Marco d'Itri 版权归属和 GPL-2 条款。
结合固定 GPL-2.0 文本，这覆盖了已识别的包级声明、贡献者/维护者与外部文件
attribution，因此在候选材料工程层关闭
`identify-package-specific-copyright-and-notice`。这不判定 GPL 对产品分发的
法律要求，也不解除法律、对应源码或发行门禁。

All 16 canonical entries in the pinned `alpine-baselayout` aports snapshot
were inspected: 15 regular files and the `alpine-baselayout.post-upgrade`
symlink to `alpine-baselayout.post-install`. The 8,053-byte `APKBUILD` with
SHA-256
`80af34ff14881421241beca05d78b9b85fabfcf77899f078036283a961fd4870`
preserves the package's `GPL-2.0-only` declaration, contributor, and
maintainer; the remaining Alpine configuration and install scripts contain no
additional inline copyright or notice. The only external inputs are Debian
netbase 6.4 `protocols` and `services`, fixed at 3,144 and 12,813 bytes. The
external candidate bundle's 1,234-byte `netbase-6.4-copyright`, with SHA-256
`795b66147ea5ad692991caa7008ece551fb0fa88b9c53656223bd1518dc58ab2`,
preserves the Peter Tobias, Anthony Towns, and Marco d'Itri attribution and
GPL-2 terms. Together with the pinned GPL-2.0 text, this covers the identified
package declaration, contributor/maintainer, and external-file attribution,
closing `identify-package-specific-copyright-and-notice` at the
candidate-material engineering level. It does not determine GPL obligations
for product distribution or open any legal, corresponding-source, or release
gate.

`alpine-keys` 的 MIT 声明现同时绑定当前固定 aports `APKBUILD` 与上游不可变提交
`7f1f035cf4f7bbea5cf7b65f9bbedc311d735596`：该提交由包维护者 Natanael
Copa 将 `license` 从 `GPL` 改为 `MIT`。外置候选包保存这份 772 字节、
SHA-256 `a939e8baa52febea02d5bcfcc306822827eac3fd979a637c7723c84af3487e3e`
的原始补丁，用于增强许可证声明的工程 provenance。该补丁没有提供包本身的
MIT grant；固定 SPDX MIT 文本也只是参考。固定 aports tree 的 17 个公钥
payload 仍没有明确的包级版权声明，因此 license-text coverage 保持
reference-only，
`collect-mit-license-grant-and-copyright-notice` 保持未决，attribution coverage
仍为 partial，法律与再分发门禁不变。

The `alpine-keys` MIT declaration is now bound to both the current pinned
aports `APKBUILD` and immutable upstream commit
`7f1f035cf4f7bbea5cf7b65f9bbedc311d735596`, where package maintainer
Natanael Copa changed `license` from `GPL` to `MIT`. The external candidate
bundle preserves the raw 772-byte patch with SHA-256
`a939e8baa52febea02d5bcfcc306822827eac3fd979a637c7723c84af3487e3e`
to strengthen engineering provenance for the declaration. The patch does not
provide the package's own MIT grant, and the pinned SPDX MIT text remains only
a reference. The 17 public-key payloads in the pinned aports tree still have
no explicit package-level copyright notice, so license-text coverage remains
reference-only,
`collect-mit-license-grant-and-copyright-notice` remains open, attribution
coverage remains partial, and the legal and redistribution gates do not
change.

固定 aports 提交 `d1b6f274f29076967826e0ecf6ebcaa5d360272f` 的
`busyboxconfig` 为 31,529 字节，SHA-256
`18d78e185ff0cccd6ccd09f4f78c5780175d78214e16acd1390e4ee85c74346e`；
其中精确启用了 `CONFIG_BZIP2=y`、`CONFIG_BZIP2_SMALL=8` 和
`CONFIG_FEATURE_BZIP2_DECOMPRESS=y`，也启用了 `CONFIG_ASH=y`、
`CONFIG_FEATURE_SH_MATH=y`、`CONFIG_FEATURE_SH_MATH_64=y` 和
`CONFIG_ENV=y`、`CONFIG_ECHO=y`、`CONFIG_FEATURE_FANCY_ECHO=y`、
`CONFIG_LOGGER=y`、`CONFIG_CAL=y`、`CONFIG_PING=y`、`CONFIG_PING6=y`、
`CONFIG_FEATURE_FANCY_PING=y`、`CONFIG_TRACEROUTE=y`、
`CONFIG_TRACEROUTE6=y`、`CONFIG_FEATURE_TRACEROUTE_VERBOSE=y` 和
`CONFIG_FEATURE_TRACEROUTE_USE_ICMP=y`，以及 `CONFIG_DESKTOP=y`、
`CONFIG_OD=y`、`CONFIG_HEXDUMP=y`、`CONFIG_HD=y`、`CONFIG_EXPAND=y`、
`CONFIG_UNEXPAND=y`、`CONFIG_FOLD=y`、`CONFIG_CUT=y`、`CONFIG_SORT=y` 和
`CONFIG_UNIQ=y`；BusyBox
`shell/Kbuild.src` 在该配置下把 `math.o` 链入构建，`coreutils/env.c` 与
`coreutils/echo.c` 则分别通过 `lib-$(CONFIG_ENV) += env.o` 和
`lib-$(CONFIG_ECHO) += echo.o` 链入，`sysklogd/logger.c` 通过
`lib-$(CONFIG_LOGGER) += syslogd_and_logger.o` 链入，`util-linux/cal.c`
通过 `lib-$(CONFIG_CAL) += cal.o` 链入，`networking/ping.c` 则同时通过
`lib-$(CONFIG_PING) += ping.o` 与 `lib-$(CONFIG_PING6) += ping.o`
链入，`networking/traceroute.c` 同时通过
`lib-$(CONFIG_TRACEROUTE) += traceroute.o` 与
`lib-$(CONFIG_TRACEROUTE6) += traceroute.o`
链入；`coreutils/od.c` 通过 `lib-$(CONFIG_OD) += od.o` 链入，并在
`ENABLE_DESKTOP` 分支直接包含 `coreutils/od_bloaty.c`；
`util-linux/hexdump.c` 通过 `CONFIG_HEXDUMP` 与 `CONFIG_HD` 两条规则链入，
并调用由 `libbb/Kbuild.src` 的 `lib-y += dump.o` 提供的 `libbb/dump.c`；
`coreutils/expand.c` 同时通过 `lib-$(CONFIG_EXPAND) += expand.o` 与
`lib-$(CONFIG_UNEXPAND) += expand.o` 链入，`coreutils/fold.c` 通过
`lib-$(CONFIG_FOLD) += fold.o` 链入；`coreutils/cut.c`、
`coreutils/sort.c` 与 `coreutils/uniq.c` 分别通过
`lib-$(CONFIG_CUT) += cut.o`、`lib-$(CONFIG_SORT) += sort.o` 与
`lib-$(CONFIG_UNIQ) += uniq.o` 链入。
外置候选树现同时绑定该
配置与固定 BusyBox
1.36.1 源包中的 1,999 字节
`archival/libarchive/bz/LICENSE`（SHA-256
`b5a136ed67798e51fe2e0ca0b2a21cb01b904ff0c9f7d563a6292e276607e58f`），
从而在工程层关闭
`confirm-enabled-bzip2-license-and-attribution-coverage`；同时绑定 26,578 字节
`shell/math.c`（SHA-256
`8f2d57454d233b67662047cd3411c77ecde7e428ef1f6652d66f177b1d06e2f3`），
其中保留完整 MIT 与 BSD-3-Clause 版权及许可通知，从而在工程层关闭
`confirm-enabled-ash-math-license-and-attribution-coverage`；同时绑定 4,753 字节
`coreutils/env.c`（SHA-256
`730d258bcbeeef301fc00611d0e325958f3f378576af54c524f9be662b0ac757`），
其中保留完整 BSD 版权及许可通知。固定 RootFS 中 `/usr/bin/env` 的目标为
`/bin/busybox`，因此在工程层关闭
`confirm-enabled-env-license-and-attribution-coverage`；同时绑定 9,960 字节
`coreutils/echo.c`（SHA-256
`fcdd9f96dc44bc1b813d478725911054948da20e4d929282b35722c28924577c`），
其中保留完整 Berkeley BSD 版权及许可通知。固定 RootFS 中 `/bin/echo` 的目标为
`/bin/busybox`，因此在工程层关闭
`confirm-enabled-echo-license-and-attribution-coverage`；同时绑定 5,529 字节
`sysklogd/logger.c`（SHA-256
`77d22f4c54824cd8bc8ede513693d9f4eb6977302908daac3797f3ee4573e611`），
其中为 `decode` 与 `pencode` 保留完整 Berkeley BSD 版权及许可通知。固定
RootFS 中 `/usr/bin/logger` 的目标为 `/bin/busybox`，因此在工程层关闭
`confirm-enabled-logger-license-and-attribution-coverage`；同时绑定 10,951 字节
`util-linux/cal.c`（SHA-256
`39798fa68229dcb25817d906ac1990cc147fd84065918a1404b56263d7a6e311`），
其中保留完整 Berkeley BSD-3-Clause 版权及许可通知。固定 RootFS 中
`/usr/bin/cal` 的目标为 `/bin/busybox`，因此在工程层关闭
`confirm-enabled-cal-license-and-attribution-coverage`；同时绑定 31,080 字节
`networking/ping.c`（SHA-256
`f5500d03eb8c681589cd99a861ce57bec208bfdded726b5529c61967e738a205`），
其中保留 Berkeley 版权、再分发条件与免责声明，并明确记录 advertising clause
已依据 1999 年许可变更移除。固定 aports 的
`0016-ping-make-ping-work-without-root-privileges.patch` 也已包含在同一外置
payload 树中；它只修改 socket/runtime 代码，不触及文件头或文件尾的许可通知。
固定 RootFS 主树与 guest 模板树中的 `/bin/ping`
和 `/bin/ping6` 均指向 `/bin/busybox`，因此在工程层关闭
`confirm-enabled-ping-and-ping6-license-and-attribution-coverage`；同时绑定
40,524 字节 `networking/traceroute.c`（SHA-256
`c75965e8ad6670e92ed1c4c116141a51cb78d77e3e47286e4527514bf8b1c229`）。
该文件保留完整的原始 BSD/Lawrence Berkeley Laboratory 版权、源码和二进制
再分发条件、advertising acknowledgement、名称使用限制及免责声明。固定 aports
补丁集没有修改 `networking/traceroute.c`；固定 RootFS 主树与 guest 模板树中的
`/usr/bin/traceroute` 和 `/usr/bin/traceroute6` 均指向 `/bin/busybox`，因此在
工程层关闭
`confirm-enabled-traceroute-and-traceroute6-license-and-attribution-coverage`。
这只是证据完备性结论，不判断 advertising 条款与产品发行方案的法律兼容性。
同时绑定 6,634 字节 `coreutils/od.c`（SHA-256
`8536f85598a87c49db70a583d9c40004719e64b4939e1d58bcbe30e1e8c5417a`）、
37,473 字节 `coreutils/od_bloaty.c`（SHA-256
`eb4ae669c359554eac9dcbac2f7625fb5413b34a76ded366a1ec13e47a729b62`）、
4,392 字节 `util-linux/hexdump.c`（SHA-256
`97e49fc1c02560fd65443a7eafbcfbeab44267f3146e0efa1738ae902d69de84`）和
22,017 字节 `libbb/dump.c`（SHA-256
`a1c705a48bd6eb43b4cb9cfb74d61f47f8500b601ebd9d3502906093f7c8ddfe`）。
`od.c` 与 `dump.c` 保留完整 Regents BSD-3-Clause 条款，
`od_bloaty.c` 保留 FSF 版权、GPLv2-or-later 声明与免责声明，
`hexdump.c` 保留 Regents attribution 和 GPLv2-or-later 声明。固定 aports
补丁集没有修改这四个文件；固定 RootFS 主树与 guest 模板树中的
`/usr/bin/od`、`/usr/bin/hexdump` 和 `/usr/bin/hd` 均指向
`/bin/busybox`，因此在工程层关闭
`confirm-enabled-od-hexdump-and-hd-license-and-attribution-coverage`。
这只确认精确源码与 notice 证据完整，不判断 GPL 版本选择、组合或发行方案的
法律兼容性。
同时绑定 6,393 字节 `coreutils/expand.c`（SHA-256
`66296875f04016bba0721d4fa80393317ffca014e4b4722ed8e7e7fb1c882802`）与
5,018 字节 `coreutils/fold.c`（SHA-256
`db291cf01ee9a90244607c88a5d88ddf7d2600237eca6f2d7a6894815928cdef`）。
`expand.c` 保留 FSF 版权、GPLv2-or-later 声明、David MacKenzie attribution
与 Tito Ragusa 的 BusyBox 改写署名；`fold.c` 保留 FSF 版权、
GPLv2-or-later 声明、David MacKenzie attribution 与 Glenn McGrath 的 BusyBox
改写署名。固定 aports 补丁集没有修改这两个文件；固定 RootFS 主树与 guest
模板树中的 `/usr/bin/expand`、`/usr/bin/unexpand` 和 `/usr/bin/fold` 均指向
`/bin/busybox`，因此在工程层关闭
`confirm-enabled-expand-unexpand-and-fold-license-and-attribution-coverage`。
这只确认精确源码与声明/署名证据完整，不判断 GPL 版本选择、组合或发行方案的
法律兼容性。
同时绑定 9,783 字节 `coreutils/cut.c`（SHA-256
`bfae86e174a6c51c7fbfee90fd8a5e2901286940378e576e141690bfa55dcc1a`）、
18,817 字节 `coreutils/sort.c`（SHA-256
`cb92adb0e734b63ae5312a157a9a735cab44bbda4cfd01c52d556be22eca5ff0`）与
3,681 字节 `coreutils/uniq.c`（SHA-256
`09c15b3e70e0b5ac2e65b42b1e556f9b25199b846b2ac75dc730d18650d14f7d`）。
三份源码均保留 GPLv2-or-later 声明和原作者署名：`cut.c` 署名 Lineo 与
Mark Whitley，`sort.c` 署名 Rob Landley，`uniq.c` 署名 Manuel Novoa III。
固定 aports 补丁集没有修改这三个文件；固定 RootFS 主树与 guest 模板树中的
`/usr/bin/cut`、`/usr/bin/sort` 和 `/usr/bin/uniq` 均指向
`/bin/busybox`，因此在工程层关闭
`confirm-enabled-cut-sort-and-uniq-license-and-attribution-coverage`。
这只确认精确源码与声明/署名证据完整，不判断 GPL 版本选择、组合或发行方案的
法律兼容性。
为收口其余已启用组件，工程审查从固定 `busybox-1.36.1.tar.bz2` 开始，按
`APKBUILD` 顺序应用全部 33 个固定 aports 补丁，再加载固定 `busyboxconfig`。
补丁后 `oldconfig` 与固定配置只差生成时间戳；生成的 dry-run 构建图包含 487
个编译单元，递归解析本地 `#include` 后得到 562 个源码/头文件闭包。审查从该
闭包中选出仍含独立 BSD/MIT/public-domain、LZO/XZ provenance、原作者版权或
再分发条款的 41 份文件，并把各自的原始 distfile member、大小和 SHA-256
加入候选。新增材料覆盖 gzip/unzip 的公共领域来源、LZO、XZ Embedded、
`dos2unix`/`sync`/`test`/`tr`、shadow-derived `libbb` 代码、密码散列来源、
进度条、`uidgid_get`、`nc_bloaty`、`ash`/shell common、OSF fdisk 与 `setsid`
等实际构建闭包。

固定补丁仅修改其中的 `libbb/hash_md5_sha.c` 和 `shell/ash.c`；相应 5 份补丁
已经作为 supplemental aports payload 单独固定，修改 hunks 不删除或改写本轮
依赖的 notice。Alpine 的 `0009-properly-fix-wget-https-support.patch` 使固定
动态配置继续保持 `CONFIG_TLS` 未启用，因此未把仅由未打补丁上游默认值引入的
TLS 源码误计入闭包。BusyBox 现有证据由 19 份增至 60 份，license-text 与
attribution coverage 均在候选材料工程层记为 complete，并关闭
`review-other-bundled-third-party-license-and-attribution-coverage`。这仍不是
法律兼容性、对应源码完整性或再分发批准，相关发行门禁保持关闭。

The `busyboxconfig` at pinned aports commit
`d1b6f274f29076967826e0ecf6ebcaa5d360272f` is 31,529 bytes with SHA-256
`18d78e185ff0cccd6ccd09f4f78c5780175d78214e16acd1390e4ee85c74346e`.
It explicitly enables `CONFIG_BZIP2=y`, `CONFIG_BZIP2_SMALL=8`,
`CONFIG_FEATURE_BZIP2_DECOMPRESS=y`, `CONFIG_ASH=y`,
`CONFIG_FEATURE_SH_MATH=y`, `CONFIG_FEATURE_SH_MATH_64=y`, `CONFIG_ENV=y`,
`CONFIG_ECHO=y`, `CONFIG_FEATURE_FANCY_ECHO=y`, `CONFIG_LOGGER=y`,
`CONFIG_CAL=y`, `CONFIG_PING=y`, `CONFIG_PING6=y`,
`CONFIG_FEATURE_FANCY_PING=y`, `CONFIG_TRACEROUTE=y`,
`CONFIG_TRACEROUTE6=y`, `CONFIG_FEATURE_TRACEROUTE_VERBOSE=y`, and
`CONFIG_FEATURE_TRACEROUTE_USE_ICMP=y`, plus `CONFIG_DESKTOP=y`,
`CONFIG_OD=y`, `CONFIG_HEXDUMP=y`, `CONFIG_HD=y`, `CONFIG_EXPAND=y`,
`CONFIG_UNEXPAND=y`, `CONFIG_FOLD=y`, `CONFIG_CUT=y`, `CONFIG_SORT=y`, and
`CONFIG_UNIQ=y`; BusyBox
`shell/Kbuild.src` links `math.o` under that configuration, while
`coreutils/env.c` and `coreutils/echo.c` are linked by
`lib-$(CONFIG_ENV) += env.o` and `lib-$(CONFIG_ECHO) += echo.o`,
respectively, `sysklogd/logger.c` is linked through
`lib-$(CONFIG_LOGGER) += syslogd_and_logger.o`, and `util-linux/cal.c` is
linked through `lib-$(CONFIG_CAL) += cal.o`; `networking/ping.c` is linked
through both `lib-$(CONFIG_PING) += ping.o` and
`lib-$(CONFIG_PING6) += ping.o`; `networking/traceroute.c` is linked through
both `lib-$(CONFIG_TRACEROUTE) += traceroute.o` and
`lib-$(CONFIG_TRACEROUTE6) += traceroute.o`; `coreutils/od.c` is linked by
`lib-$(CONFIG_OD) += od.o` and directly includes `coreutils/od_bloaty.c` under
`ENABLE_DESKTOP`; `util-linux/hexdump.c` is linked by both `CONFIG_HEXDUMP`
and `CONFIG_HD` and calls the `libbb/dump.c` implementation supplied by
`lib-y += dump.o` in `libbb/Kbuild.src`; `coreutils/expand.c` is linked by
both `lib-$(CONFIG_EXPAND) += expand.o` and
`lib-$(CONFIG_UNEXPAND) += expand.o`, while `coreutils/fold.c` is linked by
`lib-$(CONFIG_FOLD) += fold.o`; `coreutils/cut.c`, `coreutils/sort.c`, and
`coreutils/uniq.c` are linked by `lib-$(CONFIG_CUT) += cut.o`,
`lib-$(CONFIG_SORT) += sort.o`, and `lib-$(CONFIG_UNIQ) += uniq.o`,
respectively. The external candidate tree
now binds that configuration to the
1,999-byte
`archival/libarchive/bz/LICENSE` in the pinned BusyBox 1.36.1 source archive,
whose SHA-256 is
`b5a136ed67798e51fe2e0ca0b2a21cb01b904ff0c9f7d563a6292e276607e58f`.
This closes
`confirm-enabled-bzip2-license-and-attribution-coverage` at the engineering
level. It also binds the 26,578-byte `shell/math.c`, whose SHA-256 is
`8f2d57454d233b67662047cd3411c77ecde7e428ef1f6652d66f177b1d06e2f3`;
that file retains complete MIT and BSD-3-Clause copyright and license notices,
closing `confirm-enabled-ash-math-license-and-attribution-coverage` at the
engineering level. It also binds the 4,753-byte `coreutils/env.c`, whose
SHA-256 is
`730d258bcbeeef301fc00611d0e325958f3f378576af54c524f9be662b0ac757`;
the file retains its complete BSD copyright and license notice. The pinned
RootFS maps `/usr/bin/env` to `/bin/busybox`, closing
`confirm-enabled-env-license-and-attribution-coverage` at the engineering
level. It also binds the 9,960-byte `coreutils/echo.c`, whose SHA-256 is
`fcdd9f96dc44bc1b813d478725911054948da20e4d929282b35722c28924577c`;
the file retains its complete Berkeley BSD copyright and license notice. The
pinned RootFS maps `/bin/echo` to `/bin/busybox`, closing
`confirm-enabled-echo-license-and-attribution-coverage` at the engineering
level. It also binds the 5,529-byte `sysklogd/logger.c`, whose SHA-256 is
`77d22f4c54824cd8bc8ede513693d9f4eb6977302908daac3797f3ee4573e611`;
the file retains the complete Berkeley BSD copyright and license notice for
`decode` and `pencode`. The pinned RootFS maps `/usr/bin/logger` to
`/bin/busybox`, closing
`confirm-enabled-logger-license-and-attribution-coverage` at the engineering
level. It also binds the 10,951-byte `util-linux/cal.c`, whose SHA-256 is
`39798fa68229dcb25817d906ac1990cc147fd84065918a1404b56263d7a6e311`;
the file retains its complete Berkeley BSD-3-Clause copyright and license
notice. The pinned RootFS maps `/usr/bin/cal` to `/bin/busybox`, closing
`confirm-enabled-cal-license-and-attribution-coverage` at the engineering
level. It also binds the 31,080-byte `networking/ping.c`, whose SHA-256 is
`f5500d03eb8c681589cd99a861ce57bec208bfdded726b5529c61967e738a205`;
the file retains Berkeley copyright, redistribution conditions, and
disclaimer while explicitly recording removal of the advertising clause
under the 1999 licensing change. The pinned aports
`0016-ping-make-ping-work-without-root-privileges.patch` is also included in
the same external payload tree; it changes socket/runtime code without
touching the header or trailing license notice. Both the main and
guest-template RootFS trees
map `/bin/ping` and `/bin/ping6` to `/bin/busybox`, closing
`confirm-enabled-ping-and-ping6-license-and-attribution-coverage` at the engineering
level. It also binds the 40,524-byte `networking/traceroute.c`, whose SHA-256
is `c75965e8ad6670e92ed1c4c116141a51cb78d77e3e47286e4527514bf8b1c229`.
The file retains its complete original BSD/Lawrence Berkeley Laboratory
copyright, source and binary redistribution conditions, advertising
acknowledgement, name-use restriction, and disclaimer. The pinned aports patch
set does not modify `networking/traceroute.c`; both the main and guest-template
RootFS trees map `/usr/bin/traceroute` and `/usr/bin/traceroute6` to
`/bin/busybox`, closing
`confirm-enabled-traceroute-and-traceroute6-license-and-attribution-coverage`
at the engineering level. This is an evidence-completeness conclusion, not a
legal compatibility determination for the advertising condition or product
distribution plan. It also binds the 6,634-byte `coreutils/od.c` with SHA-256
`8536f85598a87c49db70a583d9c40004719e64b4939e1d58bcbe30e1e8c5417a`,
the 37,473-byte `coreutils/od_bloaty.c` with SHA-256
`eb4ae669c359554eac9dcbac2f7625fb5413b34a76ded366a1ec13e47a729b62`,
the 4,392-byte `util-linux/hexdump.c` with SHA-256
`97e49fc1c02560fd65443a7eafbcfbeab44267f3146e0efa1738ae902d69de84`,
and the 22,017-byte `libbb/dump.c` with SHA-256
`a1c705a48bd6eb43b4cb9cfb74d61f47f8500b601ebd9d3502906093f7c8ddfe`.
`od.c` and `dump.c` retain complete Regents BSD-3-Clause terms;
`od_bloaty.c` retains the FSF copyright, GPLv2-or-later declaration, and
disclaimer; `hexdump.c` retains the Regents attribution and GPLv2-or-later
declaration. The pinned aports patch set does not modify these four files, and
both the main and guest-template RootFS trees map `/usr/bin/od`,
`/usr/bin/hexdump`, and `/usr/bin/hd` to `/bin/busybox`, closing
`confirm-enabled-od-hexdump-and-hd-license-and-attribution-coverage` at the
engineering level. This confirms exact source and notice evidence only; it
does not determine the legal compatibility of GPL version selection,
combination, or the distribution plan. It also binds the 6,393-byte
`coreutils/expand.c` with SHA-256
`66296875f04016bba0721d4fa80393317ffca014e4b4722ed8e7e7fb1c882802` and
the 5,018-byte `coreutils/fold.c` with SHA-256
`db291cf01ee9a90244607c88a5d88ddf7d2600237eca6f2d7a6894815928cdef`.
`expand.c` retains the FSF copyright, GPLv2-or-later declaration, David
MacKenzie attribution, and Tito Ragusa's BusyBox port attribution; `fold.c`
retains the FSF copyright, GPLv2-or-later declaration, David MacKenzie
attribution, and Glenn McGrath's BusyBox port attribution. The pinned aports
patch set does not modify either file, and both the main and guest-template
RootFS trees map `/usr/bin/expand`, `/usr/bin/unexpand`, and `/usr/bin/fold`
to `/bin/busybox`, closing
`confirm-enabled-expand-unexpand-and-fold-license-and-attribution-coverage`
at the engineering level. This confirms exact source, declaration, and
attribution evidence only; it does not determine the legal compatibility of
GPL version selection, combination, or the distribution plan. It also binds
the 9,783-byte `coreutils/cut.c` with SHA-256
`bfae86e174a6c51c7fbfee90fd8a5e2901286940378e576e141690bfa55dcc1a`,
the 18,817-byte `coreutils/sort.c` with SHA-256
`cb92adb0e734b63ae5312a157a9a735cab44bbda4cfd01c52d556be22eca5ff0`,
and the 3,681-byte `coreutils/uniq.c` with SHA-256
`09c15b3e70e0b5ac2e65b42b1e556f9b25199b846b2ac75dc730d18650d14f7d`.
All three retain GPLv2-or-later declarations and original attribution:
`cut.c` credits Lineo and Mark Whitley, `sort.c` credits Rob Landley, and
`uniq.c` credits Manuel Novoa III. The pinned aports patch set does not modify
these files, and both the main and guest-template RootFS trees map
`/usr/bin/cut`, `/usr/bin/sort`, and `/usr/bin/uniq` to `/bin/busybox`,
closing
`confirm-enabled-cut-sort-and-uniq-license-and-attribution-coverage` at the
engineering level. This confirms exact source, declaration, and attribution
evidence only; it does not determine the legal compatibility of GPL version
selection, combination, or the distribution plan. To close the remaining
enabled-component review, the engineering audit starts from the pinned
`busybox-1.36.1.tar.bz2`, applies all 33 pinned aports patches in `APKBUILD`
order, and loads the pinned `busyboxconfig`. The post-patch `oldconfig` differs
from the pinned configuration only by its generated timestamp. The resulting
dry-run build graph contains 487 compilation units and a 562-file recursive
local-include closure. From that closure, the audit selects 41 files that
retain independent BSD/MIT/public-domain terms, LZO/XZ provenance, original
copyright, or redistribution notices, and pins each original distfile member,
byte count, and SHA-256. The added evidence covers public-domain gzip/unzip
origins, LZO, XZ Embedded, `dos2unix`/`sync`/`test`/`tr`, shadow-derived
`libbb` code, password-hash origins, the progress meter, `uidgid_get`,
`nc_bloaty`, `ash`/shell common, OSF fdisk, and `setsid`.

Only `libbb/hash_md5_sha.c` and `shell/ash.c` among those files are modified by
the pinned patch set. The five relevant patches are already pinned as
supplemental aports payloads, and their hunks do not remove or rewrite the
notices used here. Alpine patch
`0009-properly-fix-wget-https-support.patch` keeps `CONFIG_TLS` disabled in
the fixed dynamic configuration, so TLS sources introduced only by the
unpatched upstream default are excluded. BusyBox existing evidence increases
from 19 to 60 files; license-text and attribution coverage are complete at the
candidate-material engineering level, closing
`review-other-bundled-third-party-license-and-attribution-coverage`. This is
still not a legal-compatibility conclusion, corresponding-source completeness
determination, or redistribution approval; all release gates remain closed.

固定 musl 源包的 6,204 字节 `COPYRIGHT`（SHA-256
`f9bc4423732350eb0b3f7ed7e91d530298476f8fec0c6c427a1c04ade22655af`）
包含完整 MIT grant、作者列表，并逐项覆盖 TRE regex、math/complex、AArch64
memcpy/memset、DES/blowfish crypt、smoothsort 与各架构 port 的第三方来源和
许可例外。固定 RootFS 的 `musl-utils` 只安装 `getconf`、`getent`、`iconv`、
`ldconfig` 与由 `APKBUILD` 生成的 `ldd`。候选证据中的 11,614 字节
`getconf.c`、11,656 字节 `getent.c` 和 2,577 字节 `iconv.c` 分别保存完整
NetBSD BSD-2-Clause notices 与 Rich Felker GPL-2.0-or-later 头；
393 字节 `ldconfig` 和生成的 `ldd` 没有额外内联 notice。三个固定 aports
patch 也都已逐项复核。由此，已安装 musl 与 musl-utils 的第三方/辅助工具 notice
集合在候选材料工程层完整，关闭
`confirm-third-party-musl-files-and-aports-helper-notice-coverage`；这不判定
MIT/BSD/GPL 组合、对应源码或产品分发义务。

The pinned musl source's 6,204-byte `COPYRIGHT`, with SHA-256
`f9bc4423732350eb0b3f7ed7e91d530298476f8fec0c6c427a1c04ade22655af`,
contains the complete MIT grant and author list, and enumerates the third-party
origins and license exceptions for TRE regex, math/complex, AArch64
memcpy/memset, DES/blowfish crypt, smoothsort, and architecture ports. The
pinned RootFS `musl-utils` package installs only `getconf`, `getent`, `iconv`,
`ldconfig`, and the `ldd` generated by `APKBUILD`. The indexed 11,614-byte
`getconf.c`, 11,656-byte `getent.c`, and 2,577-byte `iconv.c` preserve the
complete NetBSD BSD-2-Clause notices and Rich Felker GPL-2.0-or-later header,
respectively; the 393-byte `ldconfig` and generated `ldd` contain no additional
inline notice. All three pinned aports patches were also reviewed. The
third-party/helper notice set for the installed musl and musl-utils packages is
therefore complete at the candidate-material engineering level, closing
`confirm-third-party-musl-files-and-aports-helper-notice-coverage`. This does
not decide MIT/BSD/GPL combination, corresponding-source, or product
distribution obligations.

`ca-certificates-20230506.tar.bz2` 中的 `mk-ca-bundle.pl`（20,863 字节，
SHA-256 `9d828d97053868907ce6229d132132f0f26772393405dadd037b6f85a5c5b219`）
与 curl 提交 `3fdc4bdb5b00835a1d04cf160cd61fe7f8feb477` 的
`lib/mk-ca-bundle.pl` 字节一致。外置候选包同时固定该脚本和同一提交的
1,088 字节 `COPYING`；后者 SHA-256 为
`db3c4a3b3695a0f317a0c5176acd2f656d18abc45b3ee78e50935a78eb1e132e`，
补齐脚本头部所引用的精确 curl 授权，而不是把通用 SPDX MIT 文本当作替代。
因此 `confirm-mit-script-notices-relevant-to-shipped-bundle` 的既有工程结论有了
精确 provenance。固定源包的 1,324,018 字节 `certdata.txt`（SHA-256
`c47475103fb05bb562bbadff0d1e72346b03236154e1448a6ca191b740f83507`）
保存 Mozilla MPL-2.0 头和完整 trust objects；按固定 `Makefile`/`APKBUILD`
拆分并排序拼接后生成 214,509 字节 PEM，SHA-256
`824cefcee69de918c76b7b92776f304c3a4b7f6281539118bc1d41a9dd8476d9`，
与 RootFS 主树及 guest template 中安装的
`/etc/ssl/certs/ca-certificates.crt` 逐字节一致。`ca-certificates-bundle`
APK 记录只有该文件及其 symlink，没有发布生成器或其他证书源文件。结合固定
MPL-2.0 全文，这在候选材料工程层关闭
`confirm-certificate-attribution-and-trust-store-requirements`，但不判定各 CA
证书、Mozilla policy 或产品信任选择的法律/安全适用性；法律与再分发门禁不变。

The `mk-ca-bundle.pl` in `ca-certificates-20230506.tar.bz2` is 20,863 bytes
with SHA-256
`9d828d97053868907ce6229d132132f0f26772393405dadd037b6f85a5c5b219`
and is byte-identical to `lib/mk-ca-bundle.pl` at curl commit
`3fdc4bdb5b00835a1d04cf160cd61fe7f8feb477`. The external candidate bundle
pins both that script and the 1,088-byte `COPYING` from the same commit; the
license has SHA-256
`db3c4a3b3695a0f317a0c5176acd2f656d18abc45b3ee78e50935a78eb1e132e`.
This supplies the exact curl grant referenced by the script header instead
of treating a generic SPDX MIT text as a substitute. The existing engineering
disposition of
`confirm-mit-script-notices-relevant-to-shipped-bundle` is therefore bound to
exact provenance. The pinned source's 1,324,018-byte `certdata.txt`, with
SHA-256
`c47475103fb05bb562bbadff0d1e72346b03236154e1448a6ca191b740f83507`,
preserves the Mozilla MPL-2.0 header and complete trust objects. Splitting and
sorted concatenation through the pinned `Makefile`/`APKBUILD` produces a
214,509-byte PEM with SHA-256
`824cefcee69de918c76b7b92776f304c3a4b7f6281539118bc1d41a9dd8476d9`,
byte-identical to `/etc/ssl/certs/ca-certificates.crt` in both the RootFS main
tree and guest template. The `ca-certificates-bundle` APK record contains only
that file and its symlinks; it does not ship the generator or another
certificate source. Together with the pinned complete MPL-2.0 text, this
closes `confirm-certificate-attribution-and-trust-store-requirements` at the
candidate-material engineering level. It does not decide the legal or
security suitability of individual CA certificates, Mozilla policy, or the
product trust choice; legal and redistribution gates remain closed.

OpenSSL 的工程结论绑定固定 `openssl-3.1.4.tar.gz`：源包根目录没有
`NOTICE` 文件；固定 RootFS 的 APK database 将 guest 路径
`/etc/ssl/misc/CA.pl` 与 `/etc/ssl/misc/tsget.pl` 归属到 inventory 中的
`libcrypto3`。归档内 canonical guest-template 文件分别为 8,062 字节、
SHA-256 `35a85ebe05ac4ee42a0efe544c02ad2c70bf374c4dcd8bf5aaf403b7c1b6cdd8`
和 6,746 字节、SHA-256
`1c303a261c93d09a04dbb5b4167e93553607a8d06e968bd1cf06325933c147bc`。
候选包中的 `LICENSE.txt`、`AUTHORS.md`、`README.md`、`CA.pl.in` 和
`tsget.in` 与固定源包字节一致；两个源码模板的 license/attribution 头部与上述
生成后的安装文件一致，覆盖 OpenSSL Project、OpenTSA Project 及 Eric A.
Young/Tim J. Hudson 版权归属。因此
`confirm-required-apache-notice-and-attribution-material` 已在工程层关闭；
这不表示法律审查或再分发批准。

The OpenSSL engineering conclusion is bound to the pinned
`openssl-3.1.4.tar.gz`: its source root contains no `NOTICE` file. The pinned
RootFS APK database assigns guest paths `/etc/ssl/misc/CA.pl` and
`/etc/ssl/misc/tsget.pl` to the inventoried `libcrypto3` package. Their
canonical guest-template files are 8,062 bytes with SHA-256
`35a85ebe05ac4ee42a0efe544c02ad2c70bf374c4dcd8bf5aaf403b7c1b6cdd8`
and 6,746 bytes with SHA-256
`1c303a261c93d09a04dbb5b4167e93553607a8d06e968bd1cf06325933c147bc`,
respectively. The candidate `LICENSE.txt`, `AUTHORS.md`, `README.md`,
`CA.pl.in`, and `tsget.in` are byte-identical to the pinned source; the two
source-template license/attribution headers match the generated installed
files and cover the OpenSSL Project, OpenTSA Project, and Eric A. Young/Tim J.
Hudson copyright attributions. The
`confirm-required-apache-notice-and-attribution-material` item is therefore
closed at the engineering level only; this is not legal review or
redistribution approval.

## 重新生成 / Regenerate

先把经授权使用的固定 archive 放在仓库外，再运行：

Keep an authorized copy of the pinned archive outside the repository, then run:

```bash
ruby Scripts/generate-rootfs-compliance.rb \
  --archive /absolute/path/outside-the-repository/fs.tar.gz
```

只校验而不改写文件：

Check committed output without rewriting it:

```bash
ruby Scripts/generate-rootfs-compliance.rb \
  --archive /absolute/path/outside-the-repository/fs.tar.gz \
  --check
```

生成器会先验证固定大小和 SHA-256，只读取 archive 中已知的小型元数据成员，不展开
RootFS 到仓库。CI 对同一个固定 release archive 执行 `--check`。

The generator verifies the pinned size and SHA-256 first, reads only known
small metadata members, and does not extract the RootFS into the repository.
CI runs `--check` against the same pinned release archive, verifies the pinned
official SPDX 2.3 schema digest, and validates `SBOM.spdx.json` with
the repository-owned validator and the integrity-locked `ajv@8.20.0`
dependency tree. Node.js/npm are host CI tools for that validation only; they
are not installed in the App or RootFS.

只校验源码获取清单、对应源码审查结果与固定 package/source inventory 是否一致：

Validate the source-acquisition manifest and corresponding-source review
results against the pinned package/source inventory without downloading:

```bash
ruby Scripts/prepare-rootfs-source-bundle.rb --validate-only
```

如审查人员需要本地对应源码候选材料，可生成到一个尚不存在、位于仓库外的绝对路径。脚本会依次
校验 aports archive SHA-512、解包后的规范化目录 SHA-256（包括普通文件权限位）
和所有 upstream distfile SHA-512，并以临时目录完成后原子提升：

To prepare local corresponding-source candidate material, choose a new
absolute directory outside the repository. The script verifies each aports
archive and canonical extracted tree—including regular-file permission
bits—plus every upstream distfile before atomically promoting the result:

```bash
ruby Scripts/prepare-rootfs-source-bundle.rb \
  --output /absolute/new/path/outside-the-repository/rootfs-v0.3.3-corresponding-source-candidate

ruby Scripts/prepare-rootfs-source-bundle.rb \
  --verify /absolute/new/path/outside-the-repository/rootfs-v0.3.3-corresponding-source-candidate
```

网络不可用时，可把另一份候选目录或同布局的只读目录作为下载缓存：

When the network is unavailable, another candidate directory or a
read-only directory with the same cache layout can supply the downloads:

```bash
ruby Scripts/prepare-rootfs-source-bundle.rb \
  --download-cache /absolute/existing/rootfs-v0.3.3-corresponding-source-candidate \
  --output /absolute/new/path/outside-the-repository/rootfs-v0.3.3-corresponding-source-candidate
```

缓存布局为 `downloads/aports/<source-origin>.tar.gz` 与
`distfiles/<source-origin>/<filename>`。缓存只替代网络传输；工具仍拒绝符号链接和
仓库内/重叠路径，限制每个输入大小，核对固定 SHA-512，并重新校验解包后的规范化
aports tree 后才原子提升输出。

The cache layout is `downloads/aports/<source-origin>.tar.gz` and
`distfiles/<source-origin>/<filename>`. It replaces network transport only:
the tool still rejects symlinks and repository-local or overlapping paths,
bounds every input, verifies pinned SHA-512 digests, and revalidates each
canonical extracted aports tree before atomically promoting the output.
The receipt marks cached acquisition explicitly and records cache-relative
paths instead of claiming that an upstream URL was contacted; pinned upstream
origins remain in `SOURCE-ACQUISITION.json`.
Receipt schema v3 requires that explicit acquisition mode and binds
`SOURCE-INVENTORY.json`, `CORRESPONDING-SOURCE-REVIEW-RESULTS.json`, candidate
material status, and every still-closed gate. Legacy v1/v2 source-review
directories can be passed to `--download-cache`, but they are no longer
accepted directly by `--verify`; regenerate a v3 candidate bundle.

`--verify` 同时核对所有普通文件摘要、目录集合和符号链接目标。该输出不会被 App、
Git 或 CI artifact 自动打包或上传。

`--verify` checks every regular-file digest, the directory set, and symbolic
link targets. The output is never automatically bundled into the App,
committed to Git, or uploaded as a CI artifact.

在已有外置对应源码候选目录的基础上，可校验逐包候选清单，或提取到另一个
尚不存在的仓库外目录：

Given that external corresponding-source candidate directory, validate the package-level
candidate index or extract it into another new directory outside the repository:

```bash
ruby Scripts/prepare-rootfs-license-review.rb --validate-only

ruby Scripts/prepare-rootfs-license-review.rb \
  --source-bundle /absolute/rootfs-v0.3.3-corresponding-source-candidate \
  --output /absolute/new/rootfs-v0.3.3-license-review

ruby Scripts/prepare-rootfs-license-review.rb \
  --source-bundle /absolute/rootfs-v0.3.3-corresponding-source-candidate \
  --verify /absolute/rootfs-v0.3.3-license-review

ruby Scripts/rootfs-license-review-results.rb
```

工具只提取 `LICENSE-REVIEW.json` 固定的候选文件，并再次核对大小、SHA-256、
路径全集、无符号链接/特殊节点边界。结果清单证明 78 个候选已完成工程复核；
外置输出仍不是可直接随产品发行的 NOTICE bundle。

The tool extracts only candidates pinned by `LICENSE-REVIEW.json`, then
rechecks byte counts, SHA-256 digests, the exact path set, and the no-symlink/
special-node boundary. The results manifest proves engineering review of all
78 candidates; the external output is still not a product-ready NOTICE bundle.

剩余 8 个 source origin 的材料可继续组装为外置候选包。先校验清单；实际物化
必须同时提供已经通过 `--verify` 的对应源码候选和 license-review 目录，以及
一个尚不存在的仓库外输出路径：

The remaining eight origins can be assembled into an external candidate
bundle. Validate the manifest first. Materialization requires
corresponding-source candidate and license-review directories that already
pass `--verify`, plus a new output path outside the repository:

```bash
ruby Scripts/rootfs-license-notice-candidates.rb
ruby Scripts/rootfs-license-notice-review-results.rb
ruby Scripts/prepare-rootfs-license-notice-bundle.rb --validate-only

ruby Scripts/prepare-rootfs-license-notice-bundle.rb \
  --source-bundle /absolute/rootfs-v0.3.3-corresponding-source-candidate \
  --license-review /absolute/rootfs-v0.3.3-license-review \
  --output /absolute/new/rootfs-v0.3.3-license-notice-candidates

ruby Scripts/prepare-rootfs-license-notice-bundle.rb \
  --source-bundle /absolute/rootfs-v0.3.3-corresponding-source-candidate \
  --license-review /absolute/rootfs-v0.3.3-license-review \
  --verify /absolute/rootfs-v0.3.3-license-notice-candidates

ruby Scripts/rootfs-license-notice-review-results.rb \
  --bundle /absolute/rootfs-v0.3.3-license-notice-candidates
```

统一交付候选工具会先调用上述独立 verifier，再从固定 Git object 为历史/后继
builder 与全部已初始化 submodule 生成按 commit 内容寻址的 deterministic tar；
共享 submodule 只保存一次，大小写不同的 Linux 路径不会在 host 文件系统上覆盖。
工具再加入固定 Alpine 输入、对应源码、license-review evidence、LICENSE/NOTICE
候选、修改披露和合规证据，并生成 receipt、typed tree 与 `SHA256SUMS`：

```bash
ruby Scripts/prepare-rootfs-delivery-candidate.rb --validate-only

ruby Scripts/prepare-rootfs-delivery-candidate.rb \
  --historical-builder /absolute/ish-arm64-pkg-v0.3.3 \
  --successor-builder /absolute/ish-arm64-pkg-successor \
  --alpine-minirootfs /absolute/alpine-minirootfs-3.19.1-aarch64.tar.gz \
  --source-bundle /absolute/rootfs-v0.3.3-corresponding-source-candidate \
  --license-notice-bundle /absolute/rootfs-v0.3.3-license-notice-candidates \
  --license-review-bundle /absolute/rootfs-v0.3.3-license-review \
  --output /absolute/new/rootfs-v0.3.3-delivery-candidate

ruby Scripts/prepare-rootfs-delivery-candidate.rb \
  --verify /absolute/new/rootfs-v0.3.3-delivery-candidate
```

The unified delivery-candidate tool first invokes the independent verifiers,
then generates commit-addressed deterministic tar files for the historical
and successor builders and every initialized submodule from pinned Git
objects. Shared submodules are stored once, and case-distinct Linux paths
never collide on the host filesystem. It adds the pinned Alpine input,
corresponding-source candidate, license-review evidence, LICENSE/NOTICE
candidate, modification disclosure, compliance evidence, a receipt, typed
tree, and `SHA256SUMS`. Independent verification reruns both lower-level
bundle verifiers from the candidate itself, requires all bundled evidence to
match this checkout's committed canonical evidence byte for byte, and rejects
alternate evidence paths. Its receipt keeps source-offer, legal, delivery,
redistribution, and distribution authorization false. The output is not a
public artifact or permission to ship the RootFS.

远端材料由固定 URL、字节数和 SHA-256 约束；可选 `--download-cache` 只读取以
`cacheKey` 命名的本地普通文件并再次校验。输出包含候选 NOTICE、receipt 和
`SHA256SUMS`，但仍是工程审查输入，不是产品 NOTICE、法律意见或再分发批准。

Remote payloads are pinned by URL, byte count, and SHA-256. An optional
`--download-cache` reads only local regular files named by each `cacheKey` and
revalidates them. The output includes a candidate NOTICE, receipt, and
`SHA256SUMS`; it remains engineering-review input, not a product NOTICE, legal
advice, or redistribution approval.

## 未解除的门禁 / Open gates

这些文件不构成完整第三方 LICENSE/NOTICE bundle、经批准的 copyleft
corresponding-source 交付、法律意见或再分发授权。源码获取清单已完整覆盖固定
inventory，10/10 origin 的对应源码候选材料工程复核已完成；78 个许可证候选也都有
工程复核结果；`libc-dev`、`zlib` 已关闭索引项，另外
8 个 source origin 的 138 个新候选 payload 已完成 checksum-bound 工程复核；
`alpine-baselayout`、`apk-tools`、`busybox`、`ca-certificates`、`musl`、
`openssl`、`pax-utils` 的候选材料工程项已关闭；只有 `alpine-keys` 因上游
MIT grant/版权声明缺失仍未决。5 单元修改/源码交付 inventory 已建立，但固定
发布归档的精确重建环境/重建、实际材料化 bundle、源码提供方式、对应源码交付
批准、法律审查、App Store 2.5.2 产品策略和负责人批准仍是发行阻塞项。

These files are not a complete third-party LICENSE/NOTICE bundle, approved
copyleft corresponding-source delivery, legal advice, or redistribution
approval. The acquisition manifest completely covers the pinned inventory,
and candidate source material for all 10 origins has engineering review. All
78 indexed license candidates also have engineering review results. `libc-dev` and
`zlib` have no remaining indexed items. All 138 newly indexed payloads have a
checksum-bound engineering review. `alpine-baselayout`, `apk-tools`, `busybox`,
`ca-certificates`, `musl`, `openssl`, and `pax-utils` have no remaining
candidate-material engineering items; only `alpine-keys` remains open because
its upstream MIT grant and copyright notice are missing. The five-unit
modification/source-delivery inventory is recorded, while the pinned release's
exact environment/rebuild, materialized bundle, source-offer mechanics,
corresponding-source delivery approval, legal review, App Store 2.5.2 product
policy, and authorized approval remain distribution blockers.
