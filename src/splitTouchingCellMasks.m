function summary = splitTouchingCellMasks(inputDir, outputDir, varargin)
% splitTouchingCellMasks Split touching cell objects in binary mask images.
%
%   summary = splitTouchingCellMasks(inputDir, outputDir) reads binary mask
%   images from inputDir, separates likely touching-cell clusters, and writes
%   processed masks to outputDir.
%
%   summary = splitTouchingCellMasks(..., Name, Value) overrides parameters.
%
%   Main steps:
%     1. Opening
%     2. Small-object and boundary-object removal
%     3. Cluster detection using area, solidity, and eccentricity
%     4. Cluster splitting by marker-controlled watershed
%     5. Fallback splitting by concavity-based cutting
%     6. Hole filling and optional boundary smoothing
%
%   Requirements:
%     MATLAB + Image Processing Toolbox
%
%   Example:
%     summary = splitTouchingCellMasks("data/input_masks", "results", ...
%         "FilePattern", "*.jpg", "ShowFigure", true);

    parser = inputParser;
    parser.FunctionName = mfilename;

    addRequired(parser, 'inputDir',  @(x) ischar(x) || isstring(x));
    addRequired(parser, 'outputDir', @(x) ischar(x) || isstring(x));

    addParameter(parser, 'FilePattern', '*.jpg', @(x) ischar(x) || isstring(x));

    % Basic filtering
    addParameter(parser, 'MinArea', 5000, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'Margin', 20, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'SolidityThreshold', 0.90, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(parser, 'EccentricityThreshold', 0.70, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
    addParameter(parser, 'OpeningRadius', 2, @(x) isnumeric(x) && isscalar(x) && x >= 0);

    % Watershed splitting
    addParameter(parser, 'DistanceSigma', 1.2, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'PeakHList', [1.2 0.9 0.6], @(x) isnumeric(x) && isvector(x) && all(x > 0));
    addParameter(parser, 'MarkerMinArea', 5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'RidgeWidth', 4, @(x) isnumeric(x) && isscalar(x) && x >= 0);

    % Concavity splitting
    addParameter(parser, 'CutWidth', 4, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'DefectMinArea', 20, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'SplitMinKeep', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 0));

    % Post-processing and output
    addParameter(parser, 'SmoothSigma', 10.0, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    addParameter(parser, 'ShowFigure', false, @(x) islogical(x) || isnumeric(x));
    addParameter(parser, 'SaveResult', true, @(x) islogical(x) || isnumeric(x));
    addParameter(parser, 'DebugPrint', false, @(x) islogical(x) || isnumeric(x));
    addParameter(parser, 'DebugCutPlot', false, @(x) islogical(x) || isnumeric(x));

    parse(parser, inputDir, outputDir, varargin{:});
    params = parser.Results;

    inputDir = char(inputDir);
    outputDir = char(outputDir);
    params.FilePattern = char(params.FilePattern);

    if isempty(params.SplitMinKeep)
        params.SplitMinKeep = max(round(0.20 * params.MinArea), 20);
    end

    if ~exist(inputDir, 'dir')
        error('Input directory does not exist: %s', inputDir);
    end

    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    files = dir(fullfile(inputDir, params.FilePattern));
    if isempty(files)
        error('No files found: %s', fullfile(inputDir, params.FilePattern));
    end

    records(numel(files), 1) = struct( ...
        'file', "", ...
        'inputObjects', 0, ...
        'filteredObjects', 0, ...
        'detectedClusters', 0, ...
        'finalObjects', 0, ...
        'outputPath', "");

    for k = 1:numel(files)
        fname = files(k).name;
        fpath = fullfile(inputDir, fname);

        if params.DebugPrint
            fprintf('\n[%d/%d] Processing: %s\n', k, numel(files), fname);
        end

        I = imread(fpath);
        bw0 = makeLogicalMask(I);
        [H, W] = size(bw0);

        % 1) Opening
        if params.OpeningRadius > 0
            bw1 = imopen(bw0, strel('disk', params.OpeningRadius));
        else
            bw1 = bw0;
        end

        % 2) Small-object and boundary-object removal
        bw2 = removeSmallAndBoundaryObjects(bw1, params.MinArea, params.Margin);

        % 3) Cluster detection
        [bwClust, L2] = detectClusters( ...
            bw2, params.MinArea, params.SolidityThreshold, params.EccentricityThreshold);

        % 4) Split cluster objects
        finalMask = bw2 & ~bwClust;
        CCclust = bwconncomp(bwClust, 8);

        if params.DebugPrint
            fprintf('  detected clusters: %d\n', CCclust.NumObjects);
        end

        for i = 1:CCclust.NumObjects
            maskI = false(H, W);
            maskI(CCclust.PixelIdxList{i}) = true;

            [splitMask1, success1] = tryMarkerWatershedSplit( ...
                maskI, params.PeakHList, params.DistanceSigma, ...
                params.MarkerMinArea, params.SplitMinKeep, params.RidgeWidth);

            if success1
                finalMask = finalMask | splitMask1;
                if params.DebugPrint
                    fprintf('    cluster %d: watershed split used (RidgeWidth=%g)\n', i, params.RidgeWidth);
                end
                continue;
            end

            [splitMask2, success2] = splitByConcavity( ...
                maskI, params.CutWidth, params.DefectMinArea, ...
                params.SplitMinKeep, params.DebugCutPlot);

            if success2
                finalMask = finalMask | splitMask2;
                if params.DebugPrint
                    fprintf('    cluster %d: concavity split used (CutWidth=%g)\n', i, params.CutWidth);
                end
            else
                finalMask = finalMask | maskI;
                if params.DebugPrint
                    fprintf('    cluster %d: no split, original kept\n', i);
                end
            end
        end

        % 5) Hole fill and optional smoothing
        finalMask = fillEachComponent(finalMask);
        if params.SmoothSigma > 0
            finalMask = smoothEachComponent(finalMask, params.SmoothSigma);
        end

        % 6) Display
        if logical(params.ShowFigure)
            showProcessingFigure(fname, bw0, bw1, bw2, L2, bwClust, finalMask);
        end

        % 7) Save
        outPath = fullfile(outputDir, fname);
        if logical(params.SaveResult)
            imwrite(uint8(finalMask) * 255, outPath);
        end

        records(k).file = string(fname);
        records(k).inputObjects = bwconncomp(bw0, 8).NumObjects;
        records(k).filteredObjects = bwconncomp(bw2, 8).NumObjects;
        records(k).detectedClusters = CCclust.NumObjects;
        records(k).finalObjects = bwconncomp(finalMask, 8).NumObjects;
        records(k).outputPath = string(outPath);
    end

    summary = struct2table(records);

    if params.DebugPrint
        fprintf('\nDone. Split masks written to:\n%s\n', outputDir);
    end
end

%% Local functions

function bw = makeLogicalMask(I)
    % Convert grayscale or RGB mask images to a logical binary mask.
    if ndims(I) == 3
        bw = any(I > 0, 3);
    else
        bw = I > 0;
    end
    bw = logical(bw);
end

function bwOut = removeSmallAndBoundaryObjects(bwIn, minArea, margin)
    [H, W] = size(bwIn);
    L = bwlabel(bwIn, 8);
    stats = regionprops(L, 'Area', 'BoundingBox', 'PixelIdxList');

    bwOut = false(H, W);

    for i = 1:numel(stats)
        A = stats(i).Area;
        bb = stats(i).BoundingBox; % [x y width height]

        x1 = bb(1);
        y1 = bb(2);
        x2 = x1 + bb(3) - 1;
        y2 = y1 + bb(4) - 1;

        inside = (x1 > margin) && (y1 > margin) && ...
                 (x2 <= W - margin) && (y2 <= H - margin);

        if A >= minArea && inside
            bwOut(stats(i).PixelIdxList) = true;
        end
    end
end

function [bwClust, L] = detectClusters(bwIn, minArea, solidityT, eccentricityT)
    [H, W] = size(bwIn);
    L = bwlabel(bwIn, 8);
    stats = regionprops(L, 'Area', 'Solidity', 'Eccentricity', 'PixelIdxList');

    bwClust = false(H, W);

    for i = 1:numel(stats)
        A = stats(i).Area;
        sol = stats(i).Solidity;
        ecc = stats(i).Eccentricity;

        % Large and shape-irregular objects are treated as touching-cell clusters.
        if A > 2 * minArea && (sol < solidityT || ecc > eccentricityT)
            bwClust(stats(i).PixelIdxList) = true;
        end
    end
end

function [splitMask, success] = tryMarkerWatershedSplit(maskI, peakHList, distSigma, markerMinArea, splitMinKeep, ridgeWidth)
    splitMask = maskI;
    success = false;

    D = bwdist(~maskI);
    if distSigma > 0
        Ds = imgaussfilt(D, distSigma);
    else
        Ds = D;
    end

    for h = peakHList
        marks = imextendedmax(Ds, h);
        marks = marks & maskI;
        marks = bwareaopen(marks, markerMinArea);
        marks = imclose(marks, strel('disk', 1));

        CCm = bwconncomp(marks, 8);
        if CCm.NumObjects < 2
            continue;
        end

        Lw = watershed(imimposemin(-Ds, marks | ~maskI));
        Lw(~maskI) = 0;

        ridge = (Lw == 0) & maskI;
        if ridgeWidth > 0
            ridge = imdilate(ridge, strel('disk', ridgeWidth));
        end
        ridge = ridge & maskI;

        tmp = maskI & ~ridge;
        tmp = bwareaopen(tmp, splitMinKeep);
        tmp = fillEachComponent(tmp);

        CCs = bwconncomp(tmp, 8);
        if CCs.NumObjects >= 2
            splitMask = tmp;
            success = true;
            return;
        end
    end
end

function [outMask, success] = splitByConcavity(maskI, cutWidth, defectMinArea, splitMinKeep, debugCutPlot)
    outMask = maskI;
    success = false;

    hullMask = bwconvhull(maskI);
    defect = hullMask & ~maskI;
    defect = bwareaopen(defect, defectMinArea);

    CCd = bwconncomp(defect, 8);
    if CCd.NumObjects < 2
        return;
    end

    stats = regionprops(CCd, 'Area', 'Centroid');
    allAreas = [stats.Area];
    [~, order] = sort(allAreas, 'descend');

    c1 = stats(order(1)).Centroid; % [x y]
    c2 = stats(order(2)).Centroid; % [x y]

    cutLine = makeLineMask(size(maskI), c1, c2);
    if cutWidth > 0
        cutLine = imdilate(cutLine, strel('disk', cutWidth));
    end
    cutLine = cutLine & maskI;

    if logical(debugCutPlot)
        figure;
        tiledlayout(1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
        nexttile; imshow(maskI); title('Cluster mask');
        nexttile; imshow(defect); title('Concavity defect');
        nexttile; imshow(maskI); hold on;
        visboundaries(cutLine, 'Color', 'r', 'LineWidth', 1);
        title(sprintf('Cut line, width = %g', cutWidth));
        hold off;
    end

    tmp = maskI & ~cutLine;
    tmp = bwareaopen(tmp, splitMinKeep);
    tmp = fillEachComponent(tmp);

    CCs = bwconncomp(tmp, 8);
    if CCs.NumObjects >= 2
        outMask = tmp;
        success = true;
    end
end

function lineMask = makeLineMask(imSize, p1, p2)
    % p1, p2 are [x y] coordinates.
    n = max(ceil(norm(p1 - p2) * 4), 10);

    xs = round(linspace(p1(1), p2(1), n));
    ys = round(linspace(p1(2), p2(2), n));

    valid = xs >= 1 & xs <= imSize(2) & ys >= 1 & ys <= imSize(1);
    xs = xs(valid);
    ys = ys(valid);

    lineMask = false(imSize);
    idx = sub2ind(imSize, ys, xs);
    lineMask(idx) = true;
end

function bwOut = fillEachComponent(bwIn)
    L = bwlabel(bwIn, 8);
    bwOut = false(size(bwIn));

    nObj = max(L(:));
    for i = 1:nObj
        comp = (L == i);
        compFill = imfill(comp, 'holes');
        bwOut = bwOut | compFill;
    end
end

function bwOut = smoothEachComponent(bwIn, sigma)
    L = bwlabel(bwIn, 8);
    bwOut = false(size(bwIn));

    nObj = max(L(:));
    for i = 1:nObj
        comp = (L == i);

        % Signed distance map: positive inside the object, negative outside.
        phi = bwdist(~comp) - bwdist(comp);
        phiS = imgaussfilt(phi, sigma);
        compS = phiS > 0;
        compS = imfill(compS, 'holes');

        bwOut = bwOut | compS;
    end
end

function showProcessingFigure(fname, bw0, bw1, bw2, L2, bwClust, finalMask)
    figure('Name', fname, 'Units', 'normalized', 'Position', [0.05 0.08 0.90 0.80]);
    tiledlayout(2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

    nexttile; imshow(bw0); title('(0) Original');
    nexttile; imshow(bw1); title('(1) Opening');
    nexttile; imshow(bw2); title('(2) Small/Boundary removed');

    nexttile;
    imshow(label2rgb(L2, 'jet', 'k', 'shuffle'));
    hold on;
    visboundaries(bwClust, 'Color', 'r', 'LineWidth', 0.8);
    title('(3) Detected clusters');
    hold off;

    nexttile;
    Lfin = bwlabel(finalMask, 8);
    imshow(label2rgb(Lfin, 'parula', 'k', 'shuffle'));
    title('(4) Final segments');

    nexttile; imshow(finalMask); title('(5) Final mask');

    nexttile;
    imshow(overlayPerimeter(bw0, bwperim(finalMask)));
    title('(6) Overlay');

    nexttile;
    histogram(double(finalMask(:)), [0 0.5 1]);
    xlim([-0.5 1.5]);
    title('(7) Pixel histogram');

    drawnow;
end

function rgb = overlayPerimeter(baseMask, perimMask)
    gray = im2double(baseMask);
    if ndims(gray) == 3
        gray = rgb2gray(gray);
    end
    rgb = repmat(gray, 1, 1, 3);

    perimMask = logical(perimMask);
    rgb(:,:,1) = max(rgb(:,:,1), perimMask);
    rgb(:,:,2) = rgb(:,:,2) .* ~perimMask;
    rgb(:,:,3) = rgb(:,:,3) .* ~perimMask;
end
