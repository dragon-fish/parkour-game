# 作者开发笔记

面向作者本人的操作备忘。仓库结构、代码规范等见其他文档；这里只记「怎么用」。

## 私有资产的云同步（overlay 仓）

受授权约束不能进公开仓的资产（Beriul 全套、test.vrm、酒狐、UAL full
动画包、body profiles、本地白盒场景），备份在 GitHub **私有**仓
`dragon-fish/parkour-game-private`，大文件全部走 Git LFS。

结构是「overlay 仓」：私有仓的 git 目录放在
`~/GitRepositories/parkour-game-private.git`，工作树就是本项目目录本身。
两个仓互不干扰——公开仓的 .gitignore 恰好就是两者的分界线。

### 日常同步

```sh
sh ~/GitRepositories/parkour-game-private.git/sync.sh
```

自动 add → commit → push。改了私有资产（调 wrapper、换贴图、加 profile）
之后跑一次即可。

### 新增私有文件

公开仓 .gitignore 对 overlay 仓同样生效、且优先级高于任何白名单，所以
同步走的是 `git add -f` 硬加。**新的私有路径必须手动加进 sync.sh 里的
路径列表**（文件就在上面那个 git 目录下，自带注释）。

### 换新电脑

```sh
git clone git@github.com:dragon-fish/parkour-game.git
git clone --bare git@github.com:dragon-fish/parkour-game-private.git \
    ~/GitRepositories/parkour-game-private.git
git --git-dir=$HOME/GitRepositories/parkour-game-private.git \
    --work-tree=<项目目录> checkout -f master
```

私有文件原地归位（含记录了 bone_map 手术的 .import）。之后在私有 git
目录里重建 sync.sh 或从旧机拷一份。

### LFS 说明

LFS 匹配模式不在工作树的 .gitattributes（会污染公开仓），而在私有仓的
`info/attributes` 里：fbx / vrm / glb / blend / gltf / png / psd。
新增其他大文件类型时改那个文件。

## Beriul 相关的注意事项

- 模型、贴图、材质、wrapper（`assets/models/beriul/`）全部不入库；
  入库的是通用脚本（spring_chains / headless_variant / bone_rotation_damp
  / bone_scale_tweak / matcap_toon.gdshader）和 `scenes/player/tuning/
  beriul_body.json`（挂载数值）。
- 骨骼重定向的 BoneMap 只能活在 `beriul.fbx.import` 里，编辑器重导入
  可能洗掉它——症状是 T-pose + 灰模 + 0.97m 原始身高。洗了就从私有仓
  checkout 恢复 .import 再重启编辑器。
