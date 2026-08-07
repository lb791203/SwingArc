# SwingArc 精准挥杆数据清单

此目录只保存视频元数据、授权状态和经过审核的清单，不保存原始视频。

## 当前开发素材

`development-inventory.json` 由 `/Users/liangbo/Desktop/test` 中的 8 段原始 MOV 自动生成。库存扫描只读取文件名、时长、帧率和方向修正后的尺寸；不会猜测球员、DTL/Face-on、左右手或授权范围。

当前清单全部是：

- `split: development`
- `authorization: internal-review`
- `annotationPasses: 0`
- `golferID`、`view`、`handedness` 留空

因此这些条目只能用于建立流程和当前算法基线，不能进入模型训练，也不能作为准确度验收集。

## 进入训练前必须补齐

1. 为每位球员分配匿名且稳定的 `golferID`。
2. 确认 `view` 为 `dtl` 或 `face-on`，并填写 `handedness`。
3. 记录明确授权；只有 `training-allowed` 可以进入训练或验证集。
4. P1–P8 由两名标注者独立逐帧标注。分歧超过 2 帧时填写裁定帧。
5. 人体、握把、杆身、杆头和球的帧标签必须由人工复核，`reviewed` 设为 `true` 并记录复核者。
6. 按球员分配 `training`、`validation` 或 `held-out`；同一球员不能跨集合。

原始视频、未审核帧标签和训练产物分别保留在外部视频目录、被忽略的 `labels/` 和 `Training/` 目录中。只有明确授权、审核完成且不含原始视频字节的清单可以提交。

## 重新生成库存

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun swiftc -parse-as-library -framework AVFoundation \
  Tools/PrecisionDataset/PrecisionDatasetModels.swift \
  Tools/PrecisionDataset/PrecisionVideoInventory.swift \
  Tools/PrecisionDataset/InventoryVideos.swift \
  -o /tmp/inventory-precision-videos

/tmp/inventory-precision-videos /Users/liangbo/Desktop/test
```

生成结果需人工对照文件数量和媒体元数据后，再用补丁更新 `development-inventory.json`。
