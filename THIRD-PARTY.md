# 数据来源与许可

本项目源码采用 GNU AGPL-3.0，完整条款见根目录 `LICENSE`。分发可执行文件时应一并提供本项目对应源码及数据，包括构建脚本；本地源码即为对应源码。

## 拆分码表与字根字体

`data/decomposition.tsv`、`data/roots.ttf` 来自 [sdcb/wubi86-viewer](https://github.com/sdcb/wubi86-viewer) 的 `data-src/data-wubi-v86.tsv` 和 `data-src/黑体字根.ttf`，获取于 2026-10-29；该仓库采用 AGPL-3.0。文件原样保留。

上游声明拆分资料和字体来自 [hantang/search-wubi](https://github.com/hantang/search-wubi)，原始五笔资源来自 [86wb.ysepan.com](http://86wb.ysepan.com)。拆分码表汇集王码、Rime、极点、UnicodeCJK-WuBi 等资料。上述字体的独立原始许可未在上游单列；目前按上游仓库许可保留使用及来源说明，公开再分发前建议进一步确认原始字体授权。

`data/keyboard.tsv` 原样来自 hantang/search-wubi 的 `docs/wiki/data/roots-table.tsv`，用于显示标准基本字根键盘；获取于同日。

## 五笔词库

`data/wubi86.dict.yaml` 原样来自 [rime/rime-wubi](https://github.com/rime/rime-wubi)，LGPL-3.0，见 `data/RIME-LICENSE.txt` 和 `data/RIME-AUTHORS.txt`。词库头部保留原作者与修订说明。获取于 2026-10-29。词库作为独立数据文件加载，可以替换。

`data/corpus.txt` 是本项目自编补充语料。程序没有使用微软输入法提取词库。
