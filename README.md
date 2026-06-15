[README.md](https://github.com/user-attachments/files/28958432/README.md)
# Touching Cell Mask Splitter

MATLAB code for post-processing binary cell masks and separating likely touching-cell clusters.  
The workflow was designed for binary mask images from cell segmentation pipelines.

## What it does

For each binary mask image, the code performs:

1. Morphological opening
2. Small-object removal
3. Boundary-object removal
4. Cluster detection using area, solidity, and eccentricity
5. Touching-cell splitting using marker-controlled watershed
6. Fallback splitting using concavity-based cutting
7. Hole filling and optional boundary smoothing
8. Saving the final binary mask

## Repository structure

```text
.
├── src/
│   └── splitTouchingCellMasks.m      # Main MATLAB function
├── examples/
│   └── run_example.m                 # Example runner
├── docs/
├── README.md
└── .gitignore
```

## Requirements

- MATLAB
- Image Processing Toolbox

Refactored from a MATLAB Live Script into a reusable function. Please verify on your own mask images before using results for quantitative analysis.

## Usage

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/touching-cell-mask-splitter.git
cd touching-cell-mask-splitter
```

### 2. Run in MATLAB

```matlab
addpath('src');

inputDir = 'path/to/input_masks';
outputDir = 'path/to/output_masks';

summary = splitTouchingCellMasks(inputDir, outputDir, ...
    'FilePattern', '*.jpg', ...
    'ShowFigure', true, ...
    'DebugPrint', true);
```

The output masks are saved in `outputDir` using the original file names.

## Important parameters

| Parameter | Default | Description |
|---|---:|---|
| `FilePattern` | `*.jpg` | Input mask file pattern. Use `*.png`, `*.tif`, etc. if needed. |
| `MinArea` | `5000` | Minimum object area to keep. |
| `Margin` | `20` | Objects touching the image boundary within this margin are removed. |
| `SolidityThreshold` | `0.90` | Low-solidity objects are treated as cluster candidates. |
| `EccentricityThreshold` | `0.70` | High-eccentricity objects are treated as cluster candidates. |
| `OpeningRadius` | `2` | Radius for morphological opening. |
| `DistanceSigma` | `1.2` | Gaussian smoothing sigma for the distance map. |
| `PeakHList` | `[1.2 0.9 0.6]` | Marker-detection thresholds for watershed splitting. |
| `RidgeWidth` | `4` | Thickness of the watershed ridge removed during splitting. |
| `CutWidth` | `4` | Thickness of the concavity-based cut line. |
| `SmoothSigma` | `10.0` | Boundary smoothing sigma. Set to `0` to disable smoothing. |
| `ShowFigure` | `false` | Show processing steps for each image. |
| `SaveResult` | `true` | Save final masks. |
| `DebugPrint` | `false` | Print processing details. |

## Input format

Input images should be binary masks. The function treats every nonzero pixel as foreground. RGB masks are also accepted; any nonzero channel is considered foreground.

## Notes

- The code is intended for mask post-processing, not for raw fluorescence image segmentation.
- Parameters such as `MinArea`, `RidgeWidth`, `CutWidth`, and `SmoothSigma` should be tuned for your cell size and image resolution.
- Avoid committing raw experimental data unless it is intentionally public and properly anonymized.

## Citation

If this code is used in a publication, add your preferred citation information here.

## License

Choose a license before public release. MIT is a common option if you want others to reuse and modify the code.
