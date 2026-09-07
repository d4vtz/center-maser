export function clamp(value, min, max) {
    return Math.max(min, Math.min(max, value));
}

export function chooseInsertionSide({
    policy = "balanced",
    leftCount = 0,
    rightCount = 0,
    nextSide = "right",
    focusedZone = null
}) {
    if (policy === "left") return "left";
    if (policy === "right") return "right";

    if (
        policy === "focused-stack" &&
        (focusedZone === "left" || focusedZone === "right")
    ) {
        return focusedZone;
    }

    if (leftCount < rightCount) return "left";
    if (rightCount < leftCount) return "right";
    return nextSide;
}

export function calculateWeightedHeights(weights, totalHeight, gap, minWeight = 0.2) {
    if (!weights.length) return [];

    const usable = Math.max(1, totalHeight - gap * Math.max(0, weights.length - 1));
    const safeWeights = weights.map(weight =>
        Math.max(minWeight, Number.isFinite(weight) ? weight : 1)
    );

    const totalWeight = Math.max(
        0.0001,
        safeWeights.reduce((sum, weight) => sum + weight, 0)
    );

    const heights = safeWeights.map(weight => usable * weight / totalWeight);

    // Preserve the exact available height despite floating point accumulation.
    if (heights.length) {
        const used = heights.slice(0, -1).reduce((sum, height) => sum + height, 0);
        heights[heights.length - 1] = usable - used;
    }

    return heights;
}

export function resizeWeightPair(current, neighbor, delta, minWeight = 0.2) {
    const nextCurrent = current + delta;
    const nextNeighbor = neighbor - delta;

    if (nextCurrent < minWeight || nextNeighbor < minWeight) {
        return null;
    }

    return [nextCurrent, nextNeighbor];
}

export function wrappedIndex(index, length, direction, wrap) {
    if (length <= 0) return -1;

    const candidate = index + direction;

    if (candidate >= 0 && candidate < length) return candidate;
    if (!wrap) return index;

    if (candidate < 0) return length - 1;
    return 0;
}
