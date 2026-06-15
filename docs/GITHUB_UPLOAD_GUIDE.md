# GitHub upload guide

## Option A: GitHub website

1. Create a new repository on GitHub.
2. Repository name suggestion: `touching-cell-mask-splitter`.
3. Do not initialize with README if you upload this prepared folder as-is.
4. Upload all files from this folder.
5. Commit with a message such as `Initial MATLAB mask splitter code`.

## Option B: Git command line

```bash
git init
git add .
git commit -m "Initial MATLAB mask splitter code"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/touching-cell-mask-splitter.git
git push -u origin main
```

## Before making it public

- Remove private paths from example files.
- Do not upload unpublished patient/sample data.
- Choose a license if you want other people to reuse the code.
- Add example images only if they are safe to share.
