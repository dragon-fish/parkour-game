# 原版烘焙光照移植

> 目标：静态几何改用原版 Beast 烘焙的光照贴图，取代实时灯光 + SDFGI 对它的近似；色调映射对准所有者安装的速通圈画质 mod（`_local/mirrors edge/Engine/Shaders/TdToneMappingPixelShader.usf`、`TdToneMapExposurePixelShader.usf`）。
> 依据：2026-10-14 的调研（脚本与证明图在会话 scratchpad `lightmaps/`；软件渲染只用 lightmap 即复现了原版的阴影形状与蓝色阴影，室内走廊 t3 均值 27/38/34 对原版 36/49/47）。

## 数据（从包里读出）

- **StaticMeshComponent 原生尾部**（版本 536）：`LODData[]`，每项 `ShadowMaps[]`、`ShadowVertexBuffers[]`、`FLightMapRef`。
  - `FLightMapRef`：`uint32 type`（0 无、1 顶点 LightMap1D、2 纹理 LightMap2D）+ `LightGuids[]`。
  - type 2：4 组 `(Texture, FVector ScaleVector)` + `CoordinateScale`(2f) + `CoordinateBias`(2f)。第 4 组是 1×1 白色占位（被 cook 剔掉的简单 lightmap），忽略。
  - type 1：`Owner`、方向样本 bulk（每顶点 3 个 BGRA FColor）、4 个 ScaleVector、简单样本 bulk。样本数 = 顶点数。
  - ShadowMap 数组在已查的关卡里全空。
- **BSP**：`ModelComponent` = `Model, ZoneIndex, Elements[]`；每个 element 带自己的 `FLightMapRef`，lightmap 坐标是 Model `FVert.ShadowTexCoord`（组件内 0..1），再经 element 的 scale/bias 映射到 atlas。
- **纹理**：`LightMapTexture2D`，DXT1，多为 1024²，mip 全部内联，无 TFC。教程 33 张约 60 MB，sp01a 约 132 MB。
- **覆盖**：教程 1492 个纹理 LM + 889 个顶点 LM + 2 个无（日晕）；sp01a 3178 + 1053 + 11。不绘制的 DefaultMaterial BSP 面无 LM；个别小 BSP 元素（MI_ConcreteCeiling_01_Red 等）需单独看。
- **动态物体**（InterpActor、SkeletalMeshActor、KActor）无 LODData，原版用 DynamicLightEnvironment。

## 公式（游戏自带 `Engine/Shaders/BasePassPixelShader.usf`、`BasePassVertexShader.usf`、`LocalVertexFactory.usf`）

```
uv_atlas = uv[LightMapCoordinateIndex] * CoordinateScale + CoordinateBias   (xy 顺序)
LM_i     = sRGB_decode(tex_i(uv_atlas)) * ScaleVector_i                    (纹理)
LM_i     = pow(FColor_i.rgb / 255, 2.2) * ScaleVector_i                     (顶点)
B0 = (0, sqrt(2/3), 1/sqrt3), B1 = (-1/sqrt2, -1/sqrt6, 1/sqrt3), B2 = (1/sqrt2, -1/sqrt6, 1/sqrt3)   切线空间，Z 为法线
w_i      = saturate(dot(N_t, B_i)) ^ (2 * DiffusePower)                    DiffusePower 默认 1
Diffuse  = sum(LM_i * w_i) * DiffuseColor * (1 + DiffusePower) / 2
Spec     = sum(LM_i * saturate(dot(R_t, B_i)) ^ (SpecPower + 1)) * SpecularColor
Color    = Emissive + Diffuse + Spec (+ 天光项)
```

`LightMapCoordinateIndex` 缺省为 0，部分网格显式为 1 或 2。

## 做法

1. **提取器**（`docs/mirrors-edge-deep-research/tools/level_extract/`）
   - 解析 StaticMeshComponent 与 ModelComponent 的 `FLightMapRef`，写进 manifest：每个放置的 type、atlas 引用、3 个 ScaleVector、scale/bias、`LightMapCoordinateIndex`；顶点 LM 的每顶点 3 色。
   - atlas 原样导出 DXT1（不重新压缩），走现有纹理导出管线。
   - BSP 导出 `ShadowTexCoord` 与 element 的 lightmap。
2. **网格库**（`tools/me_level/mesh_library.gd`）：每个 surface 带 UV2（取 `LightMapCoordinateIndex` 那一套）；要用法线贴图的带切线。共享网格库的 UV 选择以网格自身属性为准，不随章节变。
3. **着色器**：静态几何一个 lightmap 着色器。
   - 采样 3 张系数纹理；scale/bias 与 ScaleVector 走 `instance uniform`（现在每个放置一个 MeshInstance3D）。
   - `unshaded`：输出 = 自发光 + albedo·E（+ lightmap 高光）。雾照常。
   - 顶点 LM：数据进 CUSTOM / COLOR，每个放置一份网格副本。
   - 节点与材质在生成的场景文件里，编辑器可见。
4. **实时光**：太阳与灯只照玩家身体和动态物体（DynamicLightEnvironment 的近似）；静态几何不再接受实时光与 SDFGI。
5. **去掉重复着色**：静态几何上的 `baker_tint` 关掉，BakerColor 已烘进 lightmap。
6. **色调映射**：曝光与色调曲线移植 mod 版两个 usf（已有 `tools/me_level/me_tone_curve.gd` 可沿用或替换），包括高光压缩。这一步同时修掉 PhysX 通风蒸汽中心截断成纯白的问题。

## 验证

- 结构性测试：`FLightMapRef` 解析（type 1/2、字节对齐到导出末尾）、BSP element 映射、atlas 分配不重叠（xy 顺序）、UV2 选择、生成场景里静态几何挂着 lightmap 材质。
- 视觉：对教程 6 张参考截图（`.private/docs/me-reference-shots`）按区域量化均值比对，从同一机位截图（非 headless）。
- 第一人称和第三人称都看一眼玩家身体在实时光下是否和环境协调。

## 顺序

教程（sp00）做通 → sp01a / sp01b → 其余章节。

## 已知风险

- 法线贴图切线手性随坐标轴翻转而翻转。
- 所有者在关卡外壳里移动过的几何会带着原位置的光照。
- atlas 接缝的双线性渗色。
- macOS / Metal 上 DXT1 是否可用需核实（不行则导出时转 ETC2/ASTC，已开启 `import_etc2_astc`）。
- bias+scale 略超 1 的 30 个分配（推断为 atlas 填充边距）未核实。
